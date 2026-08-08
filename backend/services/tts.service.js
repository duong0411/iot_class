const fs = require('fs');
const path = require('path');
const https = require('https');

class TtsService {
  constructor() {
    this.publicDir = path.join(__dirname, '../public/audio');
    if (!fs.existsSync(this.publicDir)) {
      fs.mkdirSync(this.publicDir, { recursive: true });
    }
  }

  /**
   * Generates a Vietnamese MP3 audio file for the given text prompt.
   * Saves to public/audio/{scheduleId}.mp3 and returns the relative URL.
   */
  async generateVietnameseTts(scheduleId, textPrompt) {
    let cleanPrompt = (textPrompt || '').replace(/[^\p{L}\p{N}\s.,!?-]/gu, ' ').replace(/\s+/g, ' ').trim();
    if (!cleanPrompt || cleanPrompt.length < 2) {
      cleanPrompt = 'Đã đến giờ thông báo tự động!';
    }

    try {
      const sanitizedId = scheduleId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const filename = `${sanitizedId}.mp3`;
      const filePath = path.join(this.publicDir, filename);

      console.log(`🎙️ [TTS Generator] Generating Vietnamese audio for prompt: "${cleanPrompt}"...`);
      
      const encodedText = encodeURIComponent(cleanPrompt);
      const url = `https://translate.google.com/translate_tts?ie=UTF-8&q=${encodedText}&tl=vi&client=tw-ob`;

      await new Promise((resolve, reject) => {
        const fileStream = fs.createWriteStream(filePath);
        https.get(url, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
          }
        }, (res) => {
          if (res.statusCode !== 200) {
            return reject(new Error(`Google TTS status code: ${res.statusCode}`));
          }
          res.pipe(fileStream);
          fileStream.on('finish', () => {
            fileStream.close();
            resolve();
          });
        }).on('error', (err) => {
          fs.unlink(filePath, () => {});
          reject(err);
        });
      });

      const stats = fs.statSync(filePath);
      console.log(`✅ [TTS Generator] Saved audio file to: ${filePath} (${stats.size} bytes)`);

      return filename;
    } catch (error) {
      console.error('❌ [TTS Generator] Failed to generate TTS audio:', error.message);
      return null;
    }
  }
}

module.exports = new TtsService();
