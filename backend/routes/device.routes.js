const express = require('express');
const router = express.Router();
const deviceController = require('../controllers/device.controller');
const authMiddleware = require('../middleware/auth.middleware');

// Tất cả device routes đều cần JWT
router.use(authMiddleware);

router.get('/', deviceController.getDevices);
router.put('/sensors', deviceController.updateSensors);
router.put('/:field', deviceController.updateDevice);

module.exports = router;
