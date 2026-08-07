const mqtt = require('mqtt');

class MqttService {
  constructor() {
    this.client = null;
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

  handleMessage(topic, message) {
    const payloadStr = message.toString().trim();
    let valStr = payloadStr;

    try {
      const json = JSON.parse(payloadStr);
      if (json.value !== undefined) {
        valStr = String(json.value);
      }

      if (topic === 'cmnd/classroom_schedule/set' && json.schedules && Array.isArray(json.schedules)) {
        this.schedules = json.schedules.map(s => ({
          ...s,
          lastTriggeredDay: -1
        }));
        console.log(`⏰ [Backend Schedule Update] Cập nhật ${this.schedules.length} mốc lịch tự động từ App!`);
        return;
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
