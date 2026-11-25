@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ==============================
echo   Windows Network Optimizer
echo ==============================
echo 1. Scan (quet mang)
echo 2. Optimize (toi uu)
echo 3. Optimize + Reset stack
echo 4. Speed test
echo 5. Update drivers
echo 6. Restore
echo 0. Thoat
echo.
set /p choice="Chon (0-6): "

if "%choice%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0netopt.ps1" -Scan
if "%choice%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0netopt.ps1" -Optimize
if "%choice%"=="3" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0netopt.ps1" -Optimize -ResetStack
if "%choice%"=="4" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0netopt.ps1" -SpeedTest
if "%choice%"=="5" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0netopt.ps1" -UpdateDrivers
if "%choice%"=="6" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0netopt.ps1" -Restore

echo.
pause
endlocal