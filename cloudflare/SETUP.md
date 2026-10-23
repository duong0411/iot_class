# Cloudflare — 1 domain + path (nhà giữ nguyên, lớp học path riêng)

## Sơ đồ

```
Internet :443
  │
  ├─ mqtt.duynguyen.io.vn/mqtt  →  Mosquitto (host :443 WS / :1883 TCP)
  │
  └─ duynguyen.io.vn
        ├─ /api/schedule*  ─┐
        ├─ /api/tts*       ─┼→  classroom-backend :3001  (Docker lớp học + Opus /ws)
        ├─ /audio*         ─┤
        ├─ /ws*            ─┘
        └─ /* (còn lại)    →  alot-backend :3000         (Docker nhà — KHÔNG SỬA)
```

App Flutter lớp học đã gọi đúng các path trên → **không cần rebuild app**.

---

## Bước 1–3: cloudflared / login / tạo tunnel

Giữ như trước (`alot-mqtt-tunnel`).

---

## Bước 4: `%USERPROFILE%\.cloudflared\config.yml`

```yaml
tunnel: alot-mqtt-tunnel
credentials-file: C:\Users\<username>\.cloudflared\<TUNNEL_ID>.json

ingress:
  # MQTT WSS (ESP32 + app) — dùng chung nhà & lớp
  - hostname: mqtt.duynguyen.io.vn
    service: ws://localhost:443

  # Lớp học — classroom-backend :3001 (đặt TRƯỚC rule nhà)
  - hostname: duynguyen.io.vn
    path: /api/schedule*
    service: http://localhost:3001
  - hostname: duynguyen.io.vn
    path: /api/tts*
    service: http://localhost:3001
  - hostname: duynguyen.io.vn
    path: /audio*
    service: http://localhost:3001
  - hostname: duynguyen.io.vn
    path: /ws*
    service: http://localhost:3001

  # Nhà thông minh — alot-backend :3000 (giữ nguyên)
  - hostname: duynguyen.io.vn
    service: http://localhost:3000

  - service: http_status:404
```

Restart tunnel sau khi sửa:

```powershell
cloudflared tunnel run alot-mqtt-tunnel
# hoặc restart Windows service cloudflared
```

---

## Bước 5: DNS

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| CNAME | `mqtt` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |
| CNAME | `@` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |

**Network → WebSockets → ON**

---

## Kiểm tra

```bash
# Nhà (không đổi)
curl -I https://duynguyen.io.vn/api/auth/profile

# Lớp học
curl https://duynguyen.io.vn/api/schedule
curl -I https://duynguyen.io.vn/audio/

# MQTT
mqttx sub -h mqtt.duynguyen.io.vn -p 443 -t "tele/#" --protocol wss --path /mqtt
```

---

## Docker lớp học

Xem `DOCKER.md` — chỉ chạy `classroom-backend` port 3001, không đụng `alot-backend`.
