@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO=C:\Xilinx\Vivado\2018.3\bin\vivado.bat"
set "RUN_DIR=%TEMP%\zephyr_deepfilter_engine_ooc_%RANDOM%_%RANDOM%"
set "REPORT_DIR=%SOURCE_RTL%\reports\deepfilter_engine"

if not exist "%VIVADO%" exit /b 1
mkdir "%RUN_DIR%" 2>nul
if errorlevel 1 exit /b 1
pushd "%RUN_DIR%"
if errorlevel 1 exit /b 1

call "%VIVADO%" -mode batch -nojournal -nolog ^
  -source "%SOURCE_RTL%\scripts\synth_deepfilter_engine_ooc.tcl" ^
  -tclargs "%SOURCE_RTL%" > vivado-deepfilter-engine.log 2>&1
set "FAILED=%ERRORLEVEL%"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
copy /y vivado-deepfilter-engine.log ^
  "%REPORT_DIR%\vivado-deepfilter-engine.log" >nul

if "%FAILED%"=="0" (
  echo DEEPFILTER_ENGINE_OOC_PASS
) else (
  echo DEEPFILTER_ENGINE_OOC_FAIL
  type vivado-deepfilter-engine.log
)

echo DEEPFILTER_ENGINE_OOC_RUN_DIR=%RUN_DIR%
popd
exit /b %FAILED%
