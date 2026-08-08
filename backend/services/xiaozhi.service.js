const WebSocket = require('ws');
const mqttService = require('./mqtt.service');

// XIAOZHI MCP ENDPOINT (WebSockets Client MCP Endpoint)
const XIAOZHI_URL = process.env.XIAOZHI_MCP_URL || "wss://api.xiaozhi.me/mcp/?token=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjg4MzEwMiwiYWdlbnRJZCI6MjE5MDk4MSwiZW5kcG9pbnRJZCI6ImFnZW50XzIxOTA5ODEiLCJwdXJwb3NlIjoibWNwLWVuZHBvaW50IiwiaWF0IjoxNzg1Njg2MDY4LCJleHAiOjE4MTcyNDM2Njh9.mA4TgMiFd3et8bjKDcVSquDsw-FXL42XYgXVKmNygAo_F9TWG_QYgA1P32i5QfOWx3rdWhyGWi4boK7U4eLvpw";

class XiaoZhiService {
  constructor() {
    this.ws = null;
    this.reconnectTimeout = null;
    this.pingInterval = null;
    this.schedulerInterval = null;
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

      // Khởi chạy Bộ Lịch Tự Động từ Mobile App qua MQTT
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

  // BỘ LỊCH TỰ ĐỘNG ĐỘNG (Nhận dữ liệu từ Mobile App qua MQTT aiotlearninghub)
  startClassroomScheduler() {
    if (this.schedulerInterval) return;

    console.log('⏰ Bộ lịch tự động Lớp học từ Mobile App (aiotlearninghub MQTT) đã kích hoạt!');

    this.schedulerInterval = setInterval(() => {
      const now = new Date();
      const hours = now.getHours();
      const minutes = now.getMinutes();
      const currentDay = now.getDate();

      const schedules = mqttService.schedules || [];
      schedules.forEach(sch => {
        if (sch.enabled && sch.hour === hours && sch.minute === minutes) {
          if (sch.lastTriggeredDay !== currentDay) {
            sch.lastTriggeredDay = currentDay;
            console.log(`⏰ [Lịch Nhắc Nhở %02d:%02d] 🔔 Lời dẫn: "${sch.prompt}"`);
            this.sendTtsSay(sch.prompt);
          }
        }
      });
    }, 10000);
  }

  sendTtsSay(promptText) {
    if (!promptText) return;
    console.log(`📢 [Xiaozhi Voice TTS] Đang phát câu thoại qua Xiaozhi: "${promptText}"`);
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try {
        this.ws.send(JSON.stringify({
          jsonrpc: "2.0",
          method: "notifications/message",
          params: { message: promptText }
        }));
      } catch (e) {
        console.error('❌ Lỗi khi gửi TTS message:', e.message);
      }
    }
  }

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
      responseText = `Thông số môi trường: Nhiệt độ ${cache.temp}°C, Độ ẩm ${cache.humi}%, ${cache.light}, Đèn ${cache.led}, Quạt ${cache.fan}, Cửa ${cache.door}, Chế độ ${cache.mode}.`;
    } else if (toolName === 'control_all_devices') {
      const state = args.state === 'ON' ? 'ON' : 'OFF';
      mqttService.publish('cmnd/classroom_led/POWER', state);
      mqttService.publish('cmnd/classroom_fan/POWER', state);
      responseText = `Đã ${state === 'ON' ? 'bật' : 'tắt'} toàn bộ thiết bị.`;
      return responseText;
    }

    if (mqttTopic && mqttValue) {
      mqttService.publish(mqttTopic, mqttValue);
    }

    return responseText;
  }

  send(dataObj) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(dataObj));
    }
  }

  handleJsonRpc(jsonString) {
    let doc;
    try {
      doc = JSON.parse(jsonString);
    } catch (e) {
      return;
    }

    if (!doc || !doc.method) return;

    if (doc.method === 'initialize') {
      this.send({
        jsonrpc: "2.0",
        id: doc.id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: "AloT Smart Classroom Server", version: "2.0.0" }
        }
      });
      console.log(`[XiaoZhi MCP] Trả lời initialize thành công!`);
    } 
    else if (doc.method === 'notifications/initialized') {
      console.log(`[XiaoZhi MCP] Đã nhận notifications/initialized từ XiaoZhi Client.`);
    }
    else if (doc.method === 'tools/list') {
      this.send({
        jsonrpc: "2.0",
        id: doc.id,
        result: {
          tools: [
            {
              name: "control_light",
              description: "Điều khiển bật (ON) hoặc tắt (OFF) đèn chiếu sáng trong lớp học thông minh.",
              inputSchema: {
                type: "object",
                properties: {
                  state: { type: "string", enum: ["ON", "OFF"], description: "ON để bật đèn, OFF để tắt đèn" }
                },
                required: ["state"]
              }
            },
            {
              name: "control_fan",
              description: "Điều khiển bật (ON) hoặc tắt (OFF) quạt làm mát trong lớp học thông minh.",
              inputSchema: {
                type: "object",
                properties: {
                  state: { type: "string", enum: ["ON", "OFF"], description: "ON để bật quạt, OFF để tắt quạt" }
                },
                required: ["state"]
              }
            },
            {
              name: "control_door",
              description: "Điều khiển mở cửa (open / 90 độ), đóng cửa (close / 0 độ) hoặc quay góc tùy chọn.",
              inputSchema: {
                type: "object",
                properties: {
                  mode: { type: "string", enum: ["open", "close", "angle"], description: "open: mở 90 độ | close: đóng 0 độ | angle: góc tùy chọn" },
                  angle: { type: "integer", minimum: 0, maximum: 180, description: "Góc quay servo từ 0 đến 180 độ" }
                },
                required: ["mode"]
              }
            },
            {
              name: "set_classroom_mode",
              description: "Cài đặt chế độ hoạt động cho lớp học: AUTO (Tự động bật/tắt thiết bị theo cảm biến) hoặc MANUAL (Điều khiển thủ công).",
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
