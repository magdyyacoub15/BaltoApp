@echo off
echo ==========================================
echo      BaltoPro - Sync Push Tool
echo ==========================================
echo 1. Adding changes...
git add .
echo.
set /p msg="Enter commit message (or press Enter for 'Updates'): "
if "%msg%"=="" set msg=Updates
echo.
echo 2. Committing changes: %msg%
git commit -m "%msg%"
echo.
echo 3. Pushing to GitHub...
git push origin main
echo.
echo ==========================================
echo [SUCCESS] Changes uploaded successfully!
echo ==========================================
pause
