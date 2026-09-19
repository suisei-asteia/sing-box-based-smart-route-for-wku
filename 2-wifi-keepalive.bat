@echo off
title Install WiFi keepalive
echo ==========================================
echo   2. Install WiFi keepalive
echo ==========================================
echo.
echo Running wifi-keepalive.ps1 install ...
echo (A UAC prompt will appear, click Yes)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wifi-keepalive.ps1" install
echo.
echo ==========================================
echo Done. If you saw errors above, screenshot them.
echo ==========================================
pause
