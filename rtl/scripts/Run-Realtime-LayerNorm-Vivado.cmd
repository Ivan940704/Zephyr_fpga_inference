@echo off
setlocal EnableExtensions

for %%I in ("%~dp0..\..") do set "SOURCE_REPO_ROOT=%%~fI"
if not defined VIVADO_BIN set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "WORK_ROOT=%TEMP%\zephyr_layernorm_q12_%RANDOM%_%RANDOM%"
set "RESULT_DIR=%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_q12_125mhz"
set "FAILED=0"

if not exist "%VIVADO%" (
  echo Missing Vivado 2018.3 tool: "%VIVADO%"
  exit /b 1
)
if not exist "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\layernorm_engine_q12.v" (
  echo Missing LayerNorm experiment sources
  exit /b 1
)

mkdir "%WORK_ROOT%\rtl\experiments\realtime_layernorm\tb" 2>nul
mkdir "%WORK_ROOT%\rtl\experiments\realtime_layernorm\constraints" 2>nul
mkdir "%WORK_ROOT%\rtl\experiments\realtime_layernorm\scripts" 2>nul
mkdir "%WORK_ROOT%\logs" 2>nul
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\layernorm_engine_q12.v" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\tb\*" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\tb\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\constraints\*" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\constraints\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\scripts\*" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\scripts\" >nul
if errorlevel 1 exit /b 1

pushd "%WORK_ROOT%"
if errorlevel 1 exit /b 1
echo === SHARED Q12 LAYERNORM XSIM ===
call "%VIVADO%" -mode batch -nojournal -log "logs\xsim.log" -source "rtl\experiments\realtime_layernorm\scripts\run_layernorm_engine_q12_xsim.tcl" -tclargs "%WORK_ROOT%"
if errorlevel 1 (
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"LAYER_NORM_Q12_XSIM_GATE_PASS" "logs\xsim.log" >nul
if errorlevel 1 (
  set "FAILED=1"
  goto :copy_results
)

echo === SHARED Q12 LAYERNORM 125 MHZ OOC IMPLEMENTATION ===
call "%VIVADO%" -mode batch -nojournal -log "logs\implementation.log" -source "rtl\experiments\realtime_layernorm\scripts\impl_layernorm_engine_q12_125mhz_ooc.tcl" -tclargs "%WORK_ROOT%"
if errorlevel 1 set "FAILED=1"
findstr /c:"LAYER_NORM_Q12_125MHZ_OOC_PASS" "logs\implementation.log" >nul
if errorlevel 1 set "FAILED=1"

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
copy /y "logs\*.log" "%RESULT_DIR%\" >nul 2>nul
if exist "rtl\reports\realtime_layernorm_q12_125mhz" xcopy /e /i /y "rtl\reports\realtime_layernorm_q12_125mhz" "%RESULT_DIR%" >nul
> "%RESULT_DIR%\run_status.txt" echo evidence=Windows_Vivado_2018.3
>> "%RESULT_DIR%\run_status.txt" echo scope=experimental_leaf_not_full_system_timing_signoff
>> "%RESULT_DIR%\run_status.txt" echo simulation_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo implementation_run=OOC_PLACE_AND_ROUTE
>> "%RESULT_DIR%\run_status.txt" echo bitstream=NOT_GENERATED
>> "%RESULT_DIR%\run_status.txt" echo exit_failed=%FAILED%
>> "%RESULT_DIR%\run_status.txt" echo work_root=%WORK_ROOT%
echo REALTIME_LAYERNORM_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo REALTIME_LAYERNORM_VIVADO_ALL_PASS
exit /b %FAILED%
