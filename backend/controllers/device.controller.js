const Device = require('../models/device.model');

// GET /api/devices - Lấy trạng thái tất cả thiết bị
exports.getDevices = async (req, res) => {
  try {
    let device = await Device.findOne({ userId: req.userId });
    
    // Nếu chưa có, tạo mới
    if (!device) {
      device = await Device.create({ userId: req.userId });
    }

    res.json({
      success: true,
      data: { device },
    });
  } catch (err) {
    console.error('Get devices error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};

// PUT /api/devices/:field - Cập nhật trạng thái thiết bị
exports.updateDevice = async (req, res) => {
  try {
    const { field } = req.params;
    const { value } = req.body;

    // Danh sách các field được phép update
    const allowedFields = [
      'kitchenLight', 'kitchenFan', 'kitchenFanSpeed',
      'livingRoomDoor', 'clothesDryer',
      'bedroomLight', 'bedroomFan', 'bedroomFanSpeed',
      'bedroomDoor', 'curtain',
    ];

    if (!allowedFields.includes(field)) {
      return res.status(400).json({
        success: false,
        message: `Field '${field}' không hợp lệ`,
      });
    }

    const device = await Device.findOneAndUpdate(
      { userId: req.userId },
      { 
        [field]: value,
        // Tự tính angle cho servo
        ...(field === 'livingRoomDoor' && { livingRoomDoorAngle: value ? 90 : 0 }),
        ...(field === 'clothesDryer' && { clothesDryerAngle: value ? 90 : 0 }),
        ...(field === 'bedroomDoor' && { bedroomDoorAngle: value ? 90 : 0 }),
        ...(field === 'curtain' && { curtainAngle: value ? 90 : 0 }),
      },
      { new: true, upsert: true }
    );

    res.json({
      success: true,
      message: `Đã cập nhật ${field}`,
      data: { device },
    });
  } catch (err) {
    console.error('Update device error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};

// PUT /api/devices/sensors - Cập nhật dữ liệu cảm biến (từ ESP32/Arduino)
exports.updateSensors = async (req, res) => {
  try {
    const {
      kitchenTemp, kitchenHumidity,
      livingRoomTemp, livingRoomHumidity,
      bedroomTemp, bedroomHumidity,
      gasDetector, fireDetector,
    } = req.body;

    const updateData = {};
    if (kitchenTemp !== undefined) updateData.kitchenTemp = kitchenTemp;
    if (kitchenHumidity !== undefined) updateData.kitchenHumidity = kitchenHumidity;
    if (livingRoomTemp !== undefined) updateData.livingRoomTemp = livingRoomTemp;
    if (livingRoomHumidity !== undefined) updateData.livingRoomHumidity = livingRoomHumidity;
    if (bedroomTemp !== undefined) updateData.bedroomTemp = bedroomTemp;
    if (bedroomHumidity !== undefined) updateData.bedroomHumidity = bedroomHumidity;
    if (gasDetector !== undefined) updateData.gasDetector = gasDetector;
    if (fireDetector !== undefined) updateData.fireDetector = fireDetector;

    const device = await Device.findOneAndUpdate(
      { userId: req.userId },
      updateData,
      { new: true, upsert: true }
    );

    res.json({
      success: true,
      message: 'Đã cập nhật dữ liệu cảm biến',
      data: { device },
    });
  } catch (err) {
    console.error('Update sensors error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};
