const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth.controller');
const authMiddleware = require('../middleware/auth.middleware');

// Public routes
router.post('/check-pre-register', authController.checkPreRegister);
router.post('/register', authController.register);
router.post('/login', authController.login);
router.post('/google-login', authController.googleLogin);

router.post('/check-phone-exists', authController.checkPhoneExists);
router.post('/reset-password', authController.resetPassword);

// Protected routes (cần JWT token)
router.get('/profile', authMiddleware, authController.getProfile);

module.exports = router;

