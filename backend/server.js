const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

// Khởi tạo Firebase Admin
require('./config/firebase');

const authRoutes = require('./routes/auth.routes');
const nodeRoutes = require('./routes/node.routes');
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

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 AloT Smart Classroom Backend đang chạy tại http://0.0.0.0:${PORT}`);
  console.log(`📱 Flutter app kết nối tới Backend & XiaoZhi MCP Server qua MQTT WSS!`);
});
