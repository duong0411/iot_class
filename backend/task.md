# Task: MQTT Local Broker + Cloudflare Tunnel Setup

- [x] Đọc code ESP32 và backend hiện tại
- [ ] Tạo `mqtt/mosquitto.conf` — plain WS port 443 + TCP 1883
- [ ] Tạo `docker-compose.yml` — chạy Mosquitto
- [ ] Tạo `cloudflare/SETUP.md` — hướng dẫn tunnel
- [ ] Cập nhật `backend/.env` — đổi MQTT_URL
- [ ] Cập nhật `backend/services/mqtt.service.js` — connect localhost
- [ ] Cập nhật `esp32.ino` — đổi host + beginSSL → begin
- [ ] Tạo `start.ps1` — script khởi động tổng hợp
