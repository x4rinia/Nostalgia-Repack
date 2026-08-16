@echo off
setlocal
cd /d "%~dp0"
title Nostalgia Vanilla Server
color 0A

echo.
echo =========================================
echo             NOSTALGIA VANILLA
echo        Dein Classic WoW Server
echo =========================================
echo.

echo [1/4] MariaDB...
call :port_in_use 3307
if errorlevel 1 (
    start "Nostalgia MariaDB" /D "MariaDB" cmd /c "dbstart.bat"
    timeout /t 5 >nul
) else (
    echo       Laeuft bereits auf Port 3307.
)

echo       Setze Gurubashi-Arena auf volle Serverstunden...
"%~dp0MariaDB\bin\mysql.exe" --protocol=tcp -h 127.0.0.1 -P 3307 -u vmangos --password=vmangos -D vmangos < "%~dp0database\custom\nostalgia_gurubashi_hourly.sql"
if errorlevel 1 echo       Hinweis: Gurubashi-Zeitplanung konnte nicht gesetzt werden.

echo [2/4] Loginserver...
call :port_in_use 3724
if errorlevel 1 (
    start "Nostalgia Loginserver" /D "Server" realmd.exe
    timeout /t 3 >nul
) else (
    echo       Laeuft bereits auf Port 3724.
)

echo [3/4] Worldserver...
call :port_in_use 8085
if errorlevel 1 (
    start "Nostalgia Worldserver" /D "Server" mangosd.exe
) else (
    echo       Laeuft bereits auf Port 8085.
)

echo [4/4] Lokale Nostalgia-Webseite...
call "%~dp0web.bat"

echo.
echo =========================================
echo Nostalgia ist bereit.
echo.
echo MariaDB     : Port 3307
echo Loginserver : Port 3724
echo Worldserver : Port 8085
echo Webseite    : http://127.0.0.1:8080/
echo =========================================
echo.
pause
endlocal
exit /b 0

:port_in_use
netstat -ano | findstr /r /c:":%~1 .*LISTENING" >nul
exit /b %errorlevel%
