@echo off
title AloT - Mosquitto MQTT & Backend Node.js

echo ========================================================
echo    ALO-T: KHOI DONG MOSQUITTO MQTT & BACKEND NODE.JS
echo ========================================================
echo.

set ROOT=%~dp0

:: 1. TIM MOSQUITTO
set MOSQ_EXE=
if exist "C:\Program Files\mosquitto\mosquitto.exe" set MOSQ_EXE=C:\Program Files\mosquitto\mosquitto.exe
if exist "C:\Program Files (x86)\mosquitto\mosquitto.exe" set MOSQ_EXE=C:\Program Files (x86)\mosquitto\mosquitto.exe

if "%MOSQ_EXE%"=="" (
    echo [LOI] Khong tim thay mosquitto.exe tai C:\Program Files\mosquitto\
    echo Vui long kiem tra lai cai dat Mosquitto.
    pause
    exit /b 1
)

:: 2. KHOI DONG MOSQUITTO CHAY NEN
echo [1/2] Dang khoi chay Mosquitto MQTT Broker...
start /B "" "%MOSQ_EXE%" -v -c "%ROOT%mqtt\mosquitto.conf"

:: Cho 3 giay de Mosquitto bind port
timeout /t 3 /nobreak >nul

:: 3. KHOI DONG BACKEND NODE.JS
echo [2/2] Dang ket noi Backend Node.js...
echo ========================================================
echo.

cd /d "%ROOT%backend"
node server.js
