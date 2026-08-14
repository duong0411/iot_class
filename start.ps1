# ╔══════════════════════════════════════════════════════════╗
# ║   AloT Smart Classroom — Khởi động toàn bộ hệ thống    ║
# ║   1. Mosquitto MQTT Broker (Docker)                     ║
# ║   2. Backend Node.js                                    ║
# ║   3. Cloudflare Tunnel (nếu cloudflared đã cài)        ║
# ╚══════════════════════════════════════════════════════════╝

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "🚀 ═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   AloT Smart Classroom Backend — Khởi động"      -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─── 1. Mosquitto MQTT Broker ───
Write-Host "📦 [1/3] Khởi động Mosquitto MQTT Broker..." -ForegroundColor Yellow
$mqttDir = Join-Path $ROOT "mqtt"
if (Test-Path (Join-Path $mqttDir "docker-compose.yml")) {
    Push-Location $mqttDir
    docker compose up -d
    Pop-Location
    Write-Host "  ✅ Mosquitto đang chạy:" -ForegroundColor Green
    Write-Host "     • TCP  MQTT : localhost:1883  (dùng cho Backend nội bộ)" -ForegroundColor Gray
    Write-Host "     • WS   MQTT : localhost:443   (dùng cho ESP32 plain WS)" -ForegroundColor Gray
} else {
    Write-Host "  ⚠️  Không tìm thấy mqtt/docker-compose.yml! Kiểm tra thư mục." -ForegroundColor Red
}

Write-Host ""

# ─── 2. Backend Node.js ───
Write-Host "🖥️  [2/3] Khởi động Backend Node.js..." -ForegroundColor Yellow
$backendDir = Join-Path $ROOT "backend"
if (Test-Path (Join-Path $backendDir "server.js")) {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$backendDir'; npm start" -WindowStyle Normal
    Write-Host "  ✅ Backend Node.js đang chạy tại http://localhost:3001" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Không tìm thấy backend/server.js!" -ForegroundColor Red
}

Write-Host ""

# ─── 3. Cloudflare Tunnel ───
Write-Host "🌐 [3/3] Khởi động Cloudflare Tunnel..." -ForegroundColor Yellow
$cfInstalled = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cfInstalled) {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cloudflared tunnel run alot-mqtt-tunnel" -WindowStyle Normal
    Write-Host "  ✅ Cloudflare Tunnel đang chạy!" -ForegroundColor Green
    Write-Host "     • MQTT  WSS : wss://mqtt.duynguyen.io.vn:443/mqtt" -ForegroundColor Gray
    Write-Host "     • API   HTTPS: https://api.duynguyen.io.vn" -ForegroundColor Gray
} else {
    Write-Host "  ⚠️  cloudflared chưa được cài đặt!" -ForegroundColor Red
    Write-Host "     Chạy: winget install --id Cloudflare.cloudflared" -ForegroundColor Yellow
    Write-Host "     Sau đó xem hướng dẫn: cloudflare\SETUP.md" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "═════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ Hệ thống đã khởi động!" -ForegroundColor Green
Write-Host ""
Write-Host "📌 Thông tin kết nối ESP32:" -ForegroundColor White
Write-Host "   MQTT_HOST : mqtt.duynguyen.io.vn" -ForegroundColor Cyan
Write-Host "   MQTT_PORT : 443" -ForegroundColor Cyan
Write-Host "   Protocol  : plain WebSocket (ws://, không SSL)" -ForegroundColor Cyan
Write-Host "   Path      : /mqtt" -ForegroundColor Cyan
Write-Host ""
Write-Host "📌 Dừng Mosquitto: cd mqtt && docker compose down" -ForegroundColor Gray
Write-Host "═════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
