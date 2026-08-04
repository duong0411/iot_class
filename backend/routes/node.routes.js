const express = require('express');
const router = express.Router();
const nodeController = require('../controllers/node.controller');
const authMiddleware = require('../middleware/auth.middleware');

// Tất cả node routes đều cần JWT
router.use(authMiddleware);

router.get('/', nodeController.getNodes);
router.post('/', nodeController.createNode);
router.put('/:id', nodeController.updateNode);
router.delete('/:id', nodeController.deleteNode);

module.exports = router;
