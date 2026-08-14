@echo off
chcp 65001 >nul
title AloT Smart Classroom — Khởi động hệ thống

echo.
echo ════════════════════════════════════════════════════
echo    AloT Smart Classroom — Startup Script
echo ════════════════════════════════════════════════════
echo.

set ROOT=%~dp0

:: ─── BƯỚC 1: Mosquitto MQTT Broker ───
echo [1/3] Khởi động Mosquitto MQTT Broker...

:: Tìm đường dẫn Mosquitto (mặc định cài ở Program Files)
set MOSQ_EXE=
if exist "C:\Program Files\mosquitto\mosquitto.exe" set MOSQ_EXE=C:\Program Files\mosquitto\mosquitto.exe
if exist "C:\Program Files (x86)\mosquitto\mosquitto.exe" set MOSQ_EXE=C:\Program Files (x86)\mosquitto\mosquitto.exe

if "%MOSQ_EXE%"=="" (
    echo     LOI: Khong tim thay mosquitto.exe!
    echo     Cai dat bang lenh: winget install EclipseFoundation.Mosquitto
    pause
    exit /b 1
)

:: Copy config vào thư mục Mosquitto
copy /Y "%ROOT%mqtt\mosquitto.conf" "C:\Program Files\mosquitto\mosquitto.conf" >nul 2>&1

:: Chạy Mosquitto ở cửa sổ mới
start "Mosquitto MQTT Broker" cmd /k ""%MOSQ_EXE%" -v -c "%ROOT%mqtt\mosquitto.conf""
echo     OK  Mosquitto dang chay:
echo          - TCP  MQTT : localhost:1883  (Backend noi bo)
echo          - WS   MQTT : 0.0.0.0:443    (ESP32 qua Cloudflare)
echo.

:: ─── BƯỚC 2: Backend Node.js ───
echo [2/3] Khởi động Backend Node.js...
start "AloT Backend" cmd /k "cd /d "%ROOT%backend" && node server.js"
echo     OK  Backend dang chay tai http://localhost:3001
echo.

:: ─── BƯỚC 3: Cloudflare Tunnel ───
echo [3/3] Khởi động Cloudflare Tunnel...
start "Cloudflare Tunnel" cmd /k "cloudflared tunnel run alot-mqtt-tunnel"
echo     OK  Cloudflare Tunnel dang chay!
echo          - MQTT  WSS : wss://mqtt.duynguyen.io.vn:443/mqtt
echo          - API  HTTPS: https://api.duynguyen.io.vn
echo.

echo ════════════════════════════════════════════════════
echo    Tat ca dich vu da khoi dong!
echo.
echo    ESP32 ket noi:
echo      Host : mqtt.duynguyen.io.vn
echo      Port : 443
echo      Path : /mqtt
echo ════════════════════════════════════════════════════
echo.
pause
