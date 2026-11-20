@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Rebuild the signed-off PYNQ-Z1 parameter-BRAM design in a new Windows
rem temp directory, re-run route/sign-off checks, then generate matching
rem Stage-2 .bit/.hwh/.ltx artifacts.  This runner never accesses a board.
set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "DESIGN_BASELINE=78c86f38f7c8f227bc2d032f5e2ef59ae4935d3e"
set "BUILD_TAG=%RANDOM%_%RANDOM%"
set "WORK_ROOT=%TEMP%\zephyr_parameter_bram_stage2_%BUILD_TAG%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "STAGED_REPORT=%RTL_DIR%\reports\parameter_bram_board_stage2"
set "STAGED_ARTIFACT=%WORK_ROOT%\artifacts"
set "RESULT_REPORT=%SOURCE_RTL%\reports\parameter_bram_board_stage2"
set "RESULT_ARTIFACT=%SOURCE_RTL%\build\parameter_bram_board_stage2\%DESIGN_BASELINE%_%BUILD_TAG%"
set "FAILED=0"

if not exist "%VIVADO%" (
  echo Missing Vivado 2018.3 tool: %VIVADO%
  exit /b 1
)

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\scripts" "%RTL_DIR%\reports\parameter_bram_bringup\bd" "%STAGED_REPORT%" "%STAGED_ARTIFACT%" 2>nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.v" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.vh" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
for %%F in (create_parameter_bram_bringup_bd.tcl implement_parameter_bram_bringup_bd.tcl write_parameter_bram_stage2_bitstream.tcl) do (
  copy /y "%SOURCE_RTL%\scripts\%%F" "%RTL_DIR%\scripts\" >nul
  if errorlevel 1 exit /b 1
)

pushd "%RTL_DIR%"
if errorlevel 1 exit /b 1

echo === PARAMETER BRAM STAGE2 CLEAN BLOCK DESIGN REBUILD ===
call "%VIVADO%" -mode batch -nojournal -log "%WORK_ROOT%\vivado-bd.log" -source "scripts\create_parameter_bram_bringup_bd.tcl" -tclargs "."
if errorlevel 1 (
  echo PARAMETER_BRAM_STAGE2_BD_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PARAMETER_BRAM_BD_VALIDATE_PASS" "%WORK_ROOT%\vivado-bd.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_STAGE2_BD_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
copy /y "reports\parameter_bram_bringup\bd\bd_validation.txt" "%STAGED_REPORT%\bd_validation.txt" >nul
findstr /n /c:"PARAMETER_BRAM_DQS_STAGE" /c:"CRITICAL WARNING: [PSU-" "%WORK_ROOT%\vivado-bd.log" > "%STAGED_REPORT%\ddr_dqs_messages.txt"

echo === PARAMETER BRAM STAGE2 CLEAN IMPLEMENTATION ===
call "%VIVADO%" -mode batch -nojournal -log "%WORK_ROOT%\vivado-implementation.log" -source "scripts\implement_parameter_bram_bringup_bd.tcl" -tclargs "." "%DESIGN_BASELINE%"
if errorlevel 1 (
  echo PARAMETER_BRAM_STAGE2_IMPLEMENTATION_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PARAMETER_BRAM_IMPLEMENTATION_ROUTE_COMPLETE" "%WORK_ROOT%\vivado-implementation.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_STAGE2_ROUTE_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
copy /y "reports\parameter_bram_implementation\metrics_post_route.txt" "%STAGED_REPORT%\implementation_metrics_source.txt" >nul

echo === PARAMETER BRAM STAGE2 WRITE BITSTREAM/HWH/LTX ===
call "%VIVADO%" -mode batch -nojournal -log "%WORK_ROOT%\vivado-bitstream.log" -source "scripts\write_parameter_bram_stage2_bitstream.tcl" -tclargs "." "%STAGED_ARTIFACT%" "%DESIGN_BASELINE%"
if errorlevel 1 (
  echo PARAMETER_BRAM_STAGE2_BITSTREAM_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PARAMETER_BRAM_STAGE2_BITSTREAM_COMPLETE" "%WORK_ROOT%\vivado-bitstream.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_STAGE2_BITSTREAM_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
for %%E in (bit hwh ltx) do (
  if not exist "%STAGED_ARTIFACT%\parameter_bram_stage2.%%E" (
    echo PARAMETER_BRAM_STAGE2_ARTIFACT_MISSING %%E
    set "FAILED=1"
  )
)
if "!FAILED!"=="1" goto :copy_results

mkdir "%RESULT_ARTIFACT%" 2>nul
if errorlevel 1 (
  set "FAILED=1"
  goto :copy_results
)
copy /y "%STAGED_ARTIFACT%\parameter_bram_stage2.bit" "%RESULT_ARTIFACT%\" >nul
if errorlevel 1 set "FAILED=1"
copy /y "%STAGED_ARTIFACT%\parameter_bram_stage2.hwh" "%RESULT_ARTIFACT%\" >nul
if errorlevel 1 set "FAILED=1"
copy /y "%STAGED_ARTIFACT%\parameter_bram_stage2.ltx" "%RESULT_ARTIFACT%\" >nul
if errorlevel 1 set "FAILED=1"

:copy_results
if not exist "%RESULT_REPORT%" mkdir "%RESULT_REPORT%"
if exist "%STAGED_REPORT%" xcopy /e /i /y "%STAGED_REPORT%" "%RESULT_REPORT%" >nul
findstr /n /c:"CRITICAL WARNING:" /c:"ERROR:" "%WORK_ROOT%\vivado-bd.log" "%WORK_ROOT%\vivado-implementation.log" "%WORK_ROOT%\vivado-bitstream.log" > "%RESULT_REPORT%\vivado_critical_digest.txt"
> "%RESULT_REPORT%\run_status.txt" echo evidence=Windows_Vivado_2018.3_stage2_bitstream_build
>> "%RESULT_REPORT%\run_status.txt" echo hardware_source_commit=%DESIGN_BASELINE%
>> "%RESULT_REPORT%\run_status.txt" echo work_root=%WORK_ROOT%
>> "%RESULT_REPORT%\run_status.txt" echo artifact_directory=%RESULT_ARTIFACT%
>> "%RESULT_REPORT%\run_status.txt" echo bd_validation_requested=YES
>> "%RESULT_REPORT%\run_status.txt" echo synthesis_requested=YES
>> "%RESULT_REPORT%\run_status.txt" echo opt_place_route_requested=YES
>> "%RESULT_REPORT%\run_status.txt" echo write_bitstream_requested=YES
>> "%RESULT_REPORT%\run_status.txt" echo matching_hwh_requested=YES
>> "%RESULT_REPORT%\run_status.txt" echo debug_ltx_requested=YES
>> "%RESULT_REPORT%\run_status.txt" echo board_connected=NO
>> "%RESULT_REPORT%\run_status.txt" echo exit_failed=%FAILED%
echo PARAMETER_BRAM_STAGE2_WORK_ROOT=%WORK_ROOT%
echo PARAMETER_BRAM_STAGE2_ARTIFACT_DIR=%RESULT_ARTIFACT%
popd

if "%FAILED%"=="0" echo PARAMETER_BRAM_STAGE2_ARTIFACT_BUILD_PASS
exit /b %FAILED%
