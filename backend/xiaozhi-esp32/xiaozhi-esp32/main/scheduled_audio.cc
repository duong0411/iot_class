#include "scheduled_audio.h"
#include "settings.h"
#include "board.h"
#include "application.h"
#include "system_info.h"
#include "demuxer/ogg_demuxer.h"
#include "audio_codec.h"

#include <esp_heap_caps.h>
#include <esp_log.h>
#include <esp_audio_types.h>
#include "decoder/impl/esp_mp3_dec.h"
#include "esp_ae_rate_cvt.h"
#include <algorithm>
#include <ctime>
#include <cstring>
#include <vector>
#include <web_socket.h>
#include <freertos/event_groups.h>

#define TAG "ScheduledAudio"

#define RATE_CVT_CFG(_src_rate, _dest_rate, _channel)        \
    (esp_ae_rate_cvt_cfg_t)                                  \
    {                                                        \
        .src_rate        = (uint32_t)(_src_rate),            \
        .dest_rate       = (uint32_t)(_dest_rate),           \
        .channel         = (uint8_t)(_channel),              \
        .bits_per_sample = ESP_AUDIO_BIT16,                  \
        .complexity      = 2,                                \
        .perf_type       = ESP_AE_RATE_CVT_PERF_TYPE_SPEED,  \
    }

namespace {
constexpr const char* kDefaultApiUrl = "http://duynguyen.io.vn/api/tts/say";
constexpr const char* kDefaultScheduleUrl = "http://duynguyen.io.vn/api/schedule";
constexpr const char* kDefaultText = "Chào buổi sáng! Đây là lời nhắc công việc hôm nay.";
// The whole clip is buffered before decoding, so keep it well inside PSRAM and
// leave room for the WiFi/TLS buffers that are live during the download.
constexpr size_t kMaxAudioBytes = 256 * 1024;  // short TTS/OGG fallback only
// Sliding window for progressive HTTP→MP3 decode (keeps RAM flat for long clips).
constexpr size_t kStreamWindowBytes = 48 * 1024;
constexpr size_t kStreamReadChunk = 2048;
constexpr size_t kStreamLowWater = 12 * 1024;
constexpr size_t kMinFreeInternalHeap = 48 * 1024;
}  // namespace

ScheduledAudio::ScheduledAudio() {
}

ScheduledAudio::~ScheduledAudio() {
    StopAudioStream();
}

std::string ScheduledAudio::PreferHttpUrl(const std::string& url) {
    if (url.rfind("https://", 0) == 0) {
        return "http://" + url.substr(8);
    }
    return url;
}

std::string ScheduledAudio::DeriveOggUrl(const std::string& mp3_url) {
    if (mp3_url.empty()) {
        return "";
    }
    auto q = mp3_url.find('?');
    std::string base = (q == std::string::npos) ? mp3_url : mp3_url.substr(0, q);
    auto dot = base.rfind('.');
    if (dot == std::string::npos) {
        return PreferHttpUrl(base + ".ogg");
    }
    std::string ext = base.substr(dot);
    if (ext == ".ogg" || ext == ".OGG") {
        return PreferHttpUrl(mp3_url);
    }
    if (ext == ".mp3" || ext == ".MP3" || ext == ".wav" || ext == ".WAV") {
        return PreferHttpUrl(base.substr(0, dot) + ".ogg");
    }
    return PreferHttpUrl(base + ".ogg");
}

std::string ScheduledAudio::DeriveWsUrl(const std::string& http_base_url) {
    // http://host/api/schedule → ws://host/ws
    std::string u = PreferHttpUrl(http_base_url);
    if (u.rfind("http://", 0) == 0) {
        u = "ws://" + u.substr(7);
    } else if (u.rfind("https://", 0) == 0) {
        u = "wss://" + u.substr(8);
    }
    auto slash = u.find('/', u.find("://") + 3);
    if (slash != std::string::npos) {
        u = u.substr(0, slash);
    }
    return u + "/ws";
}

std::string ScheduledAudio::ExtractAudioUrlFromJson(const std::string& json) {
    cJSON* root = cJSON_Parse(json.c_str());
    if (root == nullptr) {
        return "";
    }

    std::string audio_url;
    auto try_get = [&](cJSON* obj) {
        if (obj == nullptr || !cJSON_IsObject(obj)) {
            return;
        }
        cJSON* url = cJSON_GetObjectItem(obj, "audioUrl");
        if (!cJSON_IsString(url)) {
            url = cJSON_GetObjectItem(obj, "audio_url");
        }
        if (cJSON_IsString(url) && url->valuestring != nullptr && url->valuestring[0] != '\0') {
            audio_url = url->valuestring;
        }
    };

    try_get(root);
    try_get(cJSON_GetObjectItem(root, "data"));
    cJSON_Delete(root);
    return audio_url;
}

void ScheduledAudio::Initialize() {
    Settings settings("schedule", false);
    enabled_ = settings.GetBool("enabled", true);
    hour_ = settings.GetInt("hour", 7);
    minute_ = settings.GetInt("minute", 0);
    text_ = settings.GetString("text", kDefaultText);
    api_url_ = settings.GetString("api_url", kDefaultApiUrl);
    if (api_url_.empty() || api_url_.find("generate-audio") != std::string::npos) {
        api_url_ = kDefaultApiUrl;
    }
    api_url_ = PreferHttpUrl(api_url_);
    schedule_url_ = PreferHttpUrl(kDefaultScheduleUrl);

    ESP_LOGI(TAG, "ScheduledAudio initialized: enabled=%d, time=%02d:%02d, url=%s",
             enabled_, hour_, minute_, api_url_.c_str());
}

void ScheduledAudio::FetchRemoteScheduleAsync() {
    if (schedule_fetch_in_progress_.exchange(true)) {
        return;
    }

    BaseType_t ret = xTaskCreate([](void* arg) {
        ScheduledAudio* self = static_cast<ScheduledAudio*>(arg);
        self->FetchRemoteScheduleTask();
        self->schedule_fetch_in_progress_.store(false);
        vTaskDelete(NULL);
    }, "sched_fetch", 6144, this, 3, nullptr);

    if (ret != pdPASS) {
        schedule_fetch_in_progress_.store(false);
        ESP_LOGW(TAG, "Failed to create schedule fetch task");
    }
}

void ScheduledAudio::FetchRemoteScheduleTask() {
    auto network = Board::GetInstance().GetNetwork();
    if (network == nullptr) {
        return;
    }

    auto http = network->CreateHttp(0);
    if (http == nullptr) {
        return;
    }
    http->SetTimeout(10000);
    http->SetKeepAlive(false);
    if (!http->Open("GET", schedule_url_)) {
        ESP_LOGW(TAG, "Failed to fetch remote schedule from %s", schedule_url_.c_str());
        return;
    }

    if (http->GetStatusCode() != 200) {
        ESP_LOGW(TAG, "Schedule API status=%d", http->GetStatusCode());
        http->Close();
        return;
    }

    std::string body = http->ReadAll();
    http->Close();
    ESP_LOGI(TAG, "Backend schedule JSON: %s", body.c_str());

    cJSON* root = cJSON_Parse(body.c_str());
    if (root == nullptr) {
        return;
    }

    cJSON* schedules = cJSON_GetObjectItem(root, "schedules");
    std::vector<RemoteSchedule> parsed;
    if (cJSON_IsArray(schedules)) {
        int size = cJSON_GetArraySize(schedules);
        parsed.reserve(size);
        for (int i = 0; i < size; i++) {
            cJSON* item = cJSON_GetArrayItem(schedules, i);
            RemoteSchedule entry;
            cJSON* enabled = cJSON_GetObjectItem(item, "enabled");
            cJSON* hour = cJSON_GetObjectItem(item, "hour");
            cJSON* minute = cJSON_GetObjectItem(item, "minute");
            cJSON* prompt = cJSON_GetObjectItem(item, "prompt");
            if (!cJSON_IsString(prompt)) {
                prompt = cJSON_GetObjectItem(item, "text");
            }
            cJSON* id = cJSON_GetObjectItem(item, "id");
            cJSON* audio = cJSON_GetObjectItem(item, "audio_url");
            if (!cJSON_IsString(audio)) {
                audio = cJSON_GetObjectItem(item, "audioUrl");
            }
            cJSON* opus = cJSON_GetObjectItem(item, "opus_url");
            if (!cJSON_IsString(opus)) {
                opus = cJSON_GetObjectItem(item, "opusUrl");
            }

            entry.hour = cJSON_IsNumber(hour) ? hour->valueint
                         : (cJSON_IsString(hour) ? atoi(hour->valuestring) : -1);
            entry.minute = cJSON_IsNumber(minute) ? minute->valueint
                           : (cJSON_IsString(minute) ? atoi(minute->valuestring) : -1);
            entry.enabled = cJSON_IsBool(enabled) ? cJSON_IsTrue(enabled) : true;
            if (cJSON_IsString(prompt) && prompt->valuestring != nullptr) {
                entry.prompt = prompt->valuestring;
            }
            if (cJSON_IsString(id) && id->valuestring != nullptr) {
                entry.id = id->valuestring;
            } else {
                entry.id = "sched";
            }
            if (cJSON_IsString(audio) && audio->valuestring != nullptr) {
                entry.audio_url = PreferHttpUrl(audio->valuestring);
            }
            if (cJSON_IsString(opus) && opus->valuestring != nullptr) {
                entry.opus_url = PreferHttpUrl(opus->valuestring);
            } else if (!entry.audio_url.empty()) {
                entry.opus_url = DeriveOggUrl(entry.audio_url);
            }
            if (entry.hour >= 0 && entry.minute >= 0) {
                parsed.push_back(std::move(entry));
            }
        }
    }
    cJSON_Delete(root);

    {
        std::lock_guard<std::mutex> lock(remote_mutex_);
        remote_schedules_ = std::move(parsed);
    }
}

void ScheduledAudio::ArmPending(const std::string& trigger_key, const std::string& prompt,
                                const std::string& audio_url, const std::string& opus_url) {
    pending_due_ = true;
    pending_trigger_key_ = trigger_key;
    time(&pending_deadline_);
    // Catch-up window: keep retrying for 3 minutes after the match so a busy
    // conversation / listening session does not silently drop the announcement.
    pending_deadline_ += 180;
    if (!prompt.empty()) {
        text_ = prompt;
    }
    pending_audio_url_ = audio_url;
    pending_opus_url_ = opus_url.empty() ? DeriveOggUrl(audio_url) : PreferHttpUrl(opus_url);
    ESP_LOGI(TAG, "Armed schedule '%s' audio=%s opus=%s text=%s (retry until idle, 3min)",
             trigger_key.c_str(), pending_audio_url_.c_str(), pending_opus_url_.c_str(), text_.c_str());
}

bool ScheduledAudio::TryStartPending(const char* reason) {
    if (!pending_due_ || is_playing_.load()) {
        return false;
    }

    time_t now;
    time(&now);
    if (pending_deadline_ > 0 && now > pending_deadline_) {
        ESP_LOGW(TAG, "Pending schedule '%s' expired without playing", pending_trigger_key_.c_str());
        pending_due_ = false;
        pending_trigger_key_.clear();
        pending_audio_url_.clear();
        pending_opus_url_.clear();
        pending_deadline_ = 0;
        return false;
    }

    auto device_state = Application::GetInstance().GetDeviceState();
    if (device_state != kDeviceStateIdle) {
        static int busy_log = 0;
        if ((++busy_log % 5) == 1) {
            ESP_LOGW(TAG, "Schedule pending (%s), waiting for idle (state=%d)",
                     reason ? reason : "retry", (int)device_state);
        }
        return false;
    }

    ESP_LOGI(TAG, "Starting pending schedule (%s): %s", reason ? reason : "retry",
             pending_trigger_key_.c_str());
    if (!TriggerAudioStream()) {
        return false;
    }
    // Mark consumed only after the play task actually starts. If playback fails
    // the task clears last_trigger_id_ so the remaining catch-up window can retry.
    last_trigger_id_ = pending_trigger_key_;
    return true;
}

void ScheduledAudio::CheckSchedule() {
    if (!enabled_) {
        return;
    }

    time_t now;
    time(&now);
    struct tm timeinfo;
    localtime_r(&now, &timeinfo);

    // Verify time is synchronized (tm_year >= 120 means year >= 2020)
    if (timeinfo.tm_year < 120) {
        static int unsynced_log_count = 0;
        if (++unsynced_log_count % 15 == 0) {
            ESP_LOGW(TAG, "System clock waiting for SNTP sync (tm_year=%d)", timeinfo.tm_year + 1900);
        }
        return;
    }

    // Refreshing every 10s put a DNS lookup plus an HTTP GET in the middle of TTS
    // playback, which starved the audio pipeline. The schedule only has
    // minute resolution, so once a minute is plenty, and only while idle.
    // First tick after sync: fetch immediately so we never miss the next minute.
    static int poll_counter = 0;
    static bool fetched_once_ = false;
    if (!fetched_once_ || poll_counter++ % 60 == 0) {
        auto device_state = Application::GetInstance().GetDeviceState();
        if (is_playing_.load() || device_state != kDeviceStateIdle) {
            ESP_LOGD(TAG, "Skip schedule refresh (playing=%d, state=%d)",
                     (int)is_playing_.load(), (int)device_state);
        } else {
            fetched_once_ = true;
            ESP_LOGI(TAG, "Current SNTP time: %02d:%02d:%02d. Refreshing remote schedule...",
                     timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
            FetchRemoteScheduleAsync();
        }
    }

    // Retry a previously armed announcement as soon as the device is idle.
    if (pending_due_) {
        TryStartPending("catch-up");
    }

    std::vector<RemoteSchedule> schedules;
    {
        std::lock_guard<std::mutex> lock(remote_mutex_);
        schedules = remote_schedules_;
    }

    for (const auto& item : schedules) {
        if (!item.enabled || item.hour != timeinfo.tm_hour || item.minute != timeinfo.tm_min) {
            continue;
        }

        std::string trigger_key = item.id + "_" + std::to_string(timeinfo.tm_mday) + "_" +
                                  std::to_string(item.hour) + "_" + std::to_string(item.minute);
        if (last_trigger_id_ == trigger_key || pending_trigger_key_ == trigger_key) {
            continue;
        }

        ESP_LOGI(TAG, "MATCHED backend schedule '%s' at %02d:%02d audio=%s opus=%s text=%s",
                 item.id.c_str(), item.hour, item.minute,
                 item.audio_url.c_str(), item.opus_url.c_str(), item.prompt.c_str());
        ArmPending(trigger_key, item.prompt, item.audio_url, item.opus_url);
        TryStartPending("match");
        return;
    }

    if (timeinfo.tm_hour == hour_ && timeinfo.tm_min == minute_) {
        std::string local_key = std::string("local_") + std::to_string(timeinfo.tm_mday) + "_" +
                                std::to_string(hour_) + "_" + std::to_string(minute_);
        if (last_trigger_id_ != local_key && pending_trigger_key_ != local_key &&
            last_trigger_day_ != timeinfo.tm_mday) {
            last_trigger_day_ = timeinfo.tm_mday;
            ESP_LOGI(TAG, "Local schedule triggered at %02d:%02d", hour_, minute_);
            ArmPending(local_key, text_, "");
            TryStartPending("local");
        }
    }
}

bool ScheduledAudio::TriggerAudioStream() {
    if (is_playing_.load()) {
        ESP_LOGW(TAG, "Scheduled audio is already playing");
        return false;
    }

    auto device_state = Application::GetInstance().GetDeviceState();
    if (device_state != kDeviceStateIdle) {
        ESP_LOGW(TAG, "Device is not idle (state=%d), deferring scheduled audio", (int)device_state);
        return false;
    }

    is_playing_.store(true);
    stop_requested_.store(false);

    BaseType_t ret = xTaskCreate([](void* arg) {
        ScheduledAudio* self = static_cast<ScheduledAudio*>(arg);
        self->FetchAndPlayStreamTask();
        vTaskDelete(NULL);
    }, "sched_audio", 16384, this, 4, &stream_task_handle_);

    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create scheduled audio task");
        is_playing_.store(false);
        stream_task_handle_ = nullptr;
        return false;
    }

    return true;
}

void ScheduledAudio::StopAudioStream() {
    if (is_playing_.load()) {
        stop_requested_.store(true);
        int timeout = 50;
        while (is_playing_.load() && timeout-- > 0) {
            vTaskDelay(pdMS_TO_TICKS(50));
        }
    }
}

bool ScheduledAudio::DownloadToBuffer(const std::string& url, std::vector<uint8_t>& out) {
    auto& board = Board::GetInstance();
    auto network = board.GetNetwork();
    if (network == nullptr) {
        ESP_LOGE(TAG, "Network interface not available");
        return false;
    }

    // Keep WiFi awake during download; modem sleep can stall long HTTP GETs.
    board.SetPowerSaveLevel(PowerSaveLevel::PERFORMANCE);

    auto http = network->CreateHttp(0);
    if (http == nullptr) {
        ESP_LOGE(TAG, "Failed to create HTTP client");
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    std::string request_url = PreferHttpUrl(url);
    http->SetTimeout(20000);
    http->SetKeepAlive(false);
    http->SetHeader("Connection", "close");
    http->SetHeader("Accept", "audio/mpeg, application/octet-stream, */*");

    ESP_LOGI(TAG, "Downloading audio from %s", request_url.c_str());
    if (!http->Open("GET", request_url)) {
        ESP_LOGE(TAG, "Failed to open %s", request_url.c_str());
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    int status = http->GetStatusCode();
    ESP_LOGI(TAG, "Audio download status=%d body_len=%u", status, (unsigned)http->GetBodyLength());
    if (status != 200) {
        ESP_LOGE(TAG, "Audio download status=%d", status);
        http->Close();
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    out.clear();
    size_t expected = http->GetBodyLength();
    if (expected > 0) {
        // Do not trust Content-Length blindly; a bogus value would reserve
        // (and fail on) an arbitrarily large block.
        out.reserve(std::min(expected, kMaxAudioBytes));
    }

    constexpr size_t kChunk = 1024;
    char buffer[kChunk];
    while (!stop_requested_.load()) {
        int n = http->Read(buffer, kChunk);
        if (n < 0) {
            ESP_LOGE(TAG, "Audio download read error: %d", n);
            break;
        }
        if (n == 0) {
            break;
        }
        out.insert(out.end(), buffer, buffer + n);
        if (expected > 0 && out.size() >= expected) {
            break;
        }
        // Guard against runaway downloads.
        if (out.size() > kMaxAudioBytes) {
            ESP_LOGE(TAG, "Audio download exceeded %uKB, aborting", (unsigned)(kMaxAudioBytes / 1024));
            break;
        }
    }
    http->Close();
    board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);

    if (out.empty()) {
        ESP_LOGE(TAG, "Downloaded empty audio body");
        return false;
    }

    ESP_LOGI(TAG, "Downloaded %u audio bytes (free internal=%u, free psram=%u)",
             (unsigned)out.size(), (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    return true;
}

bool ScheduledAudio::PlayDownloadedAudio(const std::vector<uint8_t>& data) {
    if (data.empty() || stop_requested_.load()) {
        return false;
    }

    // UI only — no ding sound (sound defaults to empty).
    Application::GetInstance().Alert("Phát lịch tự động", text_.c_str(), "speaker");

    bool looks_ogg = data.size() >= 4 && memcmp(data.data(), "OggS", 4) == 0;
    bool looks_id3 = data.size() >= 10 && data[0] == 'I' && data[1] == 'D' && data[2] == '3';
    size_t mp3_offset = 0;
    if (looks_id3) {
        size_t tag_size = ((data[6] & 0x7f) << 21) | ((data[7] & 0x7f) << 14) |
                          ((data[8] & 0x7f) << 7) | (data[9] & 0x7f);
        mp3_offset = 10 + tag_size;
        if (mp3_offset >= data.size()) {
            mp3_offset = 0;
        }
    }
    bool looks_mp3 = (data.size() > mp3_offset + 1) &&
                     data[mp3_offset] == 0xFF && (data[mp3_offset + 1] & 0xE0) == 0xE0;

    bool ok = false;
    if (looks_ogg) {
        auto demuxer = std::make_unique<OggDemuxer>();
        demuxer->OnDemuxerFinished([this](const uint8_t* payload, int sample_rate, size_t len) {
            if (stop_requested_.load()) {
                return;
            }
            auto packet = std::make_unique<AudioStreamPacket>();
            packet->sample_rate = sample_rate;
            packet->frame_duration = 60;
            packet->payload.assign(payload, payload + len);
            Application::GetInstance().GetAudioService().PushPacketToDecodeQueue(std::move(packet), true);
        });
        demuxer->Reset();
        demuxer->Process(data.data(), data.size());
        WaitForPlaybackIdle();
        ok = true;
    } else if (looks_mp3 || looks_id3) {
        // Decode MP3 here and write PCM straight to the speaker — never touch
        // OpusCodecTask (that path broke wake/ASR when shared).
        ok = PlayMp3DirectToSpeaker(data, mp3_offset);
    } else if (data[0] == '{' || data[0] == '[') {
        std::string json(reinterpret_cast<const char*>(data.data()), data.size());
        ESP_LOGW(TAG, "Expected audio bytes but got JSON: %s", json.c_str());
        ok = false;
    } else {
        ESP_LOGW(TAG, "Unknown audio header %02X %02X, trying MP3 direct", data[0],
                 data.size() > 1 ? data[1] : 0);
        ok = PlayMp3DirectToSpeaker(data, 0);
    }

    Application::GetInstance().DismissAlert();
    return ok;
}

bool ScheduledAudio::PlayMp3DirectToSpeaker(const std::vector<uint8_t>& data, size_t offset) {
    if (offset >= data.size()) {
        return false;
    }

    auto* codec = Board::GetInstance().GetAudioCodec();
    if (codec == nullptr) {
        ESP_LOGE(TAG, "No audio codec for scheduled MP3");
        return false;
    }

    void* mp3_decoder = nullptr;
    auto open_ret = esp_mp3_dec_open(nullptr, 0, &mp3_decoder);
    if (open_ret != ESP_AUDIO_ERR_OK || mp3_decoder == nullptr) {
        ESP_LOGE(TAG, "esp_mp3_dec_open failed: %d", open_ret);
        return false;
    }

    auto& audio_service = Application::GetInstance().GetAudioService();
    // Must go through AudioService so the power timer does not kill TX mid-clip
    // (direct codec->OutputData never updates last_output_time_).
    audio_service.TouchOutputActivity();
    ESP_LOGI(TAG, "Playing scheduled MP3 via AudioService (%u bytes, offset=%u)",
             (unsigned)data.size(), (unsigned)offset);

    esp_ae_rate_cvt_handle_t resampler = nullptr;
    int resampler_rate = 0;
    int dest_rate = codec->output_sample_rate();
    size_t pos = offset;
    int frames = 0;

    while (pos < data.size() && !stop_requested_.load()) {
        esp_audio_dec_in_raw_t raw = {
            .buffer = const_cast<uint8_t*>(data.data() + pos),
            .len = (uint32_t)(data.size() - pos),
            .consumed = 0,
            .frame_recover = ESP_AUDIO_DEC_RECOVERY_NONE,
        };
        std::vector<int16_t> pcm_buf(2304);
        esp_audio_dec_out_frame_t out_frame = {
            .buffer = (uint8_t*)pcm_buf.data(),
            .len = (uint32_t)(pcm_buf.size() * sizeof(int16_t)),
            .decoded_size = 0,
        };
        esp_audio_dec_info_t dec_info = {};
        auto ret = esp_mp3_dec_decode(mp3_decoder, &raw, &out_frame, &dec_info);
        if (ret != ESP_AUDIO_ERR_OK || out_frame.decoded_size == 0) {
            break;
        }
        if (raw.consumed == 0) {
            ESP_LOGW(TAG, "MP3 consumed 0, stop");
            break;
        }
        pos += raw.consumed;

        int samples = out_frame.decoded_size / sizeof(int16_t);
        pcm_buf.resize(samples);
        if (dec_info.channel == 2) {
            std::vector<int16_t> mono(samples / 2);
            for (size_t i = 0; i < mono.size(); i++) {
                mono[i] = (int16_t)(((int32_t)pcm_buf[i * 2] + pcm_buf[i * 2 + 1]) / 2);
            }
            pcm_buf = std::move(mono);
        }

        int src_rate = dec_info.sample_rate > 0 ? dec_info.sample_rate : 24000;
        if (src_rate != dest_rate) {
            if (resampler == nullptr || resampler_rate != src_rate) {
                if (resampler != nullptr) {
                    esp_ae_rate_cvt_close(resampler);
                    resampler = nullptr;
                }
                esp_ae_rate_cvt_cfg_t cvt_cfg = RATE_CVT_CFG(src_rate, dest_rate, ESP_AUDIO_MONO);
                esp_ae_rate_cvt_open(&cvt_cfg, &resampler);
                resampler_rate = src_rate;
            }
            if (resampler != nullptr) {
                uint32_t max_out = 0;
                esp_ae_rate_cvt_get_max_out_sample_num(resampler, pcm_buf.size(), &max_out);
                std::vector<int16_t> resampled(max_out);
                uint32_t actual = max_out;
                esp_ae_rate_cvt_process(resampler, (esp_ae_sample_t)pcm_buf.data(), pcm_buf.size(),
                                        (esp_ae_sample_t)resampled.data(), &actual);
                resampled.resize(actual);
                pcm_buf = std::move(resampled);
            }
        }

        audio_service.PlayPcm(std::move(pcm_buf));
        frames++;
    }

    if (resampler != nullptr) {
        esp_ae_rate_cvt_close(resampler);
    }
    esp_mp3_dec_close(mp3_decoder);
    WaitForPlaybackIdle();
    ESP_LOGI(TAG, "Scheduled MP3 done (%d frames)", frames);
    return frames > 0;
}

void ScheduledAudio::WaitForPlaybackIdle() {
    // Give decode/playback queues a moment to leave idle after enqueue.
    vTaskDelay(pdMS_TO_TICKS(200));
    int timeout_ms = 60000;
    while (timeout_ms > 0 && !stop_requested_.load()) {
        if (Application::GetInstance().GetAudioService().IsPlaybackIdle()) {
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
        timeout_ms -= 100;
    }
}

bool ScheduledAudio::PlayAudioFromUrl(const std::string& url) {
    // Prefer Ogg Opus (same decode path as Xiaozhi cloud TTS) to avoid MP3 underrun stutter.
    ESP_LOGI(TAG, "Playing schedule audio (prefer Opus) free int=%u psram=%u",
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    Application::GetInstance().Alert("Phát lịch tự động", text_.c_str(), "speaker");

    std::string opus_url = pending_opus_url_;
    if (opus_url.empty()) {
        opus_url = DeriveOggUrl(url);
    }

    bool ok = false;
    if (!opus_url.empty()) {
        ESP_LOGI(TAG, "Trying Ogg Opus HTTP stream: %s", opus_url.c_str());
        ok = StreamOpusOggFromUrl(opus_url);
    }
    if (!ok && !url.empty()) {
        ESP_LOGW(TAG, "Ogg Opus failed — try AloT WS Opus push");
        ok = StreamOpusViaWebSocket(url);
    }
    if (!ok && !url.empty()) {
        ESP_LOGW(TAG, "Opus paths failed — fallback HTTP MP3 stream: %s", url.c_str());
        ok = StreamMp3FromUrl(url);
    }

    Application::GetInstance().DismissAlert();
    return ok;
}

bool ScheduledAudio::StreamOpusOggFromUrl(const std::string& url) {
    auto& board = Board::GetInstance();
    auto network = board.GetNetwork();
    if (network == nullptr) {
        return false;
    }

    board.SetPowerSaveLevel(PowerSaveLevel::PERFORMANCE);
    auto http = network->CreateHttp(0);
    if (http == nullptr) {
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    std::string request_url = PreferHttpUrl(url);
    http->SetTimeout(30000);
    http->SetKeepAlive(false);
    http->SetHeader("Connection", "close");
    http->SetHeader("Accept", "audio/ogg, application/ogg, */*");

    ESP_LOGI(TAG, "HTTP Ogg Opus open %s", request_url.c_str());
    if (!http->Open("GET", request_url)) {
        ESP_LOGE(TAG, "Ogg stream open failed");
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }
    int status = http->GetStatusCode();
    size_t body_len = http->GetBodyLength();
    ESP_LOGI(TAG, "Ogg HTTP status=%d content_length=%u", status, (unsigned)body_len);
    if (status != 200) {
        http->Close();
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    auto& audio_service = Application::GetInstance().GetAudioService();
    audio_service.ResetDecoder();
    audio_service.TouchOutputActivity();

    auto demuxer = std::make_unique<OggDemuxer>();
    std::atomic<int> frames{0};
    demuxer->OnDemuxerFinished([&](const uint8_t* payload, int sample_rate, size_t len) {
        if (stop_requested_.load() || payload == nullptr || len == 0) {
            return;
        }
        auto packet = std::make_unique<AudioStreamPacket>();
        packet->sample_rate = sample_rate > 0 ? sample_rate : 16000;
        packet->frame_duration = 60;
        packet->payload.assign(payload, payload + len);
        // wait=true → back-pressure like cloud pacing (~2.4s decode buffer)
        if (audio_service.PushPacketToDecodeQueue(std::move(packet), true)) {
            frames.fetch_add(1);
        }
    });
    demuxer->Reset();

    constexpr size_t kRead = 2048;
    char read_buf[kRead];
    size_t total_read = 0;
    bool got_ogg = false;

    while (!stop_requested_.load()) {
        int n = http->Read(read_buf, kRead);
        if (n < 0) {
            ESP_LOGE(TAG, "Ogg HTTP read error %d", n);
            break;
        }
        if (n == 0) {
            break;
        }
        if (!got_ogg && n >= 4 && memcmp(read_buf, "OggS", 4) == 0) {
            got_ogg = true;
        }
        demuxer->Process(reinterpret_cast<const uint8_t*>(read_buf), (size_t)n);
        total_read += (size_t)n;
        if (body_len > 0 && total_read >= body_len) {
            break;
        }
    }

    http->Close();
    board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
    WaitForPlaybackIdle();

    int frame_count = frames.load();
    ESP_LOGI(TAG, "Ogg Opus stream done (frames=%d, bytes=%u, got_ogg=%d)",
             frame_count, (unsigned)total_read, (int)got_ogg);
    return frame_count > 0 && got_ogg;
}

bool ScheduledAudio::StreamOpusViaWebSocket(const std::string& mp3_or_audio_url) {
    auto& board = Board::GetInstance();
    auto network = board.GetNetwork();
    if (network == nullptr) {
        return false;
    }

    std::string ws_url = DeriveWsUrl(schedule_url_);
    ESP_LOGI(TAG, "WS Opus connect %s for %s", ws_url.c_str(), mp3_or_audio_url.c_str());

    board.SetPowerSaveLevel(PowerSaveLevel::PERFORMANCE);
    auto ws = network->CreateWebSocket(1);
    if (ws == nullptr) {
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    EventGroupHandle_t eg = xEventGroupCreate();
    const EventBits_t BIT_DONE = BIT0;
    const EventBits_t BIT_FAIL = BIT1;
    std::atomic<int> frames{0};
    std::atomic<int> sample_rate{16000};
    auto& audio_service = Application::GetInstance().GetAudioService();

    ws->OnData([&](const char* data, size_t len, bool binary) {
        if (binary) {
            if (stop_requested_.load() || data == nullptr || len == 0) {
                return;
            }
            auto packet = std::make_unique<AudioStreamPacket>();
            packet->sample_rate = sample_rate.load();
            packet->frame_duration = 60;
            packet->payload.assign(reinterpret_cast<const uint8_t*>(data),
                                   reinterpret_cast<const uint8_t*>(data) + len);
            if (audio_service.PushPacketToDecodeQueue(std::move(packet), true)) {
                frames.fetch_add(1);
            }
            return;
        }

        cJSON* root = cJSON_ParseWithLength(data, len);
        if (root == nullptr) {
            return;
        }
        cJSON* type = cJSON_GetObjectItem(root, "type");
        if (cJSON_IsString(type) && strcmp(type->valuestring, "tts") == 0) {
            cJSON* state = cJSON_GetObjectItem(root, "state");
            cJSON* sr = cJSON_GetObjectItem(root, "sample_rate");
            if (cJSON_IsNumber(sr)) {
                sample_rate.store(sr->valueint);
            }
            if (cJSON_IsString(state)) {
                if (strcmp(state->valuestring, "start") == 0) {
                    audio_service.ResetDecoder();
                    audio_service.TouchOutputActivity();
                    ESP_LOGI(TAG, "WS Opus tts start");
                } else if (strcmp(state->valuestring, "stop") == 0) {
                    ESP_LOGI(TAG, "WS Opus tts stop");
                    xEventGroupSetBits(eg, BIT_DONE);
                }
            }
            cJSON* err = cJSON_GetObjectItem(root, "error");
            if (cJSON_IsString(err)) {
                ESP_LOGE(TAG, "WS Opus error: %s", err->valuestring);
                xEventGroupSetBits(eg, BIT_FAIL);
            }
        }
        cJSON_Delete(root);
    });

    ws->OnDisconnected([eg]() {
        xEventGroupSetBits(eg, BIT_DONE | BIT_FAIL);
    });
    ws->OnError([eg](int) {
        xEventGroupSetBits(eg, BIT_FAIL);
    });

    if (!ws->Connect(ws_url.c_str())) {
        ESP_LOGE(TAG, "WS Opus connect failed");
        vEventGroupDelete(eg);
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    cJSON* req = cJSON_CreateObject();
    cJSON_AddStringToObject(req, "type", "opus_play");
    cJSON_AddStringToObject(req, "audio_url", mp3_or_audio_url.c_str());
    cJSON_AddStringToObject(req, "prompt", text_.c_str());
    char* req_str = cJSON_PrintUnformatted(req);
    bool sent = ws->Send(req_str ? req_str : "{}");
    if (req_str) {
        cJSON_free(req_str);
    }
    cJSON_Delete(req);
    if (!sent) {
        ws->Close();
        vEventGroupDelete(eg);
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    // Long YouTube clips — wait up to 30 minutes for stream end.
    EventBits_t bits = xEventGroupWaitBits(eg, BIT_DONE | BIT_FAIL, pdTRUE, pdFALSE, pdMS_TO_TICKS(30 * 60 * 1000));
    ws->Close();
    vEventGroupDelete(eg);
    WaitForPlaybackIdle();
    board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);

    int frame_count = frames.load();
    ESP_LOGI(TAG, "WS Opus done frames=%d bits=0x%x", frame_count, (unsigned)bits);
    return frame_count > 0;
}

bool ScheduledAudio::StreamMp3FromUrl(const std::string& url) {
    auto& board = Board::GetInstance();
    auto* codec = board.GetAudioCodec();
    auto network = board.GetNetwork();
    if (codec == nullptr || network == nullptr) {
        return false;
    }

    board.SetPowerSaveLevel(PowerSaveLevel::PERFORMANCE);
    auto http = network->CreateHttp(0);
    if (http == nullptr) {
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    std::string request_url = PreferHttpUrl(url);
    http->SetTimeout(30000);
    http->SetKeepAlive(false);
    http->SetHeader("Connection", "close");
    http->SetHeader("Accept", "audio/mpeg, application/octet-stream, */*");

    ESP_LOGI(TAG, "HTTP stream open %s", request_url.c_str());
    if (!http->Open("GET", request_url)) {
        ESP_LOGE(TAG, "Stream open failed");
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }
    int status = http->GetStatusCode();
    size_t body_len = http->GetBodyLength();
    ESP_LOGI(TAG, "HTTP stream status=%d content_length=%u", status, (unsigned)body_len);
    if (status != 200) {
        http->Close();
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    void* mp3_decoder = nullptr;
    if (esp_mp3_dec_open(nullptr, 0, &mp3_decoder) != ESP_AUDIO_ERR_OK || mp3_decoder == nullptr) {
        ESP_LOGE(TAG, "esp_mp3_dec_open failed");
        http->Close();
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    auto& audio_service = Application::GetInstance().GetAudioService();
    audio_service.TouchOutputActivity();

    if (heap_caps_get_free_size(MALLOC_CAP_INTERNAL) < kMinFreeInternalHeap) {
        ESP_LOGE(TAG, "Abort stream: low internal heap (%u)",
                 (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
        esp_mp3_dec_close(mp3_decoder);
        http->Close();
        board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
        return false;
    }

    std::vector<uint8_t> window;
    window.reserve(kStreamWindowBytes);
    char read_buf[kStreamReadChunk];
    esp_ae_rate_cvt_handle_t resampler = nullptr;
    int resampler_rate = 0;
    int dest_rate = codec->output_sample_rate();
    int frames = 0;
    bool eof = false;
    bool skipped_id3 = false;
    size_t total_read = 0;

    auto fill_window = [&]() -> bool {
        while (!eof && window.size() < kStreamWindowBytes && !stop_requested_.load()) {
            if (heap_caps_get_free_size(MALLOC_CAP_INTERNAL) < (kMinFreeInternalHeap / 2)) {
                ESP_LOGW(TAG, "Pause fill: low heap");
                break;
            }
            size_t space = kStreamWindowBytes - window.size();
            size_t want = std::min(space, kStreamReadChunk);
            int n = http->Read(read_buf, want);
            if (n < 0) {
                ESP_LOGE(TAG, "HTTP stream read error %d", n);
                eof = true;
                break;
            }
            if (n == 0) {
                eof = true;
                break;
            }
            window.insert(window.end(), read_buf, read_buf + n);
            total_read += (size_t)n;
            if (body_len > 0 && total_read >= body_len) {
                eof = true;
                break;
            }
        }
        return !window.empty();
    };

    auto skip_id3_if_needed = [&]() {
        if (skipped_id3 || window.size() < 10) {
            return;
        }
        if (window[0] == 'I' && window[1] == 'D' && window[2] == '3') {
            size_t tag_size = ((window[6] & 0x7f) << 21) | ((window[7] & 0x7f) << 14) |
                              ((window[8] & 0x7f) << 7) | (window[9] & 0x7f);
            size_t skip = 10 + tag_size;
            while (window.size() < skip && !eof && !stop_requested_.load()) {
                if (!fill_window()) {
                    break;
                }
            }
            if (window.size() >= skip) {
                window.erase(window.begin(), window.begin() + (std::ptrdiff_t)skip);
                ESP_LOGI(TAG, "Skipped ID3 tag (%u bytes)", (unsigned)skip);
            }
        }
        skipped_id3 = true;
    };

    ESP_LOGI(TAG, "Streaming MP3 decode started (window=%uKB)", (unsigned)(kStreamWindowBytes / 1024));

    while (!stop_requested_.load()) {
        if (window.size() < kStreamLowWater && !eof) {
            fill_window();
        }
        if (window.empty()) {
            break;
        }
        skip_id3_if_needed();
        if (window.empty()) {
            continue;
        }

        esp_audio_dec_in_raw_t raw = {
            .buffer = window.data(),
            .len = (uint32_t)window.size(),
            .consumed = 0,
            .frame_recover = ESP_AUDIO_DEC_RECOVERY_NONE,
        };
        std::vector<int16_t> pcm_buf(2304);
        esp_audio_dec_out_frame_t out_frame = {
            .buffer = (uint8_t*)pcm_buf.data(),
            .len = (uint32_t)(pcm_buf.size() * sizeof(int16_t)),
            .decoded_size = 0,
        };
        esp_audio_dec_info_t dec_info = {};
        auto ret = esp_mp3_dec_decode(mp3_decoder, &raw, &out_frame, &dec_info);

        if (ret != ESP_AUDIO_ERR_OK || out_frame.decoded_size == 0 || raw.consumed == 0) {
            // Need more bytes for a full frame, or truly finished.
            if (!eof) {
                size_t before = window.size();
                fill_window();
                if (window.size() == before) {
                    // No new data — drop one byte to resync if stuck on garbage.
                    if (!window.empty()) {
                        window.erase(window.begin());
                    } else {
                        break;
                    }
                }
                continue;
            }
            break;
        }

        window.erase(window.begin(), window.begin() + (std::ptrdiff_t)raw.consumed);

        int samples = out_frame.decoded_size / sizeof(int16_t);
        pcm_buf.resize(samples);
        if (dec_info.channel == 2) {
            std::vector<int16_t> mono(samples / 2);
            for (size_t i = 0; i < mono.size(); i++) {
                mono[i] = (int16_t)(((int32_t)pcm_buf[i * 2] + pcm_buf[i * 2 + 1]) / 2);
            }
            pcm_buf = std::move(mono);
        }

        int src_rate = dec_info.sample_rate > 0 ? dec_info.sample_rate : 24000;
        if (src_rate != dest_rate) {
            if (resampler == nullptr || resampler_rate != src_rate) {
                if (resampler != nullptr) {
                    esp_ae_rate_cvt_close(resampler);
                    resampler = nullptr;
                }
                esp_ae_rate_cvt_cfg_t cvt_cfg = RATE_CVT_CFG(src_rate, dest_rate, ESP_AUDIO_MONO);
                esp_ae_rate_cvt_open(&cvt_cfg, &resampler);
                resampler_rate = src_rate;
            }
            if (resampler != nullptr) {
                uint32_t max_out = 0;
                esp_ae_rate_cvt_get_max_out_sample_num(resampler, pcm_buf.size(), &max_out);
                std::vector<int16_t> resampled(max_out);
                uint32_t actual = max_out;
                esp_ae_rate_cvt_process(resampler, (esp_ae_sample_t)pcm_buf.data(), pcm_buf.size(),
                                        (esp_ae_sample_t)resampled.data(), &actual);
                resampled.resize(actual);
                pcm_buf = std::move(resampled);
            }
        }

        audio_service.PlayPcm(std::move(pcm_buf));
        frames++;
    }

    if (resampler != nullptr) {
        esp_ae_rate_cvt_close(resampler);
    }
    esp_mp3_dec_close(mp3_decoder);
    http->Close();
    board.SetPowerSaveLevel(PowerSaveLevel::LOW_POWER);
    WaitForPlaybackIdle();
    ESP_LOGI(TAG, "HTTP MP3 stream done (frames=%d, bytes_read=%u)", frames, (unsigned)total_read);
    return frames > 0;
}

bool ScheduledAudio::RequestTtsAndPlay() {
    auto network = Board::GetInstance().GetNetwork();
    if (network == nullptr) {
        ESP_LOGE(TAG, "Network interface not available");
        return false;
    }

    auto http = network->CreateHttp(0);
    if (http == nullptr) {
        ESP_LOGE(TAG, "Failed to create HTTP client");
        return false;
    }

    cJSON* root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "text", text_.c_str());
    cJSON_AddStringToObject(root, "prompt", text_.c_str());
    cJSON_AddStringToObject(root, "device_id", SystemInfo::GetMacAddress().c_str());
    char* json_str = cJSON_PrintUnformatted(root);
    std::string body(json_str ? json_str : "");
    if (json_str) {
        cJSON_free(json_str);
    }
    cJSON_Delete(root);

    http->SetHeader("Content-Type", "application/json");
    http->SetHeader("Accept", "application/json, audio/mpeg, audio/ogg, */*");
    http->SetContent(std::move(body));
    http->SetTimeout(20000);
    http->SetKeepAlive(false);

    std::string request_url = PreferHttpUrl(api_url_);
    ESP_LOGI(TAG, "Requesting TTS from %s text=%s", request_url.c_str(), text_.c_str());
    if (!http->Open("POST", request_url)) {
        ESP_LOGE(TAG, "Failed to open TTS API %s", request_url.c_str());
        return false;
    }

    int status_code = http->GetStatusCode();
    if (status_code != 200) {
        ESP_LOGE(TAG, "TTS API status=%d", status_code);
        http->Close();
        return false;
    }

    std::string response = http->ReadAll();
    http->Close();
    if (response.empty()) {
        ESP_LOGE(TAG, "TTS API returned empty body");
        return false;
    }

    if (response[0] == '{' || response[0] == '[') {
        ESP_LOGI(TAG, "TTS JSON response: %s", response.c_str());
        std::string audio_url = ExtractAudioUrlFromJson(response);
        if (audio_url.empty()) {
            ESP_LOGE(TAG, "TTS JSON missing audioUrl/audio_url");
            return false;
        }
        return PlayAudioFromUrl(audio_url);
    }

    std::vector<uint8_t> data(response.begin(), response.end());
    return PlayDownloadedAudio(data);
}

void ScheduledAudio::FetchAndPlayStreamTask() {
    ESP_LOGI(TAG, "Starting scheduled announcement (Opus-first)");

    bool ok = false;
    std::string url_copy = pending_audio_url_;
    std::string opus_copy = pending_opus_url_;
    pending_audio_url_.clear();
    pending_opus_url_.clear();

    // Restore opus preference for PlayAudioFromUrl
    pending_opus_url_ = opus_copy;

    if (!url_copy.empty() || !opus_copy.empty()) {
        ESP_LOGI(TAG, "Playing schedule audio_url=%s opus_url=%s",
                 url_copy.c_str(), opus_copy.c_str());
        ok = PlayAudioFromUrl(url_copy.empty() ? opus_copy : url_copy);
    }

    if (!ok) {
        ESP_LOGI(TAG, "Requesting backend TTS for prompt: %s", text_.c_str());
        ok = RequestTtsAndPlay();
    }

    pending_opus_url_.clear();

    if (!ok) {
        ESP_LOGE(TAG, "Scheduled audio playback failed — will retry if still in catch-up window");
        Application::GetInstance().DismissAlert();
        last_trigger_id_.clear();
        pending_audio_url_ = url_copy;
        pending_opus_url_ = opus_copy;
        pending_due_ = !pending_trigger_key_.empty();
    } else {
        pending_due_ = false;
        pending_trigger_key_.clear();
        pending_deadline_ = 0;
        pending_audio_url_.clear();
        pending_opus_url_.clear();
    }

    ESP_LOGI(TAG, "Scheduled audio playback completed (ok=%d)", ok);
    is_playing_.store(false);
    stream_task_handle_ = nullptr;
}

void ScheduledAudio::SetConfig(bool enabled, int hour, int minute, const std::string& text, const std::string& api_url) {
    enabled_ = enabled;
    hour_ = (hour >= 0 && hour <= 23) ? hour : hour_;
    minute_ = (minute >= 0 && minute <= 59) ? minute : minute_;
    if (!text.empty()) {
        text_ = text;
    }
    if (!api_url.empty()) {
        api_url_ = PreferHttpUrl(api_url);
    }

    Settings settings("schedule", true);
    settings.SetBool("enabled", enabled_);
    settings.SetInt("hour", hour_);
    settings.SetInt("minute", minute_);
    settings.SetString("text", text_);
    settings.SetString("api_url", api_url_);

    ESP_LOGI(TAG, "Updated Schedule: enabled=%d, time=%02d:%02d, text=%s, url=%s",
             enabled_, hour_, minute_, text_.c_str(), api_url_.c_str());
}

std::string ScheduledAudio::GetConfigJson() const {
    cJSON* root = cJSON_CreateObject();
    cJSON_AddBoolToObject(root, "enabled", enabled_);
    cJSON_AddNumberToObject(root, "hour", hour_);
    cJSON_AddNumberToObject(root, "minute", minute_);
    cJSON_AddStringToObject(root, "text", text_.c_str());
    cJSON_AddStringToObject(root, "api_url", api_url_.c_str());
    cJSON_AddBoolToObject(root, "is_playing", is_playing_.load());

    char* json_str = cJSON_PrintUnformatted(root);
    std::string result(json_str ? json_str : "{}");
    if (json_str) {
        cJSON_free(json_str);
    }
    cJSON_Delete(root);
    return result;
}
