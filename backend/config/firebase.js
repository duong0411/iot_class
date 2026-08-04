const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const fs = require('fs');
const path = require('path');

// Đường dẫn tới file serviceAccountKey.json
const serviceAccountPath = path.join(__dirname, '../serviceAccountKey.json');

let isFirebaseInitialized = false;

if (fs.existsSync(serviceAccountPath)) {
  const serviceAccount = require(serviceAccountPath);

  initializeApp({
    credential: cert(serviceAccount)
  });
  console.log('✅ Firebase Admin đã được khởi tạo!');
  isFirebaseInitialized = true;
} else {
  console.warn('⚠️ CẢNH BÁO: Không tìm thấy file serviceAccountKey.json ở thư mục backend.');
  console.warn('⚠️ Tính năng gửi OTP bằng Firebase (Phone Auth) sẽ không hoạt động cho đến khi bạn thêm file này.');
}

module.exports = {
  getAuth,
  isFirebaseInitialized
};
