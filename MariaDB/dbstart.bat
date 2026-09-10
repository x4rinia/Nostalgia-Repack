@echo off
cd /d "%~dp0"

bin\mariadbd.exe --defaults-file=my.ini --console
pause