const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

// Khởi tạo Firebase Admin
require('./config/firebase');

const authRoutes = require('./routes/auth.routes');
const nodeRoutes = require('./routes/node.routes');
const ttsRoutes = require('./routes/tts.routes');
const MqttService = require('./services/mqtt.service');
const XiaoZhiService = require('./services/xiaozhi.service');

const path = require('path');

const app = express();

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/audio', express.static(path.join(__dirname, 'public/audio')));

// Connect to MongoDB
mongoose.connect(process.env.MONGODB_URI)
  .then(() => {
    console.log('✅ Kết nối MongoDB thành công!');
    console.log(`📦 Database: ${process.env.MONGODB_URI}`);

    // Khởi tạo MQTT Service lắng nghe cảnh báo
    const mqttService = require('./services/mqtt.service');
    mqttService.connect();
    XiaoZhiService.connect();
  })
  .catch((err) => {
    console.error('❌ Lỗi kết nối MongoDB:', err.message);
    process.exit(1);
  });

// Routes
app.use('/api/auth', authRoutes);
// Vô hiệu hoá deviceRoutes cũ
// app.use('/api/devices', deviceRoutes); 
app.use('/api/nodes', nodeRoutes);
app.use('/api/tts', ttsRoutes);

// HTTP Endpoint phục vụ Xiaozhi ESP32 gọi trực tiếp tải danh sách Lịch & MP3 Voice URL (Không qua MQTT)
let httpSchedules = [];

app.get('/api/schedule', (req, res) => {
  const mqttService = require('./services/mqtt.service');
  const schedules = (mqttService.schedules && mqttService.schedules.length > 0) ? mqttService.schedules : httpSchedules;
  res.json({ schedules });
});

app.post('/api/schedule', async (req, res) => {
  const { schedules } = req.body;
  if (Array.isArray(schedules)) {
    const ttsService = require('./services/tts.service');
    const serverBaseUrl = process.env.SERVER_BASE_URL || 'https://duynguyen.io.vn';

    httpSchedules = await Promise.all(schedules.map(async s => {
      const filename = `voice_${s.hour ?? 0}h${s.minute ?? 0}.mp3`;
      if (s.prompt) {
        await ttsService.generateVietnameseTts(filename, s.prompt);
      }
      return {
        ...s,
        audio_url: `${serverBaseUrl}/audio/${filename}`
      };
    }));

    const mqttService = require('./services/mqtt.service');
    mqttService.schedules = httpSchedules;

    console.log(`📡 [HTTP API /api/schedule] Updated ${httpSchedules.length} schedules via HTTP Cloud!`);
    return res.json({ success: true, message: 'Đã cập nhật lịch qua HTTP thành công!', schedules: httpSchedules });
  }
  return res.status(400).json({ success: false, message: 'Invalid payload' });
});

// Test: kích hoạt cùng logic lịch (MCP tools qua MQTT)
app.get('/api/test/truy-bai', (req, res) => {
  const XiaoZhiService = require('./services/xiaozhi.service');
  XiaoZhiService.runMcpToolLocal('control_all_devices', { state: 'ON' });
  XiaoZhiService.runMcpToolLocal('control_door', { mode: 'open' });
  XiaoZhiService.runMcpToolLocal('set_classroom_mode', { mode: 'MANUAL' });
  res.json({
    success: true,
    message: '7:45 sim: control_all_devices ON + door open + mode MANUAL'
  });
});

app.get('/api/test/tan-hoc', (req, res) => {
  const XiaoZhiService = require('./services/xiaozhi.service');
  XiaoZhiService.runMcpToolLocal('control_all_devices', { state: 'OFF' });
  XiaoZhiService.runMcpToolLocal('control_door', { mode: 'close' });
  XiaoZhiService.runMcpToolLocal('control_light', { state: 'OFF' });
  XiaoZhiService.runMcpToolLocal('control_fan', { state: 'OFF' });
  res.json({
    success: true,
    message: '17:00 sim: control_all_devices OFF + door close'
  });
});

// Health check
app.get('/', (req, res) => {
  res.json({
    message: '🏫 AloT Smart Classroom & XiaoZhi MCP API đang chạy!',
    version: '2.0.0',
    testEndpoints: {
      testTruyBai: 'GET /api/test/truy-bai',
      testTanHoc: 'GET /api/test/tan-hoc'
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Endpoint không tồn tại' });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ success: false, message: 'Lỗi server nội bộ' });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 AloT Smart Classroom Backend đang chạy tại http://0.0.0.0:${PORT}`);
  console.log(`📱 Flutter app kết nối tới Backend & XiaoZhi MCP Server qua MQTT WSS!`);
});
