const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const opusService = require('./opus.service');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

class WebSocketService {
  constructor() {
    this.wss = null;
    this.clients = new Set();
  }

  /**
   * Khởi tạo WebSocket Server gắn với Express HTTP Server
   */
  init(server) {
    this.wss = new WebSocket.Server({ server, path: '/ws' });

    console.log('📡 [WebSocket Server] Opus Audio Streamer tại path: /ws');

    this.wss.on('connection', (ws, req) => {
      const clientIp = req.socket.remoteAddress;
      console.log(`🔌 [WebSocket Server] Client kết nối: ${clientIp}`);
      this.clients.add(ws);

      ws.send(JSON.stringify({
        type: 'connection_ack',
        message: 'AloT Opus streamer ready',
        format: 'opus',
        sample_rate: opusService.sampleRate,
        frame_duration: opusService.frameDurationMs,
        timestamp: Date.now()
      }));

      ws.on('message', async (data) => {
        try {
          const messageStr = data.toString();
          let parsed;
          try { parsed = JSON.parse(messageStr); } catch (_) { return; }

          if (parsed.type === 'ping') {
            ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
            return;
          }

          if (parsed.method === 'initialize') {
            ws.send(JSON.stringify({
              jsonrpc: '2.0',
              id: parsed.id,
              result: {
                protocolVersion: '2024-11-05',
                capabilities: { tools: {} },
                serverInfo: { name: 'AloT Smart Classroom Server', version: '2.1.0' }
              }
            }));
            return;
          }

          // ESP32 yêu cầu stream Opus từ URL/file MP3 (giống cloud TTS)
          if (parsed.type === 'opus_play' || parsed.type === 'play_opus') {
            const audioUrl = parsed.audio_url || parsed.url || parsed.audioUrl || '';
            const filename = parsed.filename
              || opusService.filenameFromAudioUrl(audioUrl);
            const prompt = parsed.prompt || parsed.text || '';
            console.log(`🎬 [WS] opus_play from ${clientIp}: ${filename || audioUrl}`);
            try {
              await this.streamOpusToClient(ws, filename, prompt);
            } catch (e) {
              console.error('❌ [WS] opus_play failed:', e.message);
              if (ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({ type: 'tts', state: 'stop', error: e.message }));
              }
            }
          }
        } catch (err) {
          console.error('❌ Lỗi xử lý WebSocket message:', err.message);
        }
      });

      ws.on('close', () => {
        console.log(`❌ [WebSocket Server] Client ngắt: ${clientIp}`);
        this.clients.delete(ws);
      });

      ws.on('error', (err) => {
        console.error(`⚠️ [WebSocket Error] ${clientIp}:`, err.message);
        this.clients.delete(ws);
      });
    });
  }

  /**
   * Stream Opus packets to one client — cloud-compatible tts start/stop + raw Opus binary.
   */
  async streamOpusToClient(ws, mp3Filename, promptText = '') {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    if (!mp3Filename) throw new Error('Thiếu filename MP3');

    const { packets, sampleRate, frameDurationMs, oggName } =
      await opusService.getOpusPacketsForMp3(mp3Filename);

    console.log(`📢 [Opus WS] Streaming ${packets.length} frames (${oggName}) → client`);

    // Match Xiaozhi cloud JSON control plane
    ws.send(JSON.stringify({
      type: 'tts',
      state: 'start',
      prompt: promptText || undefined,
      sample_rate: sampleRate,
      frame_duration: frameDurationMs,
      format: 'opus',
      frames: packets.length
    }));

    // Pace slightly under frame duration so decode queue stays ~full (like cloud).
    const paceMs = Math.max(20, frameDurationMs - 8);
    for (let i = 0; i < packets.length; i++) {
      if (ws.readyState !== WebSocket.OPEN) break;
      ws.send(packets[i], { binary: true });
      await sleep(paceMs);
    }

    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'tts', state: 'stop' }));
    }
    console.log(`✅ [Opus WS] Done ${oggName}`);
  }

  /**
   * Broadcast TTS + Opus stream tới mọi ESP32 đang kết nối /ws
   */
  async streamTtsToEsp32(promptText, audioUrl, filename = null) {
    if (!promptText && !filename && !audioUrl) return;

    console.log(`📢 [WebSocket Opus] Broadcast tới ${this.clients.size} clients: "${promptText || filename}"`);

    const mp3Name = filename || opusService.filenameFromAudioUrl(audioUrl);
    const openClients = [...this.clients].filter((c) => c.readyState === WebSocket.OPEN);

    // JSON notify (legacy + cloud-style)
    const jsonPayload = JSON.stringify({
      type: 'tts_play',
      prompt: promptText,
      text: promptText,
      audio_url: audioUrl,
      timestamp: Date.now()
    });

    for (const client of openClients) {
      try {
        client.send(jsonPayload);
      } catch (_) {}
    }

    if (!mp3Name || openClients.length === 0) return;

    // Ensure Ogg exists even if no client (for HTTP .ogg fallback on device)
    try {
      await opusService.ensureOggFromMp3(mp3Name);
    } catch (e) {
      console.warn(`⚠️ [Opus] ensureOgg failed: ${e.message}`);
    }

    await Promise.all(openClients.map(async (client) => {
      try {
        await this.streamOpusToClient(client, mp3Name, promptText || '');
      } catch (e) {
        console.error('❌ [Opus broadcast] client failed:', e.message);
      }
    }));
  }
}

module.exports = new WebSocketService();
