const mqtt = require('mqtt');

class MqttService {
  constructor() {
    this.client = null;
    this.xiaozhiClient = null;
    this.subscribedTopics = new Set();
    this.envCache = {
      temp: 0.0,
      humi: 0.0,
      light: "Đang đọc...",
      led: "OFF",
      fan: "OFF",
      door: "Đóng (0°)",
      mode: "AUTO (Tự động theo cảm biến)"
    };
    this.schedules = [
      { id: 'sched_morning', hour: 7, minute: 45, prompt: 'Đã đến giờ truy bài, các bạn học sinh chuẩn bị vào lớp!', enabled: true, action: 'NONE', lastTriggeredDay: -1 },
      { id: 'sched_evening', hour: 17, minute: 0, prompt: 'Đã đến giờ tan học, các bạn học sinh có thể ra về!', enabled: true, action: 'NONE', lastTriggeredDay: -1 }
    ];
    this.isTimerRunning = false;
  }

  async connect() {
    // Kết nối nội bộ tới Mosquitto local qua TCP (nhanh, không overhead TLS)
    // ESP32/Mobile App kết nối qua ws://localhost:443 (plain WS, qua Cloudflare Tunnel thành WSS)
    const mqttUrl = process.env.MQTT_URL || 'mqtt://localhost:1883';
    console.log(`🔌 Đang kết nối tới MQTT Broker local: ${mqttUrl}`);

    this.client = mqtt.connect(mqttUrl, {
      clientId: `classroom_backend_${Math.random().toString(16).slice(2, 8)}`,
      keepalive: 60,
      reconnectPeriod: 2000,
      clean: true,
      connectTimeout: 10000
    });

    this.client.on('connect', () => {
      console.log('✅ Backend đã kết nối Mosquitto local (localhost:1883) thành công!');
      console.log(`📡 ESP32 kết nối qua: ws://${process.env.MQTT_PUBLIC_HOST || 'mqtt.duynguyen.io.vn'}:${process.env.MQTT_PUBLIC_PORT || 443}/mqtt`);
      this.subscribeClassroomTopics();
      this.startScheduleTimer();
    });

    this.client.on('error', (err) => {
      console.error('❌ Lỗi kết nối MQTT:', err.message);
    });

    this.client.on('message', this.handleMessage.bind(this));
  }

  subscribeClassroomTopics() {
    if (!this.client) return;

    const topicsToSubscribe = [
      'tele/classroom_temp/status',
      'tele/classroom_humi/status',
      'tele/classroom_light/status',
      'tele/classroom_led/status',
      'tele/classroom_fan/status',
      'tele/classroom_door/status',
      'tele/classroom_rfid/status',
      'tele/classroom_mode/status',
      'cmnd/classroom_schedule/set',
      'cmnd/classroom_schedule/delete',
      'cmnd/xiaozhi_tts/say',
      'tele/+/status'
    ];

    topicsToSubscribe.forEach(t => {
      if (!this.subscribedTopics.has(t)) {
        this.client.subscribe(t);
        this.subscribedTopics.add(t);
      }
    });
    console.log('📡 Backend đã subscribe đầy đủ các Topic Telemetry & Schedule của Lớp Học Thông Minh!');
  }

  publish(topic, message) {
    if (this.client && this.client.connected) {
      this.client.publish(topic, String(message));
      console.log(`📤 [Backend MQTT TX] ${topic} -> ${message}`);
    }
  }

  startScheduleTimer() {
    if (this.isTimerRunning) return;
    this.isTimerRunning = true;
    console.log('⏱️ [Backend Automation] Timer kiểm tra lịch tự động đã khởi chạy!');

    setInterval(() => {
      if (!this.schedules || this.schedules.length === 0) return;

      const now = new Date();
      // Múi giờ Việt Nam (UTC+7)
      const vnTimeStr = now.toLocaleString("en-US", { timeZone: "Asia/Ho_Chi_Minh" });
      const vnDate = new Date(vnTimeStr);
      const currentHour = vnDate.getHours();
      const currentMinute = vnDate.getMinutes();
      const currentSecond = vnDate.getSeconds();
      const currentDay = vnDate.getDate();

      if (currentSecond === 0) {
        for (const s of this.schedules) {
          if (s.enabled && s.hour === currentHour && s.minute === currentMinute && s.lastTriggeredDay !== currentDay) {
            s.lastTriggeredDay = currentDay;
            console.log(`⏰ [AUTOMATION TRIGGER] Đã đến giờ ${s.hour}:${s.minute}! Phát lời dẫn: "${s.prompt}"`);

            // 1. Phát trực tiếp qua Topic MQTT cmnd/xiaozhi_tts/say tới Loa Xiaozhi ESP32
            const ttsPayload = JSON.stringify({
              prompt: s.prompt,
              text: s.prompt,
              audio_url: s.audioUrl || `${process.env.SERVER_BASE_URL || 'https://duynguyen.io.vn'}/audio/${s.id}.mp3`,
              say: true
            });

            this.publish('cmnd/xiaozhi_tts/say', ttsPayload);

            try {
              const XiaoZhiService = require('./xiaozhi.service');
              XiaoZhiService.sendTtsSay(s.prompt);
            } catch (err) {
              console.error('❌ Lỗi gửi voice qua Xiaozhi Service:', err.message);
            }

            // 2. Tự động bật/tắt thiết bị nếu là mốc giờ học / tan học
            if (s.hour === 7 && s.minute === 45) {
              try {
                const XiaoZhiService = require('./xiaozhi.service');
                XiaoZhiService.runMcpToolLocal('control_all_devices', { state: 'ON' });
              } catch (_) {}
            } else if (s.hour === 17 && s.minute === 0) {
              try {
                const XiaoZhiService = require('./xiaozhi.service');
                XiaoZhiService.runMcpToolLocal('control_all_devices', { state: 'OFF' });
              } catch (_) {}
            }
          }
        }
      }
    }, 1000);
  }

  async handleMessage(topic, message) {
    const payloadBuffer = Buffer.isBuffer(message) ? message : Buffer.from(message);
    let payloadStr = payloadBuffer.toString('utf8').trim();

    if (topic === 'cmnd/classroom_schedule/set') {
      console.log(`📥 [Schedule Set Received] Topic '${topic}' (${payloadBuffer.length} bytes): ${payloadStr}`);
      try {
        const jsonMatch = payloadStr.match(/\{[\s\S]*\}/);
        if (!jsonMatch) return;

        const sanitizedJsonStr = jsonMatch[0].replace(/[\x00-\x1F]/g, ' ');
        const json = JSON.parse(sanitizedJsonStr);

        if (json.schedules && Array.isArray(json.schedules)) {
          const ttsService = require('./tts.service');
          const youtubeService = require('./youtube.service');
          const serverBaseUrl = process.env.SERVER_BASE_URL || 'https://duynguyen.io.vn';

          this.schedules = await Promise.all(json.schedules.map(async s => {
            const promptStr = (s.prompt || '').trim();
            const schedId = s.id || `sched_${s.hour ?? 0}h${s.minute ?? 0}`;
            const filename = `voice_${s.hour ?? 0}h${s.minute ?? 0}.mp3`;
            const audioSource = (s.audioSource || s.audio_source || 'tts').toString().toLowerCase();
            let audioUrl = s.audioUrl || s.audio_url || '';
            const youtubeUrl = s.youtubeUrl || s.youtube_url || '';

            try {
              if (audioSource === 'youtube' && youtubeUrl && !audioUrl) {
                const saved = await youtubeService.downloadAsMp3(youtubeUrl, filename.replace('.mp3', '_yt.mp3'));
                audioUrl = `${serverBaseUrl}/audio/${saved}`;
              } else if (audioSource === 'mp3' && audioUrl) {
                // keep
              } else if (promptStr) {
                await ttsService.generateVietnameseTts(filename, promptStr);
                audioUrl = `${serverBaseUrl}/audio/${filename}`;
              } else if (!audioUrl) {
                audioUrl = `${serverBaseUrl}/audio/${filename}`;
              }
            } catch (e) {
              console.error(`❌ [Schedule MQTT] audio prepare failed:`, e.message);
              if (promptStr) {
                await ttsService.generateVietnameseTts(filename, promptStr);
                audioUrl = `${serverBaseUrl}/audio/${filename}`;
              }
            }

            let opusUrl = '';
            try {
              const opusService = require('./opus.service');
              const mp3Name = opusService.filenameFromAudioUrl(audioUrl) || filename;
              if (mp3Name && /\.mp3$/i.test(mp3Name)) {
                const oggName = await opusService.ensureOggFromMp3(mp3Name);
                opusUrl = `${serverBaseUrl}/audio/${oggName}`;
              }
            } catch (e) {
              console.warn(`⚠️ [Schedule MQTT] Opus convert:`, e.message);
            }

            return {
              ...s,
              id: schedId,
              prompt: promptStr,
              audioSource,
              youtubeUrl: youtubeUrl || undefined,
              audioUrl,
              audio_url: audioUrl,
              opusUrl: opusUrl || undefined,
              opus_url: opusUrl || undefined,
              lastTriggeredDay: -1
            };
          }));

          console.log(`⏰ [Backend Schedule Update] Cập nhật ${this.schedules.length} mốc lịch tự động từ Mobile App!`);

          const broadcastPayload = JSON.stringify({ schedules: this.schedules });
          if (this.client && this.client.connected) {
            this.client.publish('stat/classroom_schedule/list', broadcastPayload);
            console.log(`📡 [Backend TX] Đã broadcast danh sách lịch mới tới stat/classroom_schedule/list!`);
          }

          return;
        }
      } catch (err) {
        console.error('❌ [Schedule Set Error] Failed to parse schedule JSON:', err.message);
        return;
      }
    }

    let valStr = payloadStr;
    try {
      const jsonMatch = payloadStr.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        const json = JSON.parse(jsonMatch[0]);
        if (json.value !== undefined) {
          valStr = String(json.value);
        }
      }
    } catch (e) {
      valStr = payloadStr;
    }

    // --- Cập nhật Cache Telemetry Lớp Học cho XiaoZhi MCP ---
    if (topic.includes('classroom_temp')) {
      this.envCache.temp = parseFloat(valStr) || this.envCache.temp;
    } else if (topic.includes('classroom_humi')) {
      this.envCache.humi = parseFloat(valStr) || this.envCache.humi;
    } else if (topic.includes('classroom_light')) {
      this.envCache.light = (valStr === 'Tot' || valStr === 'SÁNG')
        ? 'Ánh sáng Tốt (Đủ sáng ☀️)'
        : 'Ánh sáng Yếu (Trời tối/Che tay 🌙)';
    } else if (topic.includes('classroom_led')) {
      this.envCache.led = (valStr.toUpperCase() === 'ON') ? 'ON' : 'OFF';
    } else if (topic.includes('classroom_fan')) {
      this.envCache.fan = (valStr.toUpperCase() === 'ON') ? 'ON' : 'OFF';
    } else if (topic.includes('classroom_door')) {
      this.envCache.door = (valStr === '90' || valStr.toUpperCase() === 'ON' || valStr.toUpperCase() === 'OPEN')
        ? 'Mở (90°)'
        : 'Đóng (0°)';
    } else if (topic.includes('classroom_mode')) {
      this.envCache.mode = (valStr.toUpperCase() === 'MANUAL')
        ? 'MANUAL (Thủ công qua App/Giọng nói)'
        : 'AUTO (Tự động theo cảm biến)';
    }

    console.log(`📥 [MQTT Telemetry Cache Update] ${topic} -> ${valStr}`);
  }
}

module.exports = new MqttService();
