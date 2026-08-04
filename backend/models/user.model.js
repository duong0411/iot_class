const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
  name: {
    type: String,
    required: [true, 'Tên không được để trống'],
    trim: true,
    minlength: [2, 'Tên ít nhất 2 ký tự'],
    maxlength: [50, 'Tên tối đa 50 ký tự'],
  },
  email: {
    type: String,
    required: [true, 'Email không được để trống'],
    unique: true,
    lowercase: true,
    trim: true,
    match: [/^\S+@\S+\.\S+$/, 'Email không hợp lệ'],
  },
  phone: {
    type: String,
    sparse: true,
    unique: true,
    trim: true,
    match: [/^(0[3|5|7|8|9])+([0-9]{8})$/, 'Số điện thoại không hợp lệ'],
  },
  password: {
    type: String,
    minlength: [6, 'Mật khẩu ít nhất 6 ký tự'],
    select: false, // Không trả về password khi query
  },
  avatar: {
    type: String,
    default: null,
  },
  provider: {
    type: String,
    enum: ['local', 'google'],
    default: 'local',
  },
  googleId: {
    type: String,
    sparse: true,
    unique: true,
  },

  role: {
    type: String,
    enum: ['user', 'admin'],
    default: 'user',
  },
  isActive: {
    type: Boolean,
    default: true,
  },
  lastLogin: {
    type: Date,
    default: null,
  },
  homeId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Home',
    default: null,
  },
  resetPasswordToken: {
    type: String,
    default: null,
  },
  resetPasswordExpires: {
    type: Date,
    default: null,
  },
  registerOtp: {
    type: String,
    default: null,
  },
  registerOtpExpires: {
    type: Date,
    default: null,
  },
}, {
  timestamps: true, // Tự động thêm createdAt và updatedAt
});

// Validate conditionally based on provider
userSchema.pre('validate', function(next) {
  if (this.provider === 'local') {
    if (!this.phone) {
      this.invalidate('phone', 'Số điện thoại không được để trống');
    }
    if (!this.password && this.isNew) {
      this.invalidate('password', 'Mật khẩu không được để trống');
    }
  }
  next();
});

// Hash mật khẩu trước khi lưu
userSchema.pre('save', async function(next) {
  if (!this.isModified('password')) return next();
  
  const salt = await bcrypt.genSalt(12);
  this.password = await bcrypt.hash(this.password, salt);
  next();
});

// Method kiểm tra mật khẩu
userSchema.methods.comparePassword = async function(candidatePassword) {
  return await bcrypt.compare(candidatePassword, this.password);
};

// Ẩn thông tin nhạy cảm khi convert sang JSON
userSchema.methods.toJSON = function() {
  const obj = this.toObject();
  delete obj.password;
  delete obj.resetPasswordToken;
  delete obj.resetPasswordExpires;
  delete obj.registerOtp;
  delete obj.registerOtpExpires;
  return obj;
};

module.exports = mongoose.model('User', userSchema);
