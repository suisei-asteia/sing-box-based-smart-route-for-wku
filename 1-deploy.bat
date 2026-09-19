@echo off
title Deploy sing-box smart routing
echo ==========================================
echo   1. Deploy sing-box smart routing
echo ==========================================
echo.
echo Running deploy.ps1 ...
echo (A UAC prompt will appear, click Yes)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
echo.
echo ==========================================
echo Done. If you saw errors above, screenshot them.
echo ==========================================
pause
