const jwt = require('jsonwebtoken');
const User = require('../models/user.model');
const Device = require('../models/device.model');
const { OAuth2Client } = require('google-auth-library');
const { getAuth, isFirebaseInitialized } = require('../config/firebase');

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || 'YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com';
const client = new OAuth2Client(GOOGLE_CLIENT_ID);

const generateToken = (userId) => {
  return jwt.sign(
    { id: userId },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN }
  );
};

// POST /api/auth/check-pre-register
exports.checkPreRegister = async (req, res) => {
  try {
    const { email, phone } = req.body;
    if (!email || !phone) {
      return res.status(400).json({ success: false, message: 'Vui lòng cung cấp email và số điện thoại' });
    }
    
    const existingUser = await User.findOne({ $or: [{ email: email.toLowerCase().trim() }, { phone: phone.trim() }] });
    if (existingUser) {
      if (existingUser.email === email.toLowerCase().trim()) {
        return res.status(409).json({ success: false, message: 'Email đã được sử dụng' });
      }
      return res.status(409).json({ success: false, message: 'Số điện thoại đã được sử dụng' });
    }

    res.json({ success: true, message: 'Thông tin hợp lệ, có thể gửi OTP' });
  } catch (err) {
    console.error('Check pre-register error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server, vui lòng thử lại' });
  }
};

// POST /api/auth/register
exports.register = async (req, res) => {
  try {
    const { name, email, phone, password, firebaseIdToken } = req.body;

    if (!name || !email || !phone || !password || !firebaseIdToken) {
      return res.status(400).json({ success: false, message: 'Vui lòng cung cấp đầy đủ thông tin' });
    }

    if (!isFirebaseInitialized) {
      return res.status(500).json({ success: false, message: 'Tính năng OTP chưa được cấu hình trên Server. Vui lòng thêm serviceAccountKey.json' });
    }

    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(firebaseIdToken);
    } catch (e) {
      return res.status(400).json({ success: false, message: 'Xác thực mã OTP thất bại' });
    }

    const firebasePhone = decodedToken.phone_number;
    let normalizedInputPhone = phone.trim();
    if (normalizedInputPhone.startsWith('0')) {
      normalizedInputPhone = '+84' + normalizedInputPhone.substring(1);
    }

    if (firebasePhone !== normalizedInputPhone) {
      return res.status(400).json({ success: false, message: 'Số điện thoại xác thực không khớp với đăng ký' });
    }

    const existingUser = await User.findOne({ $or: [{ email: email.toLowerCase().trim() }, { phone: phone.trim() }] });
    if (existingUser) {
      return res.status(409).json({ success: false, message: 'Email hoặc số điện thoại đã được sử dụng' });
    }

    const user = await User.create({
      name: name.trim(),
      email: email.toLowerCase().trim(),
      phone: phone.trim(),
      password,
    });

    await Device.create({ userId: user._id });

    const token = generateToken(user._id);

    res.status(201).json({
      success: true,
      message: 'Đăng ký thành công!',
      data: {
        token,
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          phone: user.phone,
          role: user.role,
          createdAt: user.createdAt,
        },
      },
    });
  } catch (err) {
    if (err.name === 'ValidationError') {
      const messages = Object.values(err.errors).map(e => e.message);
      return res.status(400).json({ success: false, message: messages.join(', ') });
    }
    console.error('Register error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server, vui lòng thử lại' });
  }
};

// POST /api/auth/login
exports.login = async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Vui lòng nhập email và mật khẩu',
      });
    }

    const user = await User.findOne({ 
      $or: [
        { email: email.toLowerCase().trim() },
        { phone: email.trim() } 
      ]
    }).select('+password');

    if (!user || !user.isActive) {
      return res.status(401).json({ success: false, message: 'Tài khoản hoặc mật khẩu không đúng' });
    }

    const isPasswordValid = await user.comparePassword(password);
    if (!isPasswordValid) {
      return res.status(401).json({ success: false, message: 'Tài khoản hoặc mật khẩu không đúng' });
    }

    user.lastLogin = new Date();
    await user.save({ validateBeforeSave: false });

    const token = generateToken(user._id);

    res.json({
      success: true,
      message: 'Đăng nhập thành công!',
      data: {
        token,
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          phone: user.phone,
          role: user.role,
          lastLogin: user.lastLogin,
          createdAt: user.createdAt,
        },
      },
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server, vui lòng thử lại' });
  }
};

// POST /api/auth/google-login
exports.googleLogin = async (req, res) => {
  try {
    const { idToken } = req.body;
    if (!idToken) return res.status(400).json({ success: false, message: 'Vui lòng cung cấp idToken' });

    const ticket = await client.verifyIdToken({
      idToken,
      audience: GOOGLE_CLIENT_ID, 
    });
    
    const payload = ticket.getPayload();
    const { sub: googleId, email, name, picture } = payload;

    let user = await User.findOne({ email: email.toLowerCase().trim() });

    if (user) {
      if (!user.isActive) return res.status(403).json({ success: false, message: 'Tài khoản đã bị khóa' });

      if (!user.googleId) {
        user.googleId = googleId;
        user.provider = 'google';
        if (!user.avatar && picture) user.avatar = picture;
        await user.save({ validateBeforeSave: false });
      }
    } else {
      user = await User.create({
        name,
        email: email.toLowerCase().trim(),
        googleId,
        provider: 'google',
        avatar: picture,
      });
      await Device.create({ userId: user._id });
    }

    user.lastLogin = new Date();
    await user.save({ validateBeforeSave: false });

    const token = generateToken(user._id);

    res.json({
      success: true,
      message: 'Đăng nhập Google thành công!',
      data: {
        token,
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          phone: user.phone,
          avatar: user.avatar,
          role: user.role,
          lastLogin: user.lastLogin,
          createdAt: user.createdAt,
        },
      },
    });

  } catch (err) {
    console.error('Google Login error:', err);
    res.status(401).json({ success: false, message: 'Xác thực Google thất bại' });
  }
};

// POST /api/auth/check-phone-exists
exports.checkPhoneExists = async (req, res) => {
  try {
    const { phone } = req.body;

    if (!phone) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập số điện thoại' });
    }

    const user = await User.findOne({
      $or: [{ email: phone.toLowerCase().trim() }, { phone: phone.trim() }]
    });

    if (!user) {
      return res.status(404).json({ success: false, message: 'Tài khoản không tồn tại trong hệ thống' });
    }

    res.json({ success: true, message: 'Số điện thoại hợp lệ' });
  } catch (err) {
    console.error('Check phone error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server, vui lòng thử lại' });
  }
};

// POST /api/auth/reset-password
exports.resetPassword = async (req, res) => {
  try {
    const { phone, firebaseIdToken, newPassword } = req.body;

    if (!phone || !firebaseIdToken || !newPassword) {
      return res.status(400).json({ success: false, message: 'Vui lòng cung cấp đầy đủ thông tin' });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ success: false, message: 'Mật khẩu mới ít nhất 6 ký tự' });
    }

    if (!isFirebaseInitialized) {
      return res.status(500).json({ success: false, message: 'Tính năng OTP chưa được cấu hình trên Server' });
    }

    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(firebaseIdToken);
    } catch (e) {
      return res.status(400).json({ success: false, message: 'Xác thực OTP thất bại' });
    }

    const firebasePhone = decodedToken.phone_number;
    let normalizedInputPhone = phone.trim();
    if (normalizedInputPhone.startsWith('0')) {
      normalizedInputPhone = '+84' + normalizedInputPhone.substring(1);
    }

    if (firebasePhone !== normalizedInputPhone) {
      return res.status(400).json({ success: false, message: 'Số điện thoại xác thực không khớp' });
    }

    const user = await User.findOne({
      $or: [{ email: phone.toLowerCase().trim() }, { phone: phone.trim() }]
    });

    if (!user) {
      return res.status(400).json({ success: false, message: 'Không tìm thấy tài khoản' });
    }

    user.password = newPassword;
    await user.save();

    res.json({ success: true, message: 'Đặt lại mật khẩu thành công! Vui lòng đăng nhập lại.' });
  } catch (err) {
    console.error('Reset password error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server, vui lòng thử lại' });
  }
};

// GET /api/auth/profile
exports.getProfile = async (req, res) => {
  try {
    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy người dùng' });
    }

    res.json({ success: true, data: { user } });
  } catch (err) {
    console.error('Get profile error:', err);
    res.status(500).json({ success: false, message: 'Lỗi server' });
  }
};
