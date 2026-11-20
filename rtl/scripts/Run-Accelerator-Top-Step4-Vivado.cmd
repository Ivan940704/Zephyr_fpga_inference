@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "RUN_DIR=%TEMP%\zephyr_accelerator_top_step4_ooc_%RANDOM%_%RANDOM%"
set "RUN_TCL=%SOURCE_RTL%\scripts\synth_accelerator_top_step4_ooc.tcl"
set "REPORT_DIR=%SOURCE_RTL%\reports\accelerator_top_step4"

if not exist "%VIVADO_BIN%\vivado.bat" (
  echo Missing Vivado 2018.3 tool: %VIVADO_BIN%\vivado.bat
  exit /b 1
)
if not exist "%RUN_TCL%" (
  echo Missing accelerator-top Tcl: %RUN_TCL%
  exit /b 1
)

mkdir "%RUN_DIR%" 2>nul
if errorlevel 1 exit /b 1
pushd "%RUN_DIR%"
if errorlevel 1 exit /b 1

call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log vivado-accelerator-top-step4.log ^
  -source "%RUN_TCL%" -tclargs "%SOURCE_RTL%"
set "STATUS=%ERRORLEVEL%"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
if exist vivado-accelerator-top-step4.log copy /y ^
  vivado-accelerator-top-step4.log ^
  "%REPORT_DIR%\vivado-accelerator-top-step4.log" >nul
set "METRICS=%SOURCE_RTL%\reports\accelerator_top_step4\metrics_post_synth.txt"
if not exist "%METRICS%" set "STATUS=1"
if "%STATUS%"=="0" findstr /x /c:"timing_met=1" "%METRICS%" >nul
if errorlevel 1 set "STATUS=1"

if "%STATUS%"=="0" (
  echo ACCELERATOR_TOP_STEP4_OOC_PASS
) else (
  echo ACCELERATOR_TOP_STEP4_OOC_FAIL
)
echo ACCELERATOR_TOP_STEP4_OOC_RUN_DIR=%RUN_DIR%
popd
exit /b %STATUS%
