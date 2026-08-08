const WebSocket = require('ws');

const XIAOZHI_URL = process.env.XIAOZHI_MCP_URL || "wss://api.xiaozhi.me/mcp/?token=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjg4MzEwMiwiYWdlbnRJZCI6MjE5MDk4MSwiZW5kcG9pbnRJZCI6ImFnZW50XzIxOTA5ODEiLCJwdXJwb3NlIjoibWNwLWVuZHBvaW50IiwiaWF0IjoxNzg1Njg2MDY4LCJleHAiOjE4MTcyNDM2Njh9.mA4TgMiFd3et8bjKDcVSquDsw-FXL42XYgXVKmNygAo_F9TWG_QYgA1P32i5QfOWx3rdWhyGWi4boK7U4eLvpw";

console.log('🤖 Connecting to Xiaozhi MCP WebSocket...');
const ws = new WebSocket(XIAOZHI_URL);

ws.on('open', () => {
  console.log('✅ Connected to Xiaozhi MCP Server!');
  
  const testMessage = "Xin chào, loa Xiaozhi đang phát âm thanh thông báo tự động!";
  console.log(`📢 Sending TTS speech notification: "${testMessage}"`);

  ws.send(JSON.stringify({
    jsonrpc: "2.0",
    method: "notifications/message",
    params: { message: testMessage }
  }));

  setTimeout(() => {
    ws.close();
    process.exit(0);
  }, 3000);
});

ws.on('message', (data) => {
  console.log('📩 RX from Xiaozhi MCP:', data.toString());
});

ws.on('error', (err) => {
  console.error('❌ MCP Error:', err.message);
});
