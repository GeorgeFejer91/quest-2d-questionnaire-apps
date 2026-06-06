@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start-questionnaire-builder-app.ps1" -Mode OnlineConnector
pause
