#ifndef SCHEDULED_AUDIO_H
#define SCHEDULED_AUDIO_H

#include <string>
#include <vector>
#include <atomic>
#include <mutex>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <cJSON.h>

class ScheduledAudio {
public:
    static ScheduledAudio& GetInstance() {
        static ScheduledAudio instance;
        return instance;
    }

    ScheduledAudio(const ScheduledAudio&) = delete;
    ScheduledAudio& operator=(const ScheduledAudio&) = delete;

    void Initialize();
    void CheckSchedule();
    void RefreshRemoteSchedule() { FetchRemoteScheduleAsync(); }
    bool TriggerAudioStream();
    void StopAudioStream();

    bool IsEnabled() const { return enabled_; }
    int GetHour() const { return hour_; }
    int GetMinute() const { return minute_; }
    const std::string& GetText() const { return text_; }
    const std::string& GetApiUrl() const { return api_url_; }
    bool IsPlaying() const { return is_playing_.load(); }

    void SetConfig(bool enabled, int hour, int minute, const std::string& text, const std::string& api_url = "");
    std::string GetConfigJson() const;

private:
    struct RemoteSchedule {
        std::string id;
        int hour = -1;
        int minute = -1;
        std::string prompt;
        std::string audio_url;
        std::string opus_url;
        bool enabled = true;
    };

    ScheduledAudio();
    ~ScheduledAudio();

    void FetchRemoteScheduleAsync();
    void FetchRemoteScheduleTask();
    void FetchAndPlayStreamTask();
    bool PlayAudioFromUrl(const std::string& url);
    bool RequestTtsAndPlay();
    bool DownloadToBuffer(const std::string& url, std::vector<uint8_t>& out);
    bool PlayDownloadedAudio(const std::vector<uint8_t>& data);
    bool PlayMp3DirectToSpeaker(const std::vector<uint8_t>& data, size_t offset);
    // HTTP chunked download + progressive MP3 decode (legacy fallback).
    bool StreamMp3FromUrl(const std::string& url);
    // Progressive Ogg Opus → PushPacketToDecodeQueue (same path as Xiaozhi cloud TTS).
    bool StreamOpusOggFromUrl(const std::string& url);
    // Ask AloT /ws to push raw Opus frames (tts start/stop + binary).
    bool StreamOpusViaWebSocket(const std::string& mp3_or_audio_url);
    void WaitForPlaybackIdle();
    void ArmPending(const std::string& trigger_key, const std::string& prompt, const std::string& audio_url,
                    const std::string& opus_url = "");
    bool TryStartPending(const char* reason);
    static std::string PreferHttpUrl(const std::string& url);
    static std::string DeriveOggUrl(const std::string& mp3_url);
    static std::string DeriveWsUrl(const std::string& http_base_url);
    static std::string ExtractAudioUrlFromJson(const std::string& json);

    bool enabled_ = true;
    int hour_ = 7;
    int minute_ = 0;
    std::string text_ = "Chào buổi sáng! Đây là lời nhắc công việc hôm nay.";
    std::string api_url_ = "http://duynguyen.io.vn/api/tts/say";
    std::string schedule_url_ = "http://duynguyen.io.vn/api/schedule";
    std::string pending_audio_url_;
    std::string pending_opus_url_;

    int last_trigger_day_ = -1;
    std::string last_trigger_id_;
    // When the clock matches but the device is busy / download fails, keep the
    // announcement armed and retry until idle (catch-up window below).
    bool pending_due_ = false;
    std::string pending_trigger_key_;
    time_t pending_deadline_ = 0;
    std::atomic<bool> is_playing_{false};
    std::atomic<bool> stop_requested_{false};
    std::atomic<bool> schedule_fetch_in_progress_{false};
    TaskHandle_t stream_task_handle_ = nullptr;

    std::mutex remote_mutex_;
    std::vector<RemoteSchedule> remote_schedules_;
};

#endif // SCHEDULED_AUDIO_H
