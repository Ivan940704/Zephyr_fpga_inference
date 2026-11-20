@echo off
setlocal EnableExtensions

for %%I in ("%~dp0..\..") do set "SOURCE_REPO_ROOT=%%~fI"
if not defined VIVADO_BIN set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "WORK_ROOT=%TEMP%\zephyr_latency_32pe_%RANDOM%_%RANDOM%"
set "RESULT_DIR=%SOURCE_REPO_ROOT%\rtl\reports\latency_scaling_32pe_125mhz"
set "FAILED=0"

if not exist "%VIVADO%" (
  echo Missing Vivado 2018.3 tool: "%VIVADO%"
  exit /b 1
)
if not exist "%SOURCE_REPO_ROOT%\rtl\experiments\latency_scaling\pe_hybrid_mac_bank_32.v" (
  echo Missing 32-PE experiment sources
  exit /b 1
)

mkdir "%WORK_ROOT%\rtl\pe_array\baseline\v1\rtl\pe" 2>nul
mkdir "%WORK_ROOT%\rtl\experiments\latency_scaling\tb" 2>nul
mkdir "%WORK_ROOT%\rtl\experiments\latency_scaling\constraints" 2>nul
mkdir "%WORK_ROOT%\rtl\experiments\latency_scaling\scripts" 2>nul
mkdir "%WORK_ROOT%\logs" 2>nul
copy /y "%SOURCE_REPO_ROOT%\rtl\pe_array\baseline\v1\rtl\pe\pe_hybrid_mac.sv" "%WORK_ROOT%\rtl\pe_array\baseline\v1\rtl\pe\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\latency_scaling\pe_hybrid_mac_bank_32.v" "%WORK_ROOT%\rtl\experiments\latency_scaling\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\latency_scaling\tb\tb_pe_hybrid_mac_bank_32.sv" "%WORK_ROOT%\rtl\experiments\latency_scaling\tb\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\latency_scaling\constraints\pe_hybrid_mac_bank_32_125mhz.xdc" "%WORK_ROOT%\rtl\experiments\latency_scaling\constraints\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\latency_scaling\scripts\*.tcl" "%WORK_ROOT%\rtl\experiments\latency_scaling\scripts\" >nul
if errorlevel 1 exit /b 1

pushd "%WORK_ROOT%"
if errorlevel 1 exit /b 1
echo === 32-LANE HYBRID MAC XSIM ===
call "%VIVADO%" -mode batch -nojournal -log "logs\xsim.log" -source "rtl\experiments\latency_scaling\scripts\run_pe_hybrid_mac_bank_32_xsim.tcl" -tclargs "%WORK_ROOT%"
if errorlevel 1 (
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"LATENCY_32PE_XSIM_PASS" "logs\xsim.log" >nul
if errorlevel 1 (
  set "FAILED=1"
  goto :copy_results
)

echo === 32-LANE HYBRID MAC 125 MHZ OOC IMPLEMENTATION ===
call "%VIVADO%" -mode batch -nojournal -log "logs\implementation.log" -source "rtl\experiments\latency_scaling\scripts\impl_pe_hybrid_mac_bank_32_125mhz_ooc.tcl" -tclargs "%WORK_ROOT%"
if errorlevel 1 set "FAILED=1"
findstr /c:"LATENCY_32PE_125MHZ_CORE_FEASIBILITY_PASS" "logs\implementation.log" >nul
if errorlevel 1 set "FAILED=1"

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
copy /y "logs\*.log" "%RESULT_DIR%\" >nul 2>nul
if exist "rtl\reports\latency_scaling_32pe_125mhz" xcopy /e /i /y "rtl\reports\latency_scaling_32pe_125mhz" "%RESULT_DIR%" >nul
> "%RESULT_DIR%\run_status.txt" echo evidence=Windows_Vivado_2018.3
>> "%RESULT_DIR%\run_status.txt" echo scope=core_feasibility_not_full_system_timing_signoff
>> "%RESULT_DIR%\run_status.txt" echo simulation_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo implementation_run=OOC_PLACE_AND_ROUTE
>> "%RESULT_DIR%\run_status.txt" echo bitstream=NOT_GENERATED
>> "%RESULT_DIR%\run_status.txt" echo exit_failed=%FAILED%
>> "%RESULT_DIR%\run_status.txt" echo work_root=%WORK_ROOT%
echo LATENCY_32PE_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo LATENCY_32PE_VIVADO_ALL_PASS
exit /b %FAILED%
