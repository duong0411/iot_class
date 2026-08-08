const googleTTS = require('google-tts-api');
const fs = require('fs');
const path = require('path');

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
      
      const base64Audio = await googleTTS.getAudioBase64(cleanPrompt, {
        lang: 'vi',
        slow: false,
        host: 'https://translate.google.com',
        timeout: 10000,
      });

      const buffer = Buffer.from(base64Audio, 'base64');
      fs.writeFileSync(filePath, buffer);
      console.log(`✅ [TTS Generator] Saved audio file to: ${filePath} (${buffer.length} bytes)`);

      return filename;
    } catch (error) {
      console.error('❌ [TTS Generator] Failed to generate TTS audio:', error.message);
      return null;
    }
  }
}

module.exports = new TtsService();
