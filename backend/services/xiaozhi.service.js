const WebSocket = require('ws');
const mqttService = require('./mqtt.service');

// XIAOZHI MCP ENDPOINT (WebSockets Client MCP Endpoint)
const XIAOZHI_URL = process.env.XIAOZHI_MCP_URL || "wss://api.xiaozhi.me/mcp/?token=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjg4MzEwMiwiYWdlbnRJZCI6MjE5MDk4MSwiZW5kcG9pbnRJZCI6ImFnZW50XzIxOTA5ODEiLCJwdXJwb3NlIjoibWNwLWVuZHBvaW50IiwiaWF0IjoxNzg1Njg2MDY4LCJleHAiOjE4MTcyNDM2Njh9.mA4TgMiFd3et8bjKDcVSquDsw-FXL42XYgXVKmNygAo_F9TWG_QYgA1P32i5QfOWx3rdWhyGWi4boK7U4eLvpw";

class XiaoZhiService {
  constructor() {
    this.ws = null;
    this.reconnectTimeout = null;
    this.pingInterval = null;
  }

  connect() {
    console.log(`🤖 Đang kết nối tới XiaoZhi MCP Server (Smart Classroom)...`);
    this.ws = new WebSocket(XIAOZHI_URL);

    this.ws.on('open', () => {
      console.log('✅ XiaoZhi MCP cho Lớp Học Thông Minh đã kết nối thành công!');

      // Giữ kết nối Ping/Pong định kỳ (25 giây)
      if (this.pingInterval) clearInterval(this.pingInterval);
      this.pingInterval = setInterval(() => {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
          this.ws.ping();
        }
      }, 25000);

      // Khởi chạy Bộ Lịch Tự Động (Truy bài 7h45 & Tan học)
      this.startClassroomScheduler();
    });

    this.ws.on('message', (data) => {
      const messageStr = data.toString();
      this.handleJsonRpc(messageStr);
    });

    this.ws.on('close', () => {
      if (this.pingInterval) clearInterval(this.pingInterval);
      console.log('❌ XiaoZhi MCP ngắt kết nối. Đang thử lại sau 5s...');
      this.scheduleReconnect();
    });

    this.ws.on('error', (err) => {
      console.error('❌ Lỗi XiaoZhi WS:', err.message);
    });
  }

  scheduleReconnect() {
    if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout);
    this.reconnectTimeout = setTimeout(() => this.connect(), 5000);
  }

  // BỘ LỊCH HÀNG NGÀY: 7:45 mở thiết bị | 17:00 tắt hết (TTS do ESP phát local)
  startClassroomScheduler() {
    if (this.schedulerInterval) return;

    let lastTriggeredMinute = -1;
    console.log('⏰ Bộ lịch lớp học: 7:45 BẬT + TTS(ESP) | 17:00 TẮT + TTS(ESP)');

    this.schedulerInterval = setInterval(() => {
      const now = new Date();
      const hours = now.getHours();
      const minutes = now.getMinutes();
      const currentMinuteId = hours * 60 + minutes;

      if (currentMinuteId === lastTriggeredMinute) return;

      // 7:45 — truy bài: bật thiết bị (ESP tự phát TTS local cùng lúc)
      if (hours === 7 && minutes === 45) {
        lastTriggeredMinute = currentMinuteId;
        console.log('⏰ [7:45] Truy bài → MCP ON devices');
        this.runMcpToolLocal('control_all_devices', { state: 'ON' });
        this.runMcpToolLocal('control_door', { mode: 'open' });
        this.runMcpToolLocal('set_classroom_mode', { mode: 'MANUAL' });
      }

      // 17:00 — ra về: tắt hết thiết bị (ESP tự phát TTS local cùng lúc)
      if (hours === 17 && minutes === 0) {
        lastTriggeredMinute = currentMinuteId;
        console.log('⏰ [17:00] Tan học → MCP OFF devices');
        this.runMcpToolLocal('control_all_devices', { state: 'OFF' });
        this.runMcpToolLocal('control_door', { mode: 'close' });
        this.runMcpToolLocal('control_light', { state: 'OFF' });
        this.runMcpToolLocal('control_fan', { state: 'OFF' });
      }
    }, 10000);
  }

  /**
   * Gọi cùng logic tools/call MCP nhưng từ lịch backend (không cần LLM).
   * Tools đăng ký: control_light, control_fan, control_door, set_classroom_mode,
   * read_environment, control_all_devices.
   */
  runMcpToolLocal(toolName, args = {}) {
    console.log(`🛠️ [Scheduler MCP] ${toolName}`, args);

    let responseText = '';
    let mqttTopic = '';
    let mqttValue = '';

    if (toolName === 'control_light') {
      mqttValue = args.state === 'ON' ? 'ON' : 'OFF';
      mqttTopic = 'cmnd/classroom_led/POWER';
      responseText = `Đã ${mqttValue === 'ON' ? 'bật' : 'tắt'} đèn.`;
    } else if (toolName === 'control_fan') {
      mqttValue = args.state === 'ON' ? 'ON' : 'OFF';
      mqttTopic = 'cmnd/classroom_fan/POWER';
      responseText = `Đã ${mqttValue === 'ON' ? 'bật' : 'tắt'} quạt.`;
    } else if (toolName === 'control_door') {
      if (args.mode === 'open') mqttValue = '90';
      else if (args.mode === 'close') mqttValue = '0';
      else if (args.mode === 'angle') mqttValue = args.angle != null ? String(args.angle) : '0';
      else mqttValue = '0';
      mqttTopic = 'cmnd/classroom_door/POWER';
      responseText = `Cửa góc ${mqttValue}.`;
    } else if (toolName === 'set_classroom_mode') {
      mqttValue = args.mode === 'MANUAL' ? 'MANUAL' : 'AUTO';
      mqttTopic = 'cmnd/classroom_mode/POWER';
      responseText = `Mode ${mqttValue}.`;
    } else if (toolName === 'read_environment') {
      const cache = mqttService.envCache;
      responseText =
        `Báo cáo môi trường lớp học:\n` +
        `- Nhiệt độ: ${cache.temp}°C\n` +
        `- Độ ẩm: ${cache.humi}%\n` +
        `- Ánh sáng: ${cache.light}\n` +
        `- Đèn: ${cache.led}\n` +
        `- Quạt: ${cache.fan}\n` +
        `- Cửa: ${cache.door}\n` +
        `- Chế độ: ${cache.mode}`;
      console.log(`[Scheduler MCP] read_environment`);
      return responseText;
    } else if (toolName === 'control_all_devices') {
      mqttValue = args.state === 'ON' ? 'ON' : 'OFF';
      if (mqttService.client) {
        mqttService.client.publish('cmnd/classroom_led/POWER', mqttValue);
        mqttService.client.publish('cmnd/classroom_fan/POWER', mqttValue);
        console.log(`[Scheduler -> MQTT] ALL devices: ${mqttValue}`);
      } else {
        console.warn('[Scheduler MCP] MQTT client chưa sẵn sàng');
      }
      responseText = `Đã ${mqttValue === 'ON' ? 'bật' : 'tắt'} toàn bộ đèn và quạt.`;
      return responseText;
    } else {
      console.warn(`[Scheduler MCP] Unknown tool: ${toolName}`);
      return 'Tool không tồn tại.';
    }

    if (mqttTopic && mqttService.client) {
      mqttService.client.publish(mqttTopic, mqttValue);
      console.log(`[Scheduler -> MQTT] ${mqttTopic} = ${mqttValue}`);
    } else if (mqttTopic && !mqttService.client) {
      console.warn('[Scheduler MCP] MQTT client chưa sẵn sàng');
    }

    return responseText;
  }

  broadcastVoiceAnnouncement(text) {
    console.log(`📢 [XIAOZHI VOICE ANNOUNCEMENT]: "${text}"`);
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.send({
        jsonrpc: "2.0",
        method: "notifications/message",
        params: {
          type: "text",
          content: text
        }
      });
    }
  }

  send(msgObj) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msgObj));
    }
  }

  handleJsonRpc(messageStr) {
    let doc;
    try {
      doc = JSON.parse(messageStr);
    } catch (e) {
      return;
    }

    if (doc.method === 'ping') {
      this.send({ jsonrpc: "2.0", id: doc.id, result: {} });
      console.log(`[XiaoZhi MCP] Ping -> Pong`);
    }
    else if (doc.method === 'initialize') {
      this.send({
        jsonrpc: "2.0",
        id: doc.id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { experimental: {}, prompts: { listChanged: false }, resources: { subscribe: false, listChanged: false }, tools: { listChanged: false } },
          serverInfo: { name: "Classroom-SmartHome-MCP", version: "2.0.0" }
        }
      });
      this.send({ jsonrpc: "2.0", method: "notifications/initialized" });
      console.log(`[XiaoZhi MCP] Đã phản hồi Initialize cho Lớp Học Thông Minh!`);
    }
    else if (doc.method === 'tools/list') {
      this.send({
        jsonrpc: "2.0",
        id: doc.id,
        result: {
          tools: [
            {
              name: "control_light",
              description: "Điều khiển BẬT (ON) hoặc TẮT (OFF) hệ thống đèn chiếu sáng của lớp học thông minh.",
              inputSchema: {
                type: "object",
                properties: {
                  state: { type: "string", enum: ["ON", "OFF"], description: "ON để bật đèn, OFF để tắt đèn lớp học" }
                },
                required: ["state"]
              }
            },
            {
              name: "control_fan",
              description: "Điều khiển BẬT (ON) hoặc TẮT (OFF) hệ thống quạt mát / quạt thông gió của lớp học thông minh.",
              inputSchema: {
                type: "object",
                properties: {
                  state: { type: "string", enum: ["ON", "OFF"], description: "ON để bật quạt, OFF để tắt quạt lớp học" }
                },
                required: ["state"]
              }
            },
            {
              name: "control_door",
              description: "Điều khiển MỞ (open/90) hoặc ĐÓNG (close/0) cửa lớp học / cửa sổ thông minh bằng góc Servo.",
              inputSchema: {
                type: "object",
                properties: {
                  mode: { type: "string", enum: ["open", "close", "angle"], description: "open: mở cửa 90 độ, close: đóng cửa 0 độ, angle: mở theo góc cụ thể" },
                  angle: { type: "integer", description: "Góc mở cửa từ 0 đến 90 độ" }
                },
                required: ["mode"]
              }
            },
            {
              name: "set_classroom_mode",
              description: "Chuyển đổi chế độ hoạt động của lớp học thông minh giữa Tự động (AUTO - cảm biến tự bật tắt quạt đèn) và Thủ công (MANUAL - cho phép tự do điều khiển qua app/giọng nói).",
              inputSchema: {
                type: "object",
                properties: {
                  mode: { type: "string", enum: ["AUTO", "MANUAL"], description: "AUTO: Tự động cảm biến | MANUAL: Điều khiển thủ công" }
                },
                required: ["mode"]
              }
            },
            {
              name: "read_environment",
              description: "Báo cáo đầy đủ thông số môi trường của lớp học thông minh bao gồm: Nhiệt độ, Độ ẩm, Cảm biến ánh sáng (Tốt/Yếu), trạng thái Quạt, Đèn, Cửa lớp và Chế độ hoạt động hiện tại.",
              inputSchema: { type: "object", properties: {} }
            },
            {
              name: "control_all_devices",
              description: "Bật (ON) hoặc Tắt (OFF) toàn bộ các thiết bị (bao gồm tất cả đèn và quạt) trong lớp học thông minh.",
              inputSchema: {
                type: "object",
                properties: {
                  state: { type: "string", enum: ["ON", "OFF"], description: "ON để bật tất cả, OFF để tắt toàn bộ thiết bị lớp học" }
                },
                required: ["state"]
              }
            }
          ]
        }
      });
      console.log(`[XiaoZhi MCP] Đã gửi danh sách Tools cho Lớp Học Thông Minh`);
    }
    else if (doc.method === 'tools/call') {
      const toolName = doc.params.name;
      const args = doc.params.arguments || {};
      console.log(`🗣️ [XiaoZhi Voice MCP Call] Tool: ${toolName}`, args);

      const responseText = this.runMcpToolLocal(toolName, args) || 'Tool không tồn tại.';

      this.send({
        jsonrpc: "2.0",
        id: doc.id,
        result: {
          content: [{ type: "text", text: responseText }],
          isError: false
        }
      });
    }
  }
}

module.exports = new XiaoZhiService();
