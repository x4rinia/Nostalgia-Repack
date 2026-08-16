@echo off
setlocal
title Nostalgia stoppen
color 0C

echo.
echo Beende Nostalgia-Dienste...

taskkill /F /IM mangosd.exe >nul 2>&1
taskkill /F /IM realmd.exe >nul 2>&1
taskkill /F /IM mariadbd.exe >nul 2>&1

rem Only stop Apache that belongs to this Nostalgia repack.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Web\Stop-NostalgiaWeb.ps1"

echo.
echo MariaDB, Loginserver und Worldserver wurden beendet.
pause
endlocal
