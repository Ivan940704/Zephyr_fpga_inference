@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "RUN_DIR=%TEMP%\zephyr_df_coefficient_store_ooc_%RANDOM%_%RANDOM%"
set "RUN_TCL=%SOURCE_RTL%\scripts\synth_df_coefficient_store_ooc.tcl"
set "REPORT_DIR=%SOURCE_RTL%\reports\df_coefficient_store"

if not exist "%VIVADO_BIN%\vivado.bat" (
  echo Missing Vivado 2018.3 tool: %VIVADO_BIN%\vivado.bat
  exit /b 1
)
if not exist "%RUN_TCL%" (
  echo Missing coefficient-store Tcl: %RUN_TCL%
  exit /b 1
)

mkdir "%RUN_DIR%" 2>nul
if errorlevel 1 exit /b 1
pushd "%RUN_DIR%"
if errorlevel 1 exit /b 1

call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log vivado-df-coefficient-store.log ^
  -source "%RUN_TCL%" -tclargs "%SOURCE_RTL%"
set "STATUS=%ERRORLEVEL%"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
if exist vivado-df-coefficient-store.log copy /y ^
  vivado-df-coefficient-store.log ^
  "%REPORT_DIR%\vivado-df-coefficient-store.log" >nul
set "METRICS=%REPORT_DIR%\metrics_post_synth.txt"
if not exist "%METRICS%" set "STATUS=1"

if "%STATUS%"=="0" (
  echo DF_COEFFICIENT_STORE_OOC_PASS
) else (
  echo DF_COEFFICIENT_STORE_OOC_FAIL
)
echo DF_COEFFICIENT_STORE_OOC_RUN_DIR=%RUN_DIR%
popd
exit /b %STATUS%
