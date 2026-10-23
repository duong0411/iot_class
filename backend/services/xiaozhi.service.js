const WebSocket = require('ws');
const mqttService = require('./mqtt.service');

// XIAOZHI MCP ENDPOINT (WebSockets Client MCP Endpoint)
const XIAOZHI_URL = process.env.XIAOZHI_MCP_URL || "wss://api.xiaozhi.me/mcp/?token=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjg4MzEwMiwiYWdlbnRJZCI6MjUyNzU3MSwiZW5kcG9pbnRJZCI6ImFnZW50XzI1Mjc1NzEiLCJwdXJwb3NlIjoibWNwLWVuZHBvaW50IiwiaWF0IjoxNzkyNzY1ODk5LCJleHAiOjE4MjQzMjM0OTl9.P0NsBdqh314qccpAnflMqDT-hRk7VEoKfberHb3Gfa1VC9fOPKksZ0o1yIrZUgQvLNfPj8CqT2se3R2eA9QbbA";

class XiaoZhiService {
  constructor() {
    this.ws = null;
    this.reconnectTimeout = null;
    this.pingInterval = null;
    this.schedulerInterval = null;
    this.reconnectAttempt = 0;
    this.intentionalClose = false;
    this.connecting = false;
    this.lastPongAt = 0;
  }

  connect() {
    if (this.connecting) {
      return;
    }
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      console.log('ℹ️ XiaoZhi MCP đã kết nối / đang kết nối, bỏ qua connect() trùng.');
      return;
    }

    this.cleanupSocket();
    this.intentionalClose = false;
    this.connecting = true;

    console.log(`🤖 Đang kết nối tới XiaoZhi MCP Server (Smart Classroom)...`);
    this.ws = new WebSocket(XIAOZHI_URL, {
      handshakeTimeout: 15000,
      perMessageDeflate: false,
    });

    this.ws.on('open', () => {
      this.connecting = false;
      this.reconnectAttempt = 0;
      this.lastPongAt = Date.now();
      console.log('✅ XiaoZhi MCP cho Lớp Học Thông Minh đã kết nối thành công!');

      if (this.pingInterval) clearInterval(this.pingInterval);
      // WS ping giữ NAT/proxy sống; cloud Xiaozhi cũng hay idle-timeout ~60–90s.
      this.pingInterval = setInterval(() => {
        if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;

        // Nếu quá 70s không nhận pong → socket zombie, cắt để reconnect.
        if (this.lastPongAt && Date.now() - this.lastPongAt > 70000) {
          console.warn('⚠️ XiaoZhi MCP không trả pong >70s, terminate để kết nối lại...');
          try { this.ws.terminate(); } catch (_) {}
          return;
        }

        try {
          this.ws.ping();
        } catch (e) {
          console.error('❌ Lỗi WS ping:', e.message);
        }
      }, 20000);

      this.startClassroomScheduler();
    });

    this.ws.on('pong', () => {
      this.lastPongAt = Date.now();
    });

    this.ws.on('message', (data) => {
      this.lastPongAt = Date.now();
      this.handleJsonRpc(data.toString());
    });

    this.ws.on('close', (code, reasonBuf) => {
      this.connecting = false;
      if (this.pingInterval) {
        clearInterval(this.pingInterval);
        this.pingInterval = null;
      }

      const reason = reasonBuf ? reasonBuf.toString() : '';
      console.log(`❌ XiaoZhi MCP ngắt kết nối (code=${code}, reason=${reason || 'n/a'}).`);

      if (this.intentionalClose) {
        console.log('ℹ️ Đóng MCP chủ động — không reconnect.');
        return;
      }

      this.scheduleReconnect();
    });

    this.ws.on('error', (err) => {
      this.connecting = false;
      console.error('❌ Lỗi XiaoZhi WS:', err.message);
    });
  }

  cleanupSocket() {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
    if (this.ws) {
      try {
        this.ws.removeAllListeners();
        if (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING) {
          this.ws.terminate();
        }
      } catch (_) {}
      this.ws = null;
    }
  }

  scheduleReconnect() {
    if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout);
    this.reconnectAttempt += 1;
    // 5s, 10s, 20s... tối đa 60s — tránh spam khi cloud kick liên tục.
    const delay = Math.min(60000, 5000 * Math.pow(2, Math.min(this.reconnectAttempt - 1, 3)));
    console.log(`🔁 Thử kết nối lại MCP sau ${Math.round(delay / 1000)}s (lần ${this.reconnectAttempt})...`);
    this.reconnectTimeout = setTimeout(() => this.connect(), delay);
  }

  disconnect() {
    this.intentionalClose = true;
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    this.cleanupSocket();
  }

  // BỘ LỊCH TỰ ĐỘNG ĐỘNG (Nhận dữ liệu từ Mobile App qua MQTT mqtt.duynguyen.io.vn)
  startClassroomScheduler() {
    if (this.schedulerInterval) return;

    console.log('⏰ Bộ lịch tự động Lớp học từ Mobile App (mqtt.duynguyen.io.vn) đã kích hoạt!');

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

    // Firmware CLASSROOM_02 tự đảo relay active-LOW. MCP gửi ON/OFF đúng nghĩa thật.
    if (toolName === 'control_light') {
      const wantOn = args.state === 'ON';
      mqttValue = wantOn ? 'ON' : 'OFF';
      mqttTopic = 'cmnd/CLASSROOM_02_led/POWER';
      responseText = `Đã ${wantOn ? 'bật' : 'tắt'} đèn và chuyển đèn sang thủ công.`;
    } else if (toolName === 'control_fan') {
      const wantOn = args.state === 'ON';
      mqttValue = wantOn ? 'ON' : 'OFF';
      mqttTopic = 'cmnd/CLASSROOM_02_fan/POWER';
      responseText = `Đã ${wantOn ? 'bật' : 'tắt'} quạt và chuyển quạt sang thủ công.`;
    } else if (toolName === 'set_light_mode') {
      mqttValue = args.mode === 'MANUAL' ? 'MANUAL' : 'AUTO';
      mqttTopic = 'cmnd/CLASSROOM_02_led_mode/POWER';
      responseText = `Đèn chuyển ${mqttValue}. Tự động bật khi tối dưới 40% và tắt từ 45%.`;
    } else if (toolName === 'set_fan_mode') {
      mqttValue = args.mode === 'MANUAL' ? 'MANUAL' : 'AUTO';
      mqttTopic = 'cmnd/CLASSROOM_02_fan_mode/POWER';
      responseText = `Quạt chuyển ${mqttValue}. Tự động bật trên 30 độ hoặc có gas, tắt từ 29.5 độ.`;
    } else if (toolName === 'control_door') {
      if (args.mode === 'open') mqttValue = 'OPEN';
      else if (args.mode === 'close') mqttValue = 'CLOSE';
      else if (args.mode === 'angle') mqttValue = args.angle != null ? String(args.angle) : '0';
      else mqttValue = 'CLOSE';
      mqttTopic = 'cmnd/CLASSROOM_02_door/POWER';
      responseText = `Cửa ${mqttValue}. Thẻ hợp lệ cần thân nhiệt 33 đến 40 độ, cửa tự đóng sau 5 giây.`;
    } else if (toolName === 'set_classroom_mode') {
      mqttValue = args.mode === 'MANUAL' ? 'MANUAL' : 'AUTO';
      mqttService.publish('cmnd/CLASSROOM_02_led_mode/POWER', mqttValue);
      mqttService.publish('cmnd/CLASSROOM_02_fan_mode/POWER', mqttValue);
      responseText = `Đèn và quạt chuyển ${mqttValue}.`;
      return responseText;
    } else if (toolName === 'read_environment') {
      const cache = mqttService.envCache;
      responseText = `Nhiệt độ ${cache.temp}°C, độ ẩm ${cache.humi}%, ánh sáng ${cache.light}, thân nhiệt ${cache.body}, đèn ${cache.led} (${cache.ledMode}), quạt ${cache.fan} (${cache.fanMode}), cửa ${cache.door}, gas ${cache.gas}, cháy ${cache.fire}.`;
    } else if (toolName === 'control_all_devices') {
      const state = args.state === 'ON' ? 'ON' : 'OFF';
      mqttService.publish('cmnd/CLASSROOM_02_led/POWER', state);
      mqttService.publish('cmnd/CLASSROOM_02_fan/POWER', state);
      responseText = `Đã ${state === 'ON' ? 'bật' : 'tắt'} đèn và quạt.`;
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

  getTools() {
    return [
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
        name: "set_light_mode",
        description: "Chọn AUTO hoặc MANUAL riêng cho đèn. AUTO bật khi ánh sáng digital dưới 40% và tắt khi từ 45%.",
        inputSchema: {
          type: "object",
          properties: {
            mode: { type: "string", enum: ["AUTO", "MANUAL"] }
          },
          required: ["mode"]
        }
      },
      {
        name: "set_fan_mode",
        description: "Chọn AUTO hoặc MANUAL riêng cho quạt. AUTO bật khi nhiệt độ trên 30 độ hoặc có gas/CO2, tắt khi từ 29.5 độ trở xuống.",
        inputSchema: {
          type: "object",
          properties: {
            mode: { type: "string", enum: ["AUTO", "MANUAL"] }
          },
          required: ["mode"]
        }
      },
      {
        name: "set_classroom_mode",
        description: "Đặt cùng lúc đèn và quạt sang AUTO hoặc MANUAL.",
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
    ];
  }

  handleJsonRpc(jsonString) {
    let doc;
    try {
      doc = JSON.parse(jsonString);
    } catch (e) {
      return;
    }

    if (!doc || typeof doc !== 'object') return;

    // Response / error từ phía cloud — không cần trả lời.
    if (doc.result !== undefined || doc.error !== undefined) {
      return;
    }

    if (!doc.method) return;

    const hasId = doc.id !== undefined && doc.id !== null;

    if (doc.method === 'initialize') {
      this.send({
        jsonrpc: "2.0",
        id: doc.id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: {
            tools: { listChanged: false }
          },
          serverInfo: { name: "AloT Smart Classroom Server", version: "2.0.0" }
        }
      });
      console.log(`[XiaoZhi MCP] Trả lời initialize thành công!`);
      return;
    }

    if (doc.method === 'notifications/initialized' || doc.method === 'notifications/cancelled') {
      console.log(`[XiaoZhi MCP] Nhận ${doc.method}`);
      return;
    }

    // JSON-RPC ping — bắt buộc trả lời, không trả thì cloud cắt socket.
    if (doc.method === 'ping') {
      if (hasId) {
        this.send({ jsonrpc: "2.0", id: doc.id, result: {} });
      }
      return;
    }

    if (doc.method === 'tools/list') {
      this.send({
        jsonrpc: "2.0",
        id: doc.id,
        result: {
          tools: this.getTools(),
          nextCursor: ""
        }
      });
      console.log(`[XiaoZhi MCP] Đã gửi danh sách Tools cho Lớp Học Thông Minh`);
      return;
    }

    if (doc.method === 'tools/call') {
      const toolName = doc.params?.name;
      const args = doc.params?.arguments || {};
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
      return;
    }

    // resources/list, prompts/list, ... — phải trả lời nếu có id, nếu không cloud timeout rồi disconnect.
    if (hasId) {
      console.log(`[XiaoZhi MCP] Method chưa hỗ trợ "${doc.method}" — trả empty/error để giữ kết nối.`);
      if (doc.method === 'resources/list') {
        this.send({ jsonrpc: "2.0", id: doc.id, result: { resources: [] } });
      } else if (doc.method === 'prompts/list') {
        this.send({ jsonrpc: "2.0", id: doc.id, result: { prompts: [] } });
      } else if (doc.method === 'resources/templates/list') {
        this.send({ jsonrpc: "2.0", id: doc.id, result: { resourceTemplates: [] } });
      } else {
        this.send({
          jsonrpc: "2.0",
          id: doc.id,
          error: { code: -32601, message: `Method not found: ${doc.method}` }
        });
      }
    } else {
      console.log(`[XiaoZhi MCP] Bỏ qua notification: ${doc.method}`);
    }
  }
}

module.exports = new XiaoZhiService();
