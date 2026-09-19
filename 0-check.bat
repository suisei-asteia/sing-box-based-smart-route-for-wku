@echo off
title Check sing-box deploy environment
echo ==========================================
echo   0. Check environment before deploy
echo ==========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check.ps1"
pause
