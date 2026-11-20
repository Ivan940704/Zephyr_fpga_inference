@echo off
setlocal EnableExtensions
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_cp7_registered_fault_xsim.ps1"
exit /b %ERRORLEVEL%
