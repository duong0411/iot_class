# 🌐 Hướng dẫn Setup Cloudflare — AloT MQTT + Backend API

## Sơ đồ luồng dữ liệu

```
                    ┌─────────────────────────────────────────────┐
                    │           CLOUDFLARE (lo TLS/SSL)           │
ESP32               │                                             │
wsClient.beginSSL() │  WSS:443        ┌─────────────────────┐     │
mqtt.duynguyen.io.vn│──────────────►  │  Cloudflare Proxy   │     │
port 443 /mqtt      │                 │  (decrypt TLS)      │     │
                    │                 └──────────┬──────────┘     │
Mobile App          │                            │ plain WS        │
(MQTT over WSS)     │                            ▼                 │
                    │                 ┌──────────────────────┐     │
                    │                 │  Cloudflare Tunnel   │     │
                    │                 │  → localhost:443     │     │
                    │                 └──────────┬───────────┘     │
                    └────────────────────────────┼─────────────────┘
                                                 │ plain ws://
                                                 ▼
                                    ┌────────────────────────┐
                                    │  Mosquitto Broker      │
                                    │  port 443 (WebSocket)  │
                                    │  port 1883 (TCP)       │
                                    └────────────┬───────────┘
                                                 │ mqtt://localhost:1883
                                                 ▼
                                    ┌────────────────────────┐
                                    │  Backend Node.js       │
                                    │  (nội bộ, không TLS)   │
                                    └────────────────────────┘
```

> **Kết quả:** ESP32 gửi `beginSSL` lên `mqtt.duynguyen.io.vn:443`.

---

## Bước 1: Cài cloudflared

### Windows
```powershell
winget install --id Cloudflare.cloudflared
```

### Linux/VPS (Ubuntu/Debian)
```bash
curl -L --output cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
```

---

## Bước 2: Đăng nhập Cloudflare

```bash
cloudflared tunnel login
# → Mở trình duyệt, chọn duynguyen.io.vn → Authorize
```

---

## Bước 3: Tạo Tunnel

```bash
cloudflared tunnel create alot-mqtt-tunnel
# Lưu lại Tunnel ID xuất hiện!
```

---

## Bước 4: File cấu hình Tunnel

Tạo `~/.cloudflared/config.yml` (Linux) hoặc `%USERPROFILE%\.cloudflared\config.yml` (Windows):

```yaml
tunnel: alot-mqtt-tunnel
credentials-file: C:\Users\<username>\.cloudflared\<TUNNEL_ID>.json

ingress:
  # MQTT WebSocket — Cloudflare nhận WSS từ ESP32, forward plain WS về Mosquitto
  - hostname: mqtt.duynguyen.io.vn
    service: ws://localhost:443

  # Backend API + Opus WebSocket (tuỳ chọn)
  - hostname: api.duynguyen.io.vn
    service: http://localhost:3001

  # Catch-all bắt buộc
  - service: http_status:404
```

---

## Bước 5: Thêm DNS CNAME trong Cloudflare Dashboard

```bash
cloudflared tunnel route dns alot-mqtt-tunnel mqtt.duynguyen.io.vn
cloudflared tunnel route dns alot-mqtt-tunnel api.duynguyen.io.vn
```

Hoặc thêm thủ công trong **Cloudflare Dashboard → DNS**:
| Type | Name | Target | Proxy |
|------|------|--------|-------|
| CNAME | `mqtt` | `<TUNNEL_ID>.cfargotunnel.com` | 🟠 Proxied |
| CNAME | `api` | `<TUNNEL_ID>.cfargotunnel.com` | 🟠 Proxied |

---

## Bước 6: Bật WebSockets trong Cloudflare

**Cloudflare Dashboard → duynguyen.io.vn → Network → WebSockets → ON** ✅

---

## Bước 7: Chạy Tunnel

```bash
# Test thử
cloudflared tunnel run alot-mqtt-tunnel

# Cài service vĩnh viễn (Windows)
cloudflared service install
cloudflared service start

# Cài service vĩnh viễn (Linux)
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

---

## ✅ Kiểm tra kết nối

```bash
# Test MQTT từ máy tính (dùng MQTTX hoặc mqtt-cli)
# Kết nối WSS (y hệt ESP32):
mqttx sub -h mqtt.duynguyen.io.vn -p 443 -t "tele/#" --protocol wss --path /mqtt

# Test backend API
curl https://api.duynguyen.io.vn/
```

---

## So sánh: Cũ vs Mới

| | **Tên miền cũ** | **mqtt.duynguyen.io.vn** |
|---|---|---|
| ESP32 code | `beginSSL(host, 443, "/mqtt")` | `beginSSL(host, 443, "/mqtt")` ✅ |
| Protocol ESP32→Cloud | WSS (port 443) | WSS (port 443) ✅ |
| TLS xử lý bởi | Broker bên ngoài | Cloudflare ✅ |
| Mosquitto nhận | — | plain WS localhost:443 |
| Backend kết nối | WSS qua internet | TCP localhost:1883 ⚡ |
| MQTT topics | Giống hệt | Giống hệt ✅ |
