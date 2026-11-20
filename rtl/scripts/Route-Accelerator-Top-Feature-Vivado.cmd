@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO=C:\Xilinx\Vivado\2018.3\bin\vivado.bat"
set "RUN_DIR=%TEMP%\zephyr_accelerator_top_route_%RANDOM%_%RANDOM%"
set "REPORT_DIR=%SOURCE_RTL%\reports\accelerator_top_sparse_timing"

if not exist "%VIVADO%" exit /b 1
if not exist "%SOURCE_RTL%\build\synth\accelerator_top_feature\accelerator_top_feature_post_synth.dcp" (
  echo Missing matching accelerator-top post-synthesis checkpoint.
  exit /b 1
)
mkdir "%RUN_DIR%" 2>nul
if errorlevel 1 exit /b 1
pushd "%RUN_DIR%"
if errorlevel 1 exit /b 1

call "%VIVADO%" -mode batch -nojournal -nolog ^
  -source "%SOURCE_RTL%\scripts\route_accelerator_top_feature_ooc.tcl" ^
  -tclargs "%SOURCE_RTL%" > vivado-accelerator-top-route.log 2>&1
set "FAILED=%ERRORLEVEL%"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
copy /y vivado-accelerator-top-route.log ^
  "%REPORT_DIR%\vivado-accelerator-top-route.log" >nul

if "%FAILED%"=="0" findstr /b /x /c:"ACCELERATOR_TOP_ROUTE_PASS" vivado-accelerator-top-route.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" (
  echo ACCELERATOR_TOP_ROUTE_PASS
) else (
  echo ACCELERATOR_TOP_ROUTE_FAIL
  type vivado-accelerator-top-route.log
)

echo ACCELERATOR_TOP_ROUTE_RUN_DIR=%RUN_DIR%
popd
exit /b %FAILED%
