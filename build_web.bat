@echo off
echo ==========================================
echo      BaltoPro - Web Build Tool
echo ==========================================
echo Building Web App...
call flutter build web --release
echo.
echo [SUCCESS] Build completed!
pause
