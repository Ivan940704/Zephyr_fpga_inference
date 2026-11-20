@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Recreate, synthesize, place, and route the minimal PYNQ-Z1 parameter-BRAM
rem design in a disposable Windows temp tree.  This runner never invokes
rem write_bitstream.  Vivado 2018.3 automatically emits the BD Hw_Handoff
rem target while preparing project synthesis; the runner records and removes
rem that disposable side product, then verifies that no .bit/.hwh is retained.
set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "XVLOG=%VIVADO_BIN%\xvlog.bat"
set "XELAB=%VIVADO_BIN%\xelab.bat"
set "XSIM=%VIVADO_BIN%\xsim.bat"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "DESIGN_BASELINE=422be9f10fc5fe8ee89ca5653bf9d378ce5a4872"
set "WORK_ROOT=%TEMP%\zephyr_parameter_bram_impl_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "IMAGE_DIR=%WORK_ROOT%\outputs\memory\2026-09-01\v3"
set "STAGED_REPORT=%RTL_DIR%\reports\parameter_bram_implementation"
set "RESULT_DIR=%SOURCE_RTL%\reports\parameter_bram_implementation"
set "FAILED=0"

for %%T in ("%XVLOG%" "%XELAB%" "%XSIM%" "%VIVADO%") do (
  if not exist %%T (
    echo Missing Vivado 2018.3 tool: %%T
    exit /b 1
  )
)

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\logs" "%RTL_DIR%\reports\parameter_bram_bringup\bd" "%STAGED_REPORT%\smoke" "%IMAGE_DIR%" 2>nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.v" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.vh" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
for %%F in (tb_parameter_bram_bringup.v tb_memory.v tb_memory_service.v) do (
  copy /y "%SOURCE_RTL%\tb\%%F" "%RTL_DIR%\tb\" >nul
  if errorlevel 1 exit /b 1
)
for %%F in (create_parameter_bram_bringup_bd.tcl implement_parameter_bram_bringup_bd.tcl xsim_run_all.tcl) do (
  copy /y "%SOURCE_RTL%\scripts\%%F" "%RTL_DIR%\scripts\" >nul
  if errorlevel 1 exit /b 1
)
copy /y "%SOURCE_RTL%\..\outputs\memory\2026-09-01\v3\parameters_v3.bin" "%IMAGE_DIR%\" >nul
if errorlevel 1 exit /b 1

pushd "%RTL_DIR%"
if errorlevel 1 exit /b 1

> parameter_bram_smoke.prj echo nosort
for %%F in (memory\*.v) do >> parameter_bram_smoke.prj echo sv xil_defaultlib "%%~fF"
>> parameter_bram_smoke.prj echo sv xil_defaultlib "%RTL_DIR%\tb\tb_parameter_bram_bringup.v"
>> parameter_bram_smoke.prj echo sv xil_defaultlib "%RTL_DIR%\tb\tb_memory.v"
>> parameter_bram_smoke.prj echo sv xil_defaultlib "%RTL_DIR%\tb\tb_memory_service.v"

echo === PARAMETER BRAM REAL-V3 SMOKE XVLOG ===
call "%XVLOG%" --incr --relax -prj parameter_bram_smoke.prj > "logs\smoke-xvlog.log" 2>&1
if errorlevel 1 (
  echo PARAMETER_BRAM_SMOKE_XVLOG_ERROR
  set "FAILED=1"
  goto :copy_results
)
echo === PARAMETER BRAM REAL-V3 SMOKE XELAB ===
call "%XELAB%" --relax --debug typical --snapshot parameter_bram_smoke "xil_defaultlib.tb_parameter_bram_bringup" > "logs\smoke-xelab.log" 2>&1
if errorlevel 1 (
  echo PARAMETER_BRAM_SMOKE_XELAB_ERROR
  set "FAILED=1"
  goto :copy_results
)
echo === PARAMETER BRAM REAL-V3 SMOKE XSIM ===
call "%XSIM%" parameter_bram_smoke -tclbatch "scripts/xsim_run_all.tcl" -log "logs\smoke-xsim.log" > "logs\smoke-console.log" 2>&1
if errorlevel 1 (
  echo PARAMETER_BRAM_SMOKE_XSIM_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PASS tb_parameter_bram_bringup" "logs\smoke-xsim.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_SMOKE_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
copy /y "logs\smoke-xsim.log" "%STAGED_REPORT%\smoke\xsim.log" >nul
echo PARAMETER_BRAM_SMOKE_PASS

for %%T in (tb_memory tb_memory_service) do (
  echo === PARAMETER BRAM RELATED XSIM %%T ===
  call "%XELAB%" --relax --debug typical --snapshot "%%T_behav" "xil_defaultlib.%%T" > "logs\%%T-xelab.log" 2>&1
  if errorlevel 1 (
    echo PARAMETER_BRAM_RELATED_XELAB_ERROR %%T
    set "FAILED=1"
  ) else (
    call "%XSIM%" "%%T_behav" -tclbatch "scripts/xsim_run_all.tcl" -log "logs\%%T-xsim.log" > "logs\%%T-console.log" 2>&1
    if errorlevel 1 (
      echo PARAMETER_BRAM_RELATED_XSIM_ERROR %%T
      set "FAILED=1"
    ) else (
      findstr /c:"PASS %%T" "logs\%%T-xsim.log" >nul
      if errorlevel 1 (
        echo PARAMETER_BRAM_RELATED_PASS_MARKER_MISSING %%T
        set "FAILED=1"
      ) else (
        copy /y "logs\%%T-xsim.log" "%STAGED_REPORT%\smoke\%%T-xsim.log" >nul
        echo PARAMETER_BRAM_RELATED_XSIM_PASS %%T
      )
    )
  )
)
if "!FAILED!"=="1" goto :copy_results

echo === PARAMETER BRAM CLEAN BLOCK DESIGN REBUILD ===
call "%VIVADO%" -mode batch -nojournal -log "logs\vivado-bd.log" -source "scripts\create_parameter_bram_bringup_bd.tcl" -tclargs "."
if errorlevel 1 (
  echo PARAMETER_BRAM_BD_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PARAMETER_BRAM_BD_VALIDATE_PASS" "logs\vivado-bd.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_BD_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
copy /y "reports\parameter_bram_bringup\bd\bd_validation.txt" "%STAGED_REPORT%\bd_validation.txt" >nul
findstr /n /c:"PARAMETER_BRAM_DQS_STAGE" /c:"CRITICAL WARNING: [PSU-" "logs\vivado-bd.log" > "%STAGED_REPORT%\ddr_dqs_messages.txt"
echo PARAMETER_BRAM_BD_PASS

echo === PARAMETER BRAM FULL BLOCK DESIGN IMPLEMENTATION ===
call "%VIVADO%" -mode batch -nojournal -log "logs\vivado-implementation.log" -source "scripts\implement_parameter_bram_bringup_bd.tcl" -tclargs "." "%DESIGN_BASELINE%"
if errorlevel 1 (
  echo PARAMETER_BRAM_IMPLEMENTATION_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PARAMETER_BRAM_IMPLEMENTATION_ROUTE_COMPLETE" "logs\vivado-implementation.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_IMPLEMENTATION_ROUTE_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)

set "FORBIDDEN=0"
for /r "%WORK_ROOT%" %%F in (*.bit) do (
  echo FORBIDDEN_BITSTREAM_ARTIFACT %%F
  set "FORBIDDEN=1"
)
set "AUTO_HWH_COUNT=0"
for /r "%WORK_ROOT%" %%F in (*.hwh) do (
  set /a AUTO_HWH_COUNT+=1
  >> "%STAGED_REPORT%\automatic_hwh_side_product.txt" echo path=%%F bytes=%%~zF
  del /q "%%F"
  if exist "%%F" (
    echo UNABLE_TO_REMOVE_AUTOMATIC_HWH_ARTIFACT %%F
    set "FORBIDDEN=1"
  )
)
>> "%STAGED_REPORT%\automatic_hwh_side_product.txt" echo vivado_2018_3_auto_hwh_count=!AUTO_HWH_COUNT!
>> "%STAGED_REPORT%\automatic_hwh_side_product.txt" echo explicit_hwh_command_invoked=NO
>> "%STAGED_REPORT%\automatic_hwh_side_product.txt" echo retained_hwh_count=0
if "!FORBIDDEN!"=="1" (
  set "FAILED=1"
  goto :copy_results
)

> "%STAGED_REPORT%\checkpoint_manifest.txt" echo build_root=%WORK_ROOT%
for %%F in ("%WORK_ROOT%\zpb_implementation_checkpoints\zpb_post_synth.dcp" "%WORK_ROOT%\zpb_implementation_checkpoints\zpb_post_route.dcp") do (
  if exist %%F (
    >> "%STAGED_REPORT%\checkpoint_manifest.txt" echo checkpoint=%%~fF bytes=%%~zF
  ) else (
    >> "%STAGED_REPORT%\checkpoint_manifest.txt" echo missing_checkpoint=%%~fF
    set "FAILED=1"
  )
)
>> "%STAGED_REPORT%\checkpoint_manifest.txt" echo bit_files_found=0
>> "%STAGED_REPORT%\checkpoint_manifest.txt" echo hwh_auto_side_products_removed=!AUTO_HWH_COUNT!
>> "%STAGED_REPORT%\checkpoint_manifest.txt" echo hwh_files_retained=0
>> "%STAGED_REPORT%\checkpoint_manifest.txt" echo board_connected=NO
echo PARAMETER_BRAM_FULL_ROUTE_PASS

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
if exist "%STAGED_REPORT%" xcopy /e /i /y "%STAGED_REPORT%" "%RESULT_DIR%" >nul
> "%RESULT_DIR%\run_status.txt" echo evidence=Windows_Vivado_2018.3_full_block_design
>> "%RESULT_DIR%\run_status.txt" echo design_baseline_commit=%DESIGN_BASELINE%
>> "%RESULT_DIR%\run_status.txt" echo work_root=%WORK_ROOT%
>> "%RESULT_DIR%\run_status.txt" echo real_v3_smoke_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo bd_validation_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo synthesis_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo opt_design_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo place_design_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo route_design_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo write_bitstream_requested=NO
>> "%RESULT_DIR%\run_status.txt" echo board_connected=NO
>> "%RESULT_DIR%\run_status.txt" echo exit_failed=%FAILED%
echo PARAMETER_BRAM_IMPLEMENTATION_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo PARAMETER_BRAM_IMPLEMENTATION_ALL_PASS
exit /b %FAILED%
