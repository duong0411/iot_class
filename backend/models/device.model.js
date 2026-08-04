const mongoose = require('mongoose');

const deviceSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
  },
  // Phòng Bếp
  kitchenLight: { type: Boolean, default: false },
  kitchenFan: { type: Boolean, default: false },
  kitchenFanSpeed: { type: Number, default: 1, min: 1, max: 3 },
  gasDetector: { type: Boolean, default: false },
  fireDetector: { type: Boolean, default: false },
  kitchenTemp: { type: Number, default: 28.5 },
  kitchenHumidity: { type: Number, default: 65.0 },

  // Phòng Khách
  livingRoomDoor: { type: Boolean, default: false },
  livingRoomDoorAngle: { type: Number, default: 0 },
  clothesDryer: { type: Boolean, default: false },
  clothesDryerAngle: { type: Number, default: 0 },
  livingRoomTemp: { type: Number, default: 26.0 },
  livingRoomHumidity: { type: Number, default: 70.0 },

  // Phòng Ngủ
  bedroomLight: { type: Boolean, default: false },
  bedroomFan: { type: Boolean, default: false },
  bedroomFanSpeed: { type: Number, default: 1, min: 1, max: 3 },
  bedroomDoor: { type: Boolean, default: false },
  bedroomDoorAngle: { type: Number, default: 0 },
  curtain: { type: Boolean, default: false },
  curtainAngle: { type: Number, default: 0 },
  bedroomTemp: { type: Number, default: 25.0 },
  bedroomHumidity: { type: Number, default: 60.0 },

}, {
  timestamps: true,
});

module.exports = mongoose.model('Device', deviceSchema);
