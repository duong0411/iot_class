# Docker — Backend Lớp học thông minh

Stack **nhà** (`alot-backend` port 3000) giữ nguyên. File này chỉ chạy **classroom-backend** port **3001**.

## Domain + path (không đổi subdomain)

Public: `https://duynguyen.io.vn` / `wss://...`

| Path | Container | Ghi chú |
|------|-----------|---------|
| `/api/schedule`, `/api/tts`, `/audio`, `/ws` | `classroom-backend:3001` | App lớp học + Opus stream |
| `/api/*` còn lại, `/mqtt` | `alot-backend:3000` | Nhà — không sửa |
| `mqtt.duynguyen.io.vn/mqtt` | Mosquitto host | Dùng chung cả 2 |

App Flutter lớp học **không cần sửa** — đang gọi đúng các path trên.

## Chạy

```bash
cd iot_class
# Tạo backend/.env từ .env.example (điền XIAOZHI_MCP_URL agent lớp học)
docker compose up -d --build
docker compose logs -f classroom-backend
```

Kiểm tra local:

```bash
curl http://localhost:3001/api/schedule
```

## Tunnel Cloudflare

Cập nhật `%USERPROFILE%\.cloudflared\config.yml` theo `cloudflare/SETUP.md` (mục path routing), rồi restart `cloudflared`.
