const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

let ffmpegPath = null;
try {
  ffmpegPath = require('ffmpeg-static');
} catch (_) {
  ffmpegPath = null;
}

const SAMPLE_RATE = 16000;
const FRAME_DURATION_MS = 60;

/**
 * Convert MP3/any audio → Ogg Opus (16 kHz mono), matching Xiaozhi cloud decode path.
 * Also demux Ogg pages into raw Opus packets for WebSocket streaming.
 */
class OpusService {
  constructor() {
    this.publicDir = path.join(__dirname, '../public/audio');
    if (!fs.existsSync(this.publicDir)) {
      fs.mkdirSync(this.publicDir, { recursive: true });
    }
  }

  get sampleRate() { return SAMPLE_RATE; }
  get frameDurationMs() { return FRAME_DURATION_MS; }

  resolveFfmpeg() {
    if (ffmpegPath && fs.existsSync(ffmpegPath)) return ffmpegPath;
    return 'ffmpeg';
  }

  /** voice_7h30.mp3 → voice_7h30.ogg */
  mp3ToOggName(filenameOrUrl) {
    const base = path.basename(String(filenameOrUrl || '').split('?')[0]);
    if (!base) return '';
    return base.replace(/\.mp3$/i, '.ogg').replace(/\.wav$/i, '.ogg');
  }

  oggPathFor(mp3Filename) {
    const oggName = this.mp3ToOggName(mp3Filename);
    return path.join(this.publicDir, oggName);
  }

  async ensureOggFromMp3(mp3Filename) {
    const mp3Name = path.basename(String(mp3Filename || '').split('?')[0]);
    if (!mp3Name) throw new Error('Thiếu tên file MP3');
    const mp3Path = path.join(this.publicDir, mp3Name);
    if (!fs.existsSync(mp3Path)) throw new Error(`Không thấy MP3: ${mp3Name}`);

    const oggName = this.mp3ToOggName(mp3Name);
    const oggPath = path.join(this.publicDir, oggName);

    if (fs.existsSync(oggPath) && fs.statSync(oggPath).mtimeMs >= fs.statSync(mp3Path).mtimeMs
        && fs.statSync(oggPath).size > 500) {
      return oggName;
    }

    await this._ffmpegToOgg(mp3Path, oggPath);
    if (!fs.existsSync(oggPath) || fs.statSync(oggPath).size < 500) {
      throw new Error('ffmpeg không tạo được Ogg Opus');
    }
    console.log(`🎵 [Opus] ${mp3Name} → ${oggName} (${fs.statSync(oggPath).size} bytes)`);
    return oggName;
  }

  _ffmpegToOgg(inputPath, outputPath) {
    const ff = this.resolveFfmpeg();
    const args = [
      '-y',
      '-i', inputPath,
      '-vn',
      '-ac', '1',
      '-ar', String(SAMPLE_RATE),
      '-c:a', 'libopus',
      '-b:a', '24k',
      '-vbr', 'on',
      '-compression_level', '10',
      '-application', 'audio',
      '-frame_duration', String(FRAME_DURATION_MS),
      '-f', 'ogg',
      outputPath
    ];

    return new Promise((resolve, reject) => {
      const child = spawn(ff, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
      let stderr = '';
      child.stderr.on('data', (d) => { stderr += d.toString(); });
      child.on('error', reject);
      child.on('close', (code) => {
        if (code === 0 && fs.existsSync(outputPath)) return resolve();
        reject(new Error(stderr.slice(-800) || `ffmpeg exit ${code}`));
      });
    });
  }

  /**
   * Extract raw Opus packets from an Ogg Opus file (skip OpusHead / OpusTags).
   */
  extractOpusPackets(oggBuffer) {
    const buf = Buffer.isBuffer(oggBuffer) ? oggBuffer : Buffer.from(oggBuffer);
    const packets = [];
    let offset = 0;
    let sawHead = false;
    let sawTags = false;

    while (offset + 27 <= buf.length) {
      if (buf.toString('ascii', offset, offset + 4) !== 'OggS') {
        offset++;
        continue;
      }
      const nsegs = buf[offset + 26];
      const segTableStart = offset + 27;
      if (segTableStart + nsegs > buf.length) break;

      let bodySize = 0;
      for (let i = 0; i < nsegs; i++) bodySize += buf[segTableStart + i];
      const bodyStart = segTableStart + nsegs;
      if (bodyStart + bodySize > buf.length) break;

      let bodyOff = 0;
      let packet = Buffer.alloc(0);
      for (let i = 0; i < nsegs; i++) {
        const segLen = buf[segTableStart + i];
        packet = Buffer.concat([packet, buf.slice(bodyStart + bodyOff, bodyStart + bodyOff + segLen)]);
        bodyOff += segLen;
        if (segLen < 255) {
          if (packet.length > 0) {
            const isHead = packet.length >= 8 && packet.toString('ascii', 0, 8) === 'OpusHead';
            const isTags = packet.length >= 8 && packet.toString('ascii', 0, 8) === 'OpusTags';
            if (isHead) {
              sawHead = true;
            } else if (isTags) {
              sawTags = true;
            } else if (sawHead) {
              packets.push(packet);
            }
          }
          packet = Buffer.alloc(0);
        }
      }
      offset = bodyStart + bodySize;
    }

    if (!sawHead) {
      console.warn('⚠️ [Opus] Ogg file missing OpusHead');
    }
    return packets;
  }

  async getOpusPacketsForMp3(mp3Filename) {
    const oggName = await this.ensureOggFromMp3(mp3Filename);
    const oggPath = path.join(this.publicDir, oggName);
    const data = fs.readFileSync(oggPath);
    const packets = this.extractOpusPackets(data);
    if (!packets.length) throw new Error('Không tách được Opus packet từ Ogg');
    return { oggName, packets, sampleRate: SAMPLE_RATE, frameDurationMs: FRAME_DURATION_MS };
  }

  /**
   * Resolve local mp3 filename from absolute/relative audio URL.
   */
  filenameFromAudioUrl(audioUrl) {
    try {
      const u = new URL(audioUrl, 'http://localhost');
      return path.basename(u.pathname);
    } catch (_) {
      return path.basename(String(audioUrl || ''));
    }
  }
}

module.exports = new OpusService();
