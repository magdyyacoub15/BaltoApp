@echo off
echo ==========================================
echo      BaltoPro - GitHub Pages Deployment
echo ==========================================

echo 1. Building Web App...
echo (Using base-href /BaltoApp/ for GitHub Pages)
call flutter build web --release --base-href "/BaltoApp/"

if %errorlevel% neq 0 (
    echo [ERROR] Build failed!
    pause
    exit /b %errorlevel%
)

echo 2. Preparing Deployment Branch...
cd build\web

:: Initialize temporary git repo for deployment
git init
git checkout -b gh-pages
git add .
git commit -m "Deploy Web Update"
git remote add origin https://github.com/magdyyacoub15/BaltoApp.git

echo 3. Uploading to GitHub Pages...
git push -f origin gh-pages

cd ..\..

echo ==========================================
echo [SUCCESS] Site updated successfully!
echo Link: https://magdyyacoub15.github.io/BaltoApp/
echo.
echo NOTE: Ensure GitHub Pages is set to use 'gh-pages' branch in:
echo Settings -> Pages -> Build and deployment -> Branch
echo ==========================================
pause
