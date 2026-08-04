const mongoose = require('mongoose');

const nodeSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  chipId: {
    type: String,
    required: true,
  },
  templateType: {
    type: String,
    enum: ['kitchen_living', 'bedroom'],
    required: true,
  },
  state: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  }
}, {
  timestamps: true,
});

module.exports = mongoose.model('Node', nodeSchema);
