@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "RUN_DIR=%TEMP%\zephyr_accelerator_top_feature_ooc_%RANDOM%_%RANDOM%"
set "RUN_TCL=%SOURCE_RTL%\scripts\synth_accelerator_top_feature_ooc.tcl"
set "REPORT_DIR=%SOURCE_RTL%\reports\accelerator_top_sparse_timing"
set "METRICS=%REPORT_DIR%\metrics_post_synth.txt"
set "DCP=%SOURCE_RTL%\build\synth\accelerator_top_feature\accelerator_top_feature_post_synth.dcp"

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

if exist "%METRICS%" del /q "%METRICS%"
if exist "%DCP%" del /q "%DCP%"

call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log vivado-accelerator-top-feature.log ^
  -source "%RUN_TCL%" -tclargs "%SOURCE_RTL%"
set "STATUS=%ERRORLEVEL%"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
if exist vivado-accelerator-top-feature.log copy /y ^
  vivado-accelerator-top-feature.log ^
  "%REPORT_DIR%\vivado-accelerator-top-feature.log" >nul
if "%STATUS%"=="0" findstr /b /c:"ACCELERATOR_TOP_FEATURE_OOC_METRIC wns_ns=" vivado-accelerator-top-feature.log >nul
if errorlevel 1 set "STATUS=1"
if "%STATUS%"=="0" findstr /c:"has been generated." vivado-accelerator-top-feature.log >nul
if errorlevel 1 set "STATUS=1"

if "%STATUS%"=="0" (
  findstr /b /x /c:"ACCELERATOR_TOP_FEATURE_SYNTH_TIMING_PASS" vivado-accelerator-top-feature.log >nul
  if errorlevel 1 (
    echo ACCELERATOR_TOP_FEATURE_OOC_READY_FOR_ROUTE_TIMING_PENDING
  ) else (
    echo ACCELERATOR_TOP_FEATURE_OOC_SYNTH_TIMING_PASS
  )
) else (
  echo ACCELERATOR_TOP_FEATURE_OOC_FAIL
)
echo ACCELERATOR_TOP_FEATURE_OOC_RUN_DIR=%RUN_DIR%
popd
exit /b %STATUS%
