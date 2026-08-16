@echo off
setlocal
title Nostalgia Webserver

set "WEBROOT=%~dp0Web"
set "HTTPD=%WEBROOT%\Apache\bin\httpd.exe"
set "CONFIG=%WEBROOT%\Apache\conf\httpd.conf"

if not exist "%HTTPD%" (
    echo Apache wurde nicht gefunden: %HTTPD%
    pause
    exit /b 1
)

"%HTTPD%" -t -f "%CONFIG%"
if errorlevel 1 (
    echo.
    echo Die Apache-Konfiguration ist ungueltig.
    pause
    exit /b 1
)

netstat -ano | findstr /r /c:":8080 .*LISTENING" >nul
if errorlevel 1 (
    start "Nostalgia Webserver" /min "%HTTPD%" -f "%CONFIG%"
    timeout /t 2 >nul
)

start "" "http://127.0.0.1:8080/"
endlocal
