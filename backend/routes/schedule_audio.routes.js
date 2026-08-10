const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const youtubeService = require('../services/youtube.service');

const router = express.Router();
const audioDir = path.join(__dirname, '../public/audio');
if (!fs.existsSync(audioDir)) {
  fs.mkdirSync(audioDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, audioDir),
  filename: (req, file, cb) => {
    const hour = req.body.hour ?? 'x';
    const minute = req.body.minute ?? 'x';
    const safeBase = `voice_${hour}h${minute}`;
    const ext = path.extname(file.originalname || '').toLowerCase() === '.mp3' ? '.mp3' : '.mp3';
    cb(null, `${safeBase}${ext}`);
  }
});

const upload = multer({
  storage,
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const name = (file.originalname || '').toLowerCase();
    const ok = name.endsWith('.mp3') || (file.mimetype || '').includes('audio');
    cb(ok ? null : new Error('Chỉ chấp nhận file MP3 / audio'), ok);
  }
});

function baseUrl(req) {
  return process.env.SERVER_BASE_URL || `${req.protocol}://${req.get('host')}` || 'https://duynguyen.io.vn';
}

/**
 * POST /api/schedule/audio/upload
 * multipart: file + optional hour/minute
 */
router.post('/upload', upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Thiếu file MP3' });
    }
    const filename = req.file.filename;
    const audioUrl = `${baseUrl(req)}/audio/${filename}`;
    console.log(`📤 [Schedule Audio] Uploaded MP3: ${filename}`);
    return res.json({
      success: true,
      filename,
      audioUrl,
      audio_url: audioUrl
    });
  } catch (e) {
    return res.status(500).json({ success: false, message: e.message });
  }
});

/**
 * POST /api/schedule/audio/youtube
 * body: { url, hour?, minute?, id? }
 */
router.post('/youtube', async (req, res) => {
  try {
    const { url, hour, minute, id } = req.body || {};
    if (!url) {
      return res.status(400).json({ success: false, message: 'Thiếu link YouTube' });
    }
    const filename = `voice_${hour ?? 0}h${minute ?? 0}_${(id || 'yt').toString().slice(-6)}.mp3`
      .replace(/[^a-zA-Z0-9._-]/g, '_');
    const saved = await youtubeService.downloadAsMp3(url, filename);
    const audioUrl = `${baseUrl(req)}/audio/${saved}`;
    return res.json({
      success: true,
      filename: saved,
      audioUrl,
      audio_url: audioUrl,
      source: 'youtube',
      youtubeUrl: youtubeService.normalizeYoutubeUrl(url)
    });
  } catch (e) {
    console.error('❌ [Schedule YouTube]', e.message);
    return res.status(500).json({ success: false, message: e.message });
  }
});

module.exports = router;
