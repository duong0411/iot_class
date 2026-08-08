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
  }

  async connect() {
    const mqttUrl = process.env.MQTT_URL || 'wss://mqtt.aiotlearninghub.com:443/mqtt';
    console.log(`🔌 Đang kết nối tới MQTT Broker (Classroom Backend): ${mqttUrl}`);

    this.client = mqtt.connect(mqttUrl, {
      clientId: `classroom_backend_${Math.random().toString(16).slice(2, 8)}`,
      keepalive: 60,
      reconnectPeriod: 2000,
      clean: true,
      protocol: 'wss'
    });

    this.client.on('connect', () => {
      console.log('✅ Backend Lớp Học Thông Minh đã kết nối MQTT thành công!');
      this.subscribeClassroomTopics();
    });

    this.client.on('error', (err) => {
      console.error('❌ Lỗi kết nối MQTT:', err.message);
    });

    this.client.on('message', this.handleMessage.bind(this));

    // Cầu nối phụ tới Xiaozhi Cloud Broker (mqtt.xiaozhi.me)
    try {
      console.log('🌉 Đang khởi tạo Cầu nối MQTT sang Xiaozhi Cloud...');
      this.xiaozhiClient = mqtt.connect('mqtts://mqtt.xiaozhi.me:8883', {
        clientId: `backend_xiaozhi_bridge_${Math.random().toString(16).slice(2, 8)}`,
        keepalive: 60,
        reconnectPeriod: 5000,
        rejectUnauthorized: false
      });

      this.xiaozhiClient.on('connect', () => {
        console.log('✅ Cầu nối MQTT sang Xiaozhi Cloud (mqtt.xiaozhi.me:8883) đã kết nối thành công!');
      });

      this.xiaozhiClient.on('error', (err) => {
        // Suppress warning
      });
    } catch (_) {}
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

  async handleMessage(topic, message) {
    const payloadBuffer = Buffer.isBuffer(message) ? message : Buffer.from(message);
    let payloadStr = payloadBuffer.toString('utf8').trim();

    if (topic === 'cmnd/classroom_schedule/set') {
      console.log(`📥 [Schedule Set Received] Topic '${topic}' (${payloadBuffer.length} bytes): ${payloadStr}`);
      try {
        const jsonMatch = payloadStr.match(/\{[\s\S]*\}/);
        if (!jsonMatch) {
          console.error('❌ [Schedule Set Error] No JSON braces found in payload.');
          return;
        }
        // Strip invalid unescaped JSON control characters (0x00-0x1F) from string literal
        const sanitizedJsonStr = jsonMatch[0].replace(/[\x00-\x1F]/g, ' ');
        const json = JSON.parse(sanitizedJsonStr);

        if (json.schedules && Array.isArray(json.schedules)) {
          const ttsService = require('./tts.service');
          const updatedSchedules = [];

          for (const s of json.schedules) {
            let promptText = (s.prompt || '').trim();
            const schId = s.id || `sched_${s.hour}_${s.minute}`;
            const audioFileName = await ttsService.generateVietnameseTts(schId, promptText);

            const baseUrl = process.env.SERVER_BASE_URL || 'http://mqtt.aiotlearninghub.com:3000';
            const audioUrl = audioFileName ? `${baseUrl}/audio/${audioFileName}` : null;

            console.log(`🎙️ [Backend TTS] Schedule '${schId}' (${s.hour}:${s.minute}) -> Audio URL: ${audioUrl}`);

            updatedSchedules.push({
              ...s,
              prompt: promptText,
              audio_url: audioUrl,
              lastTriggeredDay: -1
            });
          }

          this.schedules = updatedSchedules;
          console.log(`⏰ [Backend Schedule Update] Cập nhật ${this.schedules.length} mốc lịch tự động với Offline Audio URL!`);

          const enrichedPayload = JSON.stringify({ schedules: this.schedules });

          // Publish back to mqtt.aiotlearninghub.com
          if (this.client && this.client.connected) {
            this.client.publish('cmnd/classroom_schedule/set', enrichedPayload);
            console.log(`📡 [Backend TX] Đã publish enriched schedule với audio_url lên mqtt.aiotlearninghub.com!`);
          }

          // Forward to Xiaozhi Cloud broker
          if (this.xiaozhiClient && this.xiaozhiClient.connected) {
            this.xiaozhiClient.publish('cmnd/classroom_schedule/set', enrichedPayload);
            console.log(`🌉 [Backend Bridge] Đã forward cmnd/classroom_schedule/set với audio_url sang Xiaozhi ESP32 qua mqtt.xiaozhi.me!`);
          }
          return;
        }
      } catch (err) {
        console.error('❌ [Schedule Set Error] Failed to parse and process schedule JSON:', err.message);
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

    // Forward tin nhắn khác từ Mobile App sang Xiaozhi ESP32
    if (this.xiaozhiClient && this.xiaozhiClient.connected) {
      if (topic === 'cmnd/classroom_schedule/delete' || topic === 'cmnd/xiaozhi_tts/say') {
        this.xiaozhiClient.publish(topic, payloadStr);
        console.log(`🌉 [Backend Bridge] Đã forward ${topic} sang Xiaozhi ESP32 qua mqtt.xiaozhi.me!`);
      }
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
