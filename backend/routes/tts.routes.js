const express = require('express');
const router = express.Router();
const ttsService = require('../services/tts.service');
const xiaozhiService = require('../services/xiaozhi.service');
const mqttService = require('../services/mqtt.service');

/**
 * @route   POST /api/tts/say
 * @desc    Tạo file TTS Tiếng Việt mới tại https://duynguyen.io.vn và phát loa Xiaozhi ESP32 qua MQTT + Cloud
 * @body    { "prompt": "Đề nghị học sinh nghiêm túc truy bài..." }
 */
router.post('/say', async (req, res) => {
  try {
    const prompt = req.body.prompt || req.body.text;
    if (!prompt || typeof prompt !== 'string' || prompt.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Vui lòng cung cấp nội dung "prompt" hoặc "text"!'
      });
    }

    const cleanPrompt = prompt.trim();
    const filename = `voice_api_${Date.now()}.mp3`;
    
    // 1. Sinh file MP3 Tiếng Việt lưu tại https://duynguyen.io.vn/audio/
    const generatedFile = await ttsService.generateVietnameseTts(filename, cleanPrompt);
    const baseUrl = process.env.SERVER_BASE_URL || 'https://duynguyen.io.vn';
    const audioUrl = generatedFile ? `${baseUrl}/audio/${generatedFile}` : '';

    const ttsPayload = JSON.stringify({
      prompt: cleanPrompt,
      text: cleanPrompt,
      audio_url: audioUrl,
      say: true
    });

    // 2. Gửi tín hiệu phát loa Xiaozhi qua MQTT Topic 'cmnd/xiaozhi_tts/say'
    mqttService.publish('cmnd/xiaozhi_tts/say', ttsPayload);

    // 3. Gửi thông báo MCP nếu có kết nối WebSocket
    xiaozhiService.sendTtsSay(cleanPrompt);

    console.log(`📢 [API /api/tts/say] Streamed to Xiaozhi ESP32 via MQTT & Cloud: "${cleanPrompt}"`);
    console.log(`🔗 Audio URL: ${audioUrl}`);

    return res.json({
      success: true,
      message: 'Đã tạo voice Tiếng Việt và phát loa Xiaozhi thành công qua https://duynguyen.io.vn!',
      data: {
        prompt: cleanPrompt,
        audioUrl: audioUrl,
        filename: generatedFile,
        topic: 'cmnd/xiaozhi_tts/say'
      }
    });
  } catch (err) {
    console.error('❌ Lỗi API /api/tts/say:', err.message);
    return res.status(500).json({ success: false, message: 'Lỗi server nội bộ' });
  }
});

/**
 * @route   GET /api/tts/speak
 * @desc    Tạo giọng đọc & phát loa Xiaozhi trực tiếp qua URL GET
 * @query   ?text=Chao+cac+ban
 */
router.get('/speak', async (req, res) => {
  try {
    const prompt = req.query.text || req.query.prompt;
    if (!prompt) {
      return res.status(400).json({
        success: false,
        message: 'Vui lòng truyền query param ?text=Nội dung'
      });
    }

    const cleanPrompt = prompt.trim();
    const filename = `voice_api_${Date.now()}.mp3`;
    const generatedFile = await ttsService.generateVietnameseTts(filename, cleanPrompt);

    const baseUrl = process.env.SERVER_BASE_URL || 'https://duynguyen.io.vn';
    const audioUrl = `${baseUrl}/audio/${generatedFile}`;

    // Phát thoại trực tiếp tới Xiaozhi qua Cloud WebSocket
    xiaozhiService.sendTtsSay(cleanPrompt);

    return res.json({
      success: true,
      message: 'Đã phát loa Xiaozhi thành công qua Cloud!',
      audioUrl: audioUrl
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
