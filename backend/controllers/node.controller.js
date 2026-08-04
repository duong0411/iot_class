const Node = require('../models/node.model');
const mqttService = require('../services/mqtt.service');

// GET /api/nodes - Lấy danh sách tất cả các Node của user
exports.getNodes = async (req, res) => {
  try {
    const nodes = await Node.find({ userId: req.userId });
    res.json({
      success: true,
      data: { nodes },
    });
  } catch (err) {
    console.error('Get nodes error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};

// POST /api/nodes - Thêm Node mới
exports.createNode = async (req, res) => {
  try {
    const { name, chipId, templateType, state } = req.body;
    
    // Kiểm tra xem chipId đã tồn tại chưa
    const existingNode = await Node.findOne({ userId: req.userId, chipId });
    if (existingNode) {
      return res.status(400).json({ success: false, message: 'Chip ID này đã được thêm.' });
    }

    const newNode = await Node.create({
      userId: req.userId,
      name,
      chipId,
      templateType,
      state: state || {}
    });

    // Thêm Node vào danh sách lắng nghe MQTT để bắn FCM
    mqttService.subscribeNode(newNode);

    res.status(201).json({
      success: true,
      message: 'Thêm Node thành công',
      data: { node: newNode },
    });
  } catch (err) {
    console.error('Create node error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};

// PUT /api/nodes/:id - Cập nhật thông tin/trạng thái Node
exports.updateNode = async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body; // Có thể chứa name, chipId, templateType, hoặc state

    const updatedNode = await Node.findOneAndUpdate(
      { _id: id, userId: req.userId },
      { $set: updateData },
      { new: true }
    );

    if (!updatedNode) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy Node' });
    }

    res.json({
      success: true,
      message: 'Cập nhật Node thành công',
      data: { node: updatedNode },
    });
  } catch (err) {
    console.error('Update node error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};

// DELETE /api/nodes/:id - Xóa Node
exports.deleteNode = async (req, res) => {
  try {
    const { id } = req.params;
    
    const deletedNode = await Node.findOneAndDelete({ _id: id, userId: req.userId });

    if (!deletedNode) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy Node' });
    }

    res.json({
      success: true,
      message: 'Xóa Node thành công',
    });
  } catch (err) {
    console.error('Delete node error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};
