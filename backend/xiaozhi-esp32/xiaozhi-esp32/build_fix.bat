@echo off
setlocal
set IDF_PATH=C:\esp-idf
set IDF_PYTHON_ENV_PATH=C:\Users\Duong Phung\.espressif\python_env\idf5.5_py3.13_env

call C:\esp-idf\export.bat
if errorlevel 1 (
  echo EXPORT_FAILED
  exit /b 1
)

cd /d "C:\Users\Duong Phung\Downloads\AloT\backend\xiaozhi-esp32\xiaozhi-esp32"
idf.py build
set BUILD_RC=%ERRORLEVEL%
echo BUILD_EXIT=%BUILD_RC%
exit /b %BUILD_RC%
