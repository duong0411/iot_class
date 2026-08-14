@echo off
:: Chạy file này với quyền ADMIN (Right-click -> Run as administrator)
echo Dang cap nhat config Mosquitto...

(
echo listener 1883 127.0.0.1
echo protocol mqtt
echo allow_anonymous true
echo.
echo listener 9001 0.0.0.0
echo protocol websockets
echo allow_anonymous true
echo.
echo log_type all
echo log_dest stdout
echo.
echo persistence true
echo persistence_location C:\Program Files\mosquitto\data\
echo.
echo max_packet_size 65536
) > "C:\Program Files\mosquitto\mosquitto.conf"

echo OK - Config da ghi xong!
echo.
echo Dang restart Mosquitto service...
net stop mosquitto
timeout /t 2 /nobreak >nul
net start mosquitto
echo.
echo Kiem tra port 9001:
timeout /t 2 /nobreak >nul
netstat -ano | findstr "9001"
netstat -ano | findstr "1883"
echo.
echo Xong! Nhan phim bat ky de dong.
pause >nul
