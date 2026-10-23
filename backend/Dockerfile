# Smart Classroom backend — API + Opus /ws stream + TTS (không đụng alot-backend nhà)
FROM node:22-bookworm-slim

WORKDIR /usr/src/app

ENV NODE_ENV=production

# yt-dlp / một số tool cần python; ffmpeg-static đã kèm trong npm
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

RUN mkdir -p public/audio

# 3001: HTTP (/api/schedule, /api/tts, /audio) + WebSocket Opus (/ws)
EXPOSE 3001

CMD ["node", "server.js"]
