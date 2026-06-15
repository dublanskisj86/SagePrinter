@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%SageLabelPrinter.ps1"

if errorlevel 1 (
    echo.
    echo Sage Label Printer stopped with an error.
    pause
)
