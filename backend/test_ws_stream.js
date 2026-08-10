const WebSocket = require('ws');

// Test WebSocket connection to backend streamer
const wsUrl = 'ws://localhost:3001/ws';
console.log(`🧪 [WS Test] Đang kết nối tới WebSocket Server tại: ${wsUrl}...`);

const ws = new WebSocket(wsUrl);

ws.on('open', () => {
  console.log('✅ [WS Test] Kết nối WebSocket thành công!');
  
  // Gửi test ping
  ws.send(JSON.stringify({ type: 'ping' }));

  // Giả lập MCP initialize
  ws.send(JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: { protocolVersion: "2024-11-05" }
  }));
});

ws.on('message', (data, isBinary) => {
  if (isBinary) {
    console.log(`🎵 [WS Test Binary Audio Frame] Nhận gói âm thanh binary: ${data.length} bytes`);
  } else {
    console.log(`📩 [WS Test JSON Message]: ${data.toString()}`);
  }
});

ws.on('error', (err) => {
  console.error('❌ [WS Test Lỗi]:', err.message);
});

ws.on('close', () => {
  console.log('❌ [WS Test] Đã ngắt kết nối WebSocket.');
  process.exit(0);
});

setTimeout(() => {
  console.log('🏁 [WS Test] Hoàn tất kiểm tra 5s.');
  ws.close();
}, 5000);
