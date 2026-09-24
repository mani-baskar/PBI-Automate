@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -File "%~dp0Start-PBIAutomate.ps1"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo PBI Automate could not start successfully.
    echo Review the error above. If your organization blocks unsigned PowerShell scripts,
    echo use your approved IT/signing process. This launcher does not bypass security policy.
    echo.
    pause
)

endlocal & exit /b %EXITCODE%
