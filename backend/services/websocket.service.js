const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

class WebSocketService {
  constructor() {
    this.wss = null;
    this.clients = new Set();
  }

  /**
   * Khởi tạo WebSocket Server gắn với Express HTTP Server
   */
  init(server) {
    this.wss = new WebSocket.Server({ server, path: '/ws' });

    console.log('📡 [WebSocket Server] Đã kích hoạt WebSocket Audio Streamer tại path: /ws');

    this.wss.on('connection', (ws, req) => {
      const clientIp = req.socket.remoteAddress;
      console.log(`🔌 [WebSocket Server] Thiết bị mới kết nối từ: ${clientIp}`);
      this.clients.add(ws);

      // Gửi tin nhắn chào mừng & xác nhận kết nối
      ws.send(JSON.stringify({
        type: 'connection_ack',
        message: 'Kết nối WebSocket Server thành công!',
        timestamp: Date.now()
      }));

      ws.on('message', (data) => {
        try {
          const messageStr = data.toString();
          console.log(`📥 [WebSocket Message]: ${messageStr}`);
          
          let parsed;
          try { parsed = JSON.parse(messageStr); } catch (e) {}

          if (parsed) {
            // Xử lý các loại tin nhắn từ ESP32 / Mobile
            if (parsed.type === 'ping') {
              ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
            } else if (parsed.method === 'initialize') {
              ws.send(JSON.stringify({
                jsonrpc: "2.0",
                id: parsed.id,
                result: {
                  protocolVersion: "2024-11-05",
                  capabilities: { tools: {} },
                  serverInfo: { name: "AloT Smart Classroom Server", version: "2.0.0" }
                }
              }));
            }
          }
        } catch (err) {
          console.error('❌ Lỗi xử lý WebSocket message:', err.message);
        }
      });

      ws.on('close', () => {
        console.log(`❌ [WebSocket Server] Thiết bị đã ngắt kết nối: ${clientIp}`);
        this.clients.delete(ws);
      });

      ws.on('error', (err) => {
        console.error(`⚠️ [WebSocket Error] ${clientIp}:`, err.message);
        this.clients.delete(ws);
      });
    });
  }

  /**
   * Broadcast tin nhắn TTS & Stream âm thanh MP3/Opus qua WebSocket tới tất cả Xiaozhi ESP32 đang kết nối
   */
  async streamTtsToEsp32(promptText, audioUrl, filename = null) {
    if (!promptText) return;

    console.log(`📢 [WebSocket Audio Streamer] Đang stream câu thoại tới ${this.clients.size} clients: "${promptText}"`);

    const jsonPayload = JSON.stringify({
      type: 'tts_play',
      prompt: promptText,
      text: promptText,
      audio_url: audioUrl,
      timestamp: Date.now()
    });

    const jsonRpcPayload = JSON.stringify({
      jsonrpc: "2.0",
      method: "notifications/message",
      params: { 
        message: promptText,
        audio_url: audioUrl 
      }
    });

    // 1. Gửi tin nhắn điều khiển dạng JSON cho tất cả các kết nối WS
    this.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(jsonPayload);
        client.send(jsonRpcPayload);
      }
    });

    // 2. Nếu có file âm thanh cục bộ, đọc và stream từng chunk binary âm thanh 4KB qua WebSocket
    if (filename) {
      const filePath = path.join(__dirname, '../public/audio', filename);
      if (fs.existsSync(filePath)) {
        try {
          const audioBuffer = fs.readFileSync(filePath);
          const chunkSize = 4096; // Chunk 4KB
          console.log(`🎵 [WebSocket Binary Stream] Đang stream binary file ${filename} (${audioBuffer.length} bytes)...`);

          this.clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
              // Gửi tín hiệu bắt đầu stream âm thanh
              client.send(JSON.stringify({ type: 'audio_stream_start', size: audioBuffer.length, filename }));

              for (let offset = 0; offset < audioBuffer.length; offset += chunkSize) {
                const chunk = audioBuffer.slice(offset, offset + chunkSize);
                client.send(chunk, { binary: true });
              }

              // Gửi tín hiệu kết thúc stream âm thanh
              client.send(JSON.stringify({ type: 'audio_stream_end', filename }));
            }
          });

          console.log(`✅ [WebSocket Binary Stream] Stream âm thanh hoàn tất!`);
        } catch (e) {
          console.error('❌ Lỗi stream binary audio:', e.message);
        }
      }
    }
  }
}

module.exports = new WebSocketService();
