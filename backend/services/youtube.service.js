const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const http = require('http');
const { spawn } = require('child_process');

let ffmpegPath = null;
try {
  ffmpegPath = require('ffmpeg-static');
} catch (_) {
  ffmpegPath = null;
}

let youtubeDlExec = null;
try {
  youtubeDlExec = require('youtube-dl-exec');
} catch (_) {
  youtubeDlExec = null;
}

/** Temp dir without spaces — yt-dlp on Windows breaks with "C:\Users\Duong Phung\..." */
function safeTempDir() {
  const candidates = [
    'C:\\Temp',
    path.join('C:', 'Windows', 'Temp'),
    process.env.TEMP,
    process.env.TMP,
    os.tmpdir()
  ].filter(Boolean);
  for (const c of candidates) {
    if (!/\s/.test(c)) {
      try {
        if (!fs.existsSync(c)) fs.mkdirSync(c, { recursive: true });
        return c;
      } catch (_) {}
    }
  }
  return os.tmpdir();
}

function resolveFfmpegDir() {
  if (!ffmpegPath || !fs.existsSync(ffmpegPath)) return null;
  // Paths with spaces break youtube-dl-exec (shell:true on Windows).
  if (!/\s/.test(ffmpegPath)) return path.dirname(ffmpegPath);

  const destDir = path.join(safeTempDir(), 'alot-ffmpeg');
  const destBin = path.join(destDir, path.basename(ffmpegPath));
  try {
    if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
    if (!fs.existsSync(destBin) || fs.statSync(destBin).size !== fs.statSync(ffmpegPath).size) {
      fs.copyFileSync(ffmpegPath, destBin);
    }
    return destDir;
  } catch (e) {
    console.warn(`⚠️ [YouTube] Cannot stage ffmpeg without spaces: ${e.message}`);
    return path.dirname(ffmpegPath);
  }
}

class YoutubeService {
  constructor() {
    this.publicDir = path.join(__dirname, '../public/audio');
    if (!fs.existsSync(this.publicDir)) {
      fs.mkdirSync(this.publicDir, { recursive: true });
    }
  }

  normalizeYoutubeUrl(raw) {
    const input = String(raw || '').trim();
    if (!input) return '';
    try {
      const u = new URL(input);
      if (u.hostname.includes('youtu.be')) {
        const id = u.pathname.replace('/', '');
        return id ? `https://www.youtube.com/watch?v=${id}` : input;
      }
      if (u.hostname.includes('youtube.com')) {
        const id = u.searchParams.get('v');
        if (id) return `https://www.youtube.com/watch?v=${id}`;
      }
      return input;
    } catch (_) {
      return input;
    }
  }

  _downloadToFile(url, destPath) {
    return new Promise((resolve, reject) => {
      const client = url.startsWith('https') ? https : http;
      const file = fs.createWriteStream(destPath);
      const req = client.get(url, {
        headers: { 'User-Agent': 'Mozilla/5.0 AloT-Classroom/1.0' }
      }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          file.close();
          fs.unlink(destPath, () => {});
          return this._downloadToFile(res.headers.location, destPath).then(resolve).catch(reject);
        }
        if (res.statusCode !== 200) {
          file.close();
          fs.unlink(destPath, () => {});
          return reject(new Error(`Download status ${res.statusCode}`));
        }
        res.pipe(file);
        file.on('finish', () => {
          file.close();
          resolve(destPath);
        });
      });
      req.on('error', (err) => {
        file.close();
        fs.unlink(destPath, () => {});
        reject(err);
      });
    });
  }

  _ensureMp3Ready(destPath) {
    if (fs.existsSync(destPath)) return destPath;
    const alt = destPath.replace(/\.mp3$/i, '') + '.mp3';
    if (fs.existsSync(alt)) {
      if (alt !== destPath) fs.renameSync(alt, destPath);
      return destPath;
    }
    return null;
  }

  async _downloadViaTool(runDownload, destPath) {
    const tmpDir = safeTempDir();
    const tmpName = `alot_yt_${Date.now()}.mp3`;
    const tmpPath = path.join(tmpDir, tmpName);
    try {
      await runDownload(tmpPath);
      if (!this._ensureMp3Ready(tmpPath)) {
        throw new Error('Không tạo được file mp3 (thiếu ffmpeg?)');
      }
      fs.copyFileSync(tmpPath, destPath);
      return destPath;
    } finally {
      try { if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath); } catch (_) {}
    }
  }

  async _viaYoutubeDlExec(youtubeUrl, destPath) {
    if (!youtubeDlExec) throw new Error('youtube-dl-exec chưa được cài (npm install youtube-dl-exec)');

    return this._downloadViaTool(async (tmpPath) => {
      const outTemplate = tmpPath.replace(/\.mp3$/i, '.%(ext)s');
      const flags = {
        extractAudio: true,
        audioFormat: 'mp3',
        audioQuality: '5',
        noPlaylist: true,
        output: outTemplate,
        noCheckCertificates: true,
        noWarnings: true,
        preferFreeFormats: true,
      };
      if (ffmpegPath) {
        const ffDir = resolveFfmpegDir();
        if (ffDir) flags.ffmpegLocation = ffDir;
      }
      await youtubeDlExec(youtubeUrl, flags);
    }, destPath);
  }

  async _viaYtDlp(youtubeUrl, destPath) {
    return this._downloadViaTool(async (tmpPath) => {
      const args = [
        '-m', 'yt_dlp',
        '-x',
        '--audio-format', 'mp3',
        '--audio-quality', '5',
        '--no-playlist',
        '-o', tmpPath.replace(/\.mp3$/i, '.%(ext)s'),
        youtubeUrl
      ];
      if (ffmpegPath) {
        const ffDir = resolveFfmpegDir();
        if (ffDir) args.splice(args.length - 1, 0, '--ffmpeg-location', ffDir);
      }

      const pyCandidates = [
        process.env.PYTHON_PATH,
        'C:\\esptools\\python_env\\idf5.5_py3.13_env\\Scripts\\python.exe',
        'python',
        'py'
      ].filter(Boolean);

      let lastErr = null;
      for (const py of pyCandidates) {
        try {
          await new Promise((resolve, reject) => {
            const child = spawn(py, args, {
              windowsHide: true,
              stdio: ['ignore', 'pipe', 'pipe']
            });
            let stderr = '';
            child.stderr.on('data', (d) => { stderr += d.toString(); });
            child.on('error', reject);
            child.on('close', (code) => {
              if (this._ensureMp3Ready(tmpPath)) return resolve();
              reject(new Error(stderr.slice(-800) || `yt_dlp exit ${code}`));
            });
          });
          return;
        } catch (e) {
          lastErr = e;
        }
      }
      throw lastErr || new Error('yt_dlp failed');
    }, destPath);
  }

  async _viaCobalt(youtubeUrl, destPath) {
    // Public cobalt instances change often; keep as optional fallback.
    const endpoints = [
      'https://api.cobalt.tools/',
      'https://cobalt-api.hyper.lol/'
    ];
    let lastErr = null;
    for (const endpoint of endpoints) {
      try {
        const body = JSON.stringify({
          url: youtubeUrl,
          downloadMode: 'audio',
          audioFormat: 'mp3',
          filenameStyle: 'basic'
        });
        const data = await new Promise((resolve, reject) => {
          const u = new URL(endpoint);
          const req = https.request({
            hostname: u.hostname,
            path: u.pathname,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Mozilla/5.0 AloT-Classroom/1.0'
            }
          }, (res) => {
            let raw = '';
            res.on('data', (c) => { raw += c; });
            res.on('end', () => {
              try { resolve(JSON.parse(raw)); }
              catch (e) { reject(new Error(`Cobalt bad JSON: ${raw.slice(0, 200)}`)); }
            });
          });
          req.on('error', reject);
          req.write(body);
          req.end();
        });

        const audioUrl = data.url || data.tunnel || (data.data && data.data.url);
        if (!audioUrl) {
          lastErr = new Error(`Cobalt no url: ${JSON.stringify(data).slice(0, 300)}`);
          continue;
        }
        await this._downloadToFile(audioUrl, destPath);
        return destPath;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr || new Error('Cobalt failed');
  }

  /**
   * Download YouTube audio as MP3 into public/audio and return filename.
   */
  async downloadAsMp3(youtubeUrl, preferredFilename) {
    const url = this.normalizeYoutubeUrl(youtubeUrl);
    if (!url) throw new Error('YouTube URL trống');

    let filename = preferredFilename || `yt_${Date.now()}.mp3`;
    if (!filename.endsWith('.mp3')) filename += '.mp3';
    filename = filename.replace(/[^a-zA-Z0-9._-]/g, '_');
    const destPath = path.join(this.publicDir, filename);

    console.log(`🎬 [YouTube] Fetching audio: ${url} -> ${filename}`);
    console.log(`🎬 [YouTube] ffmpeg: ${ffmpegPath || 'NOT FOUND'} | youtube-dl-exec: ${youtubeDlExec ? 'ok' : 'missing'}`);

    const errors = [];

    try {
      await this._viaYoutubeDlExec(url, destPath);
    } catch (e1) {
      errors.push(`youtube-dl-exec: ${e1.message}`);
      console.warn(`⚠️ [YouTube] youtube-dl-exec failed: ${e1.message}`);
      try {
        await this._viaYtDlp(url, destPath);
      } catch (e2) {
        errors.push(`yt_dlp: ${e2.message}`);
        console.warn(`⚠️ [YouTube] yt_dlp failed: ${e2.message}`);
        try {
          await this._viaCobalt(url, destPath);
        } catch (e3) {
          errors.push(`cobalt: ${e3.message}`);
          console.error(`❌ [YouTube] cobalt failed: ${e3.message}`);
          throw new Error(
            `Không tải được audio YouTube. Chi tiết: ${errors.join(' | ')}`
          );
        }
      }
    }

    if (!fs.existsSync(destPath) || fs.statSync(destPath).size < 1000) {
      throw new Error('File audio YouTube rỗng hoặc quá nhỏ');
    }

    console.log(`✅ [YouTube] Saved ${filename} (${fs.statSync(destPath).size} bytes)`);
    return filename;
  }
}

module.exports = new YoutubeService();
