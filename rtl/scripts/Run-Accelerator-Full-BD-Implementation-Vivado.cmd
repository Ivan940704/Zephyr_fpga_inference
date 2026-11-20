@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Rebuild, synthesize, place, route, and physically optimize the complete
rem PYNQ-Z1 accelerator in a disposable Windows-local tree.  This checkpoint
rem deliberately does not generate or retain a bitstream, and does not
rem explicitly export or retain a production hardware handoff. Vivado may
rem create a temporary BD HWH internally while rebuilding the block design.
set "SOURCE_RTL=%~dp0.."
set "SOURCE_REPO=%SOURCE_RTL%\.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "WORK_ROOT=%TEMP%\zephyr_full_impl_%RANDOM%_%RANDOM%"
set "STAGED_REPO=%WORK_ROOT%\repo"
set "RTL_DIR=%STAGED_REPO%\rtl"
rem Tcl treats backslashes in command-line arguments as escapes (for example,
rem C:\tmp begins with a tab escape).  Pass the staged root using Tcl-native
rem forward slashes so file normalize preserves the absolute Windows path.
set "RTL_DIR_TCL=%RTL_DIR:\=/%"
set "STAGED_REPORT=%RTL_DIR%\reports\accelerator_full_bd_implementation"
set "RESULT_DIR=%SOURCE_RTL%\reports\accelerator_full_bd_implementation"
if defined ZEPHYR_DESIGN_REVISION (
  set "DESIGN_BASELINE=%ZEPHYR_DESIGN_REVISION%"
) else (
  rem A caller building a committed checkout should set ZEPHYR_DESIGN_REVISION
  rem explicitly.  Never label a new result with a stale historical commit.
  set "DESIGN_BASELINE=WORKTREE_UNSPECIFIED"
)
set "FAILED=0"
set "IMPLEMENTATION_RC=NOT_RUN"
set "METRICS_GATE=NOT_RUN"

for %%T in ("%VIVADO_BIN%\xvlog.bat" "%VIVADO_BIN%\xelab.bat" "%VIVADO_BIN%\xsim.bat" "%VIVADO_BIN%\vivado.bat") do (
  if not exist %%T (
    echo Missing Vivado 2018.3 tool: %%T
    exit /b 1
  )
)

mkdir "%RTL_DIR%\axi" "%RTL_DIR%\control" "%RTL_DIR%\experiments" "%RTL_DIR%\integration" "%RTL_DIR%\leaf" "%RTL_DIR%\memory" "%RTL_DIR%\profiling" "%RTL_DIR%\top" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\logs" "%RTL_DIR%\reports\accelerator_full_bd_preimplementation" "%STAGED_REPORT%" "%RTL_DIR%\pe_array\baseline\v1\rtl" "%RTL_DIR%\pe_array\production_v2\rtl" "%STAGED_REPO%\sparse_memory_v1\rtl" 2>nul
if errorlevel 1 exit /b 1

rem Keep human-readable report metadata across replacement of generated files.
for %%F in (.gitattributes summary.md) do (
  if exist "%RESULT_DIR%\%%F" copy /y "%RESULT_DIR%\%%F" "%STAGED_REPORT%\%%F" >nul
)

for %%D in (axi control experiments integration leaf memory profiling top) do (
  xcopy /e /i /y "%SOURCE_RTL%\%%D" "%RTL_DIR%\%%D" >nul
  if errorlevel 1 exit /b 1
)
xcopy /e /i /y "%SOURCE_RTL%\pe_array\baseline\v1\rtl" "%RTL_DIR%\pe_array\baseline\v1\rtl" >nul
if errorlevel 1 exit /b 1
xcopy /e /i /y "%SOURCE_RTL%\pe_array\production_v2\rtl" "%RTL_DIR%\pe_array\production_v2\rtl" >nul
if errorlevel 1 exit /b 1
xcopy /e /i /y "%SOURCE_REPO%\sparse_memory_v1\rtl" "%STAGED_REPO%\sparse_memory_v1\rtl" >nul
if errorlevel 1 exit /b 1
for %%F in (tb_accelerator_control_axil.sv tb_accelerator_profiling_counters.v) do (
  copy /y "%SOURCE_RTL%\tb\%%F" "%RTL_DIR%\tb\" >nul
  if errorlevel 1 exit /b 1
)
for %%F in (create_accelerator_full_bd.tcl synth_accelerator_full_bd.tcl implement_accelerator_full_bd.tcl xsim_run_all.tcl) do (
  copy /y "%SOURCE_RTL%\scripts\%%F" "%RTL_DIR%\scripts\" >nul
  if errorlevel 1 exit /b 1
)

pushd "%STAGED_REPO%"
if errorlevel 1 exit /b 1

echo === ACCELERATOR PROFILING XVLOG ===
call "%VIVADO_BIN%\xvlog.bat" --sv --relax ^
  "rtl\profiling\accelerator_profiling_counters.v" ^
  "rtl\tb\tb_accelerator_profiling_counters.v" ^
  > "rtl\logs\profiling-xvlog.log" 2>&1
if errorlevel 1 (
  echo ACCELERATOR_PROFILING_XVLOG_ERROR
  set "FAILED=1"
  goto :copy_results
)

echo === ACCELERATOR PROFILING XELAB ===
call "%VIVADO_BIN%\xelab.bat" --relax --debug typical ^
  --snapshot accelerator_profiling_behav ^
  "work.tb_accelerator_profiling_counters" ^
  > "rtl\logs\profiling-xelab.log" 2>&1
if errorlevel 1 (
  echo ACCELERATOR_PROFILING_XELAB_ERROR
  set "FAILED=1"
  goto :copy_results
)

echo === ACCELERATOR PROFILING XSIM ===
call "%VIVADO_BIN%\xsim.bat" accelerator_profiling_behav ^
  -tclbatch "rtl/scripts/xsim_run_all.tcl" ^
  -log "rtl\logs\profiling-xsim.log" ^
  > "rtl\logs\profiling-xsim-console.log" 2>&1
if errorlevel 1 (
  echo ACCELERATOR_PROFILING_XSIM_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PASS tb_accelerator_profiling_counters" "rtl\logs\profiling-xsim.log" >nul
if errorlevel 1 (
  echo ACCELERATOR_PROFILING_XSIM_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
echo ACCELERATOR_PROFILING_XSIM_PASS

echo === ACCELERATOR CONTROL XVLOG ===
call "%VIVADO_BIN%\xvlog.bat" --sv --relax ^
  "rtl\axi\accelerator_control_axil.v" ^
  "rtl\tb\tb_accelerator_control_axil.sv" ^
  > "rtl\logs\control-xvlog.log" 2>&1
if errorlevel 1 (
  echo ACCELERATOR_CONTROL_XVLOG_ERROR
  set "FAILED=1"
  goto :copy_results
)

echo === ACCELERATOR CONTROL XELAB ===
call "%VIVADO_BIN%\xelab.bat" --relax --debug typical ^
  --snapshot accelerator_control_behav ^
  "work.tb_accelerator_control_axil" ^
  > "rtl\logs\control-xelab.log" 2>&1
if errorlevel 1 (
  echo ACCELERATOR_CONTROL_XELAB_ERROR
  set "FAILED=1"
  goto :copy_results
)

echo === ACCELERATOR CONTROL XSIM ===
call "%VIVADO_BIN%\xsim.bat" accelerator_control_behav ^
  -tclbatch "rtl/scripts/xsim_run_all.tcl" ^
  -log "rtl\logs\control-xsim.log" ^
  > "rtl\logs\control-xsim-console.log" 2>&1
if errorlevel 1 (
  echo ACCELERATOR_CONTROL_XSIM_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PASS tb_accelerator_control_axil" "rtl\logs\control-xsim.log" >nul
if errorlevel 1 (
  echo ACCELERATOR_CONTROL_XSIM_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
echo ACCELERATOR_CONTROL_XSIM_PASS

echo === ACCELERATOR FULL BLOCK DESIGN VALIDATION ===
call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log "rtl\logs\vivado-bd.log" ^
  -source "rtl\scripts\create_accelerator_full_bd.tcl" ^
  -tclargs "%RTL_DIR_TCL%"
if errorlevel 1 (
  echo ACCELERATOR_FULL_BD_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"validate_bd_design=PASS" "rtl\reports\accelerator_full_bd_preimplementation\bd_validation.txt" >nul
if errorlevel 1 (
  echo ACCELERATOR_FULL_BD_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
copy /y "rtl\reports\accelerator_full_bd_preimplementation\bd_validation.txt" "%STAGED_REPORT%\bd_validation.txt" >nul
echo ACCELERATOR_FULL_BD_PASS

echo === ACCELERATOR FULL BLOCK DESIGN SYNTHESIS ===
call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log "rtl\logs\vivado-synthesis.log" ^
  -source "rtl\scripts\synth_accelerator_full_bd.tcl" ^
  -tclargs "%RTL_DIR_TCL%"
if errorlevel 1 (
  echo ACCELERATOR_FULL_SYNTH_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"ACCELERATOR_FULL_SYNTH_PASS" "rtl\logs\vivado-synthesis.log" >nul
if errorlevel 1 (
  echo ACCELERATOR_FULL_SYNTH_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
copy /y "rtl\reports\accelerator_full_bd_preimplementation\synthesis_metrics.txt" "%STAGED_REPORT%\synthesis_metrics_source.txt" >nul
echo ACCELERATOR_FULL_SYNTH_PASS

echo === ACCELERATOR FULL BLOCK DESIGN IMPLEMENTATION ===
if defined ZEPHYR_INCREMENTAL_REFERENCE (
  echo ACCELERATOR_FULL_INCREMENTAL_REFERENCE=!ZEPHYR_INCREMENTAL_REFERENCE!
  call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
    -log "rtl\logs\vivado-implementation.log" ^
    -source "rtl\scripts\implement_accelerator_full_bd.tcl" ^
    -tclargs "%RTL_DIR_TCL%" "%DESIGN_BASELINE%" "!ZEPHYR_INCREMENTAL_REFERENCE!"
) else (
  call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
    -log "rtl\logs\vivado-implementation.log" ^
    -source "rtl\scripts\implement_accelerator_full_bd.tcl" ^
    -tclargs "%RTL_DIR_TCL%" "%DESIGN_BASELINE%"
)
set "IMPLEMENTATION_RC=!ERRORLEVEL!"
if not exist "%STAGED_REPORT%\metrics_post_route.txt" (
  echo ACCELERATOR_FULL_IMPLEMENTATION_METRICS_MISSING
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_COMPLETE" "rtl\logs\vivado-implementation.log" >nul
if errorlevel 1 (
  echo ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
rem Vivado Tcl writes LF-only text. Windows findstr /x treats that final LF as
rem part of the line, so use literal beginning-of-line matching for fixed
rem boolean key/value records instead.
set "METRICS_GATE=PASS"
for %%M in ("timing_met=1" "hold_met=1" "hold_guardband_met=1" "resources_below_limit=1" "routing_errors_zero=1" "unconstrained_internal_endpoints_zero=1" "clockless_registers_zero=1" "combinational_loops_zero=1" "latch_loops_zero=1" "cdc_all_paths_safely_timed=1" "blocking_drc_zero=1" "full_gate_pass=1" "write_bitstream_invoked=NO") do (
  findstr /b /l /c:"%%~M" "%STAGED_REPORT%\metrics_post_route.txt" >nul
  if errorlevel 1 (
    echo ACCELERATOR_FULL_IMPLEMENTATION_METRIC_MISSING %%~M
    set "METRICS_GATE=FAIL"
    set "FAILED=1"
  )
)

set "FORBIDDEN=0"
for /r "%WORK_ROOT%" %%F in (*.bit) do (
  echo FORBIDDEN_BITSTREAM_ARTIFACT %%F
  set "FORBIDDEN=1"
)
if "!FORBIDDEN!"=="1" (
  set "FAILED=1"
  goto :copy_results
)

> "%STAGED_REPORT%\checkpoint_manifest.txt" echo build_root=%WORK_ROOT%
for %%F in ("%WORK_ROOT%\repo\zephyr_full_bd\checkpoints\zephyr_full_post_synth.dcp" "%WORK_ROOT%\repo\zephyr_full_implementation_checkpoints\zephyr_full_post_route.dcp") do (
  if exist %%F (
    >> "%STAGED_REPORT%\checkpoint_manifest.txt" echo checkpoint=%%~fF bytes=%%~zF
  ) else (
    >> "%STAGED_REPORT%\checkpoint_manifest.txt" echo missing_checkpoint=%%~fF
    set "FAILED=1"
  )
)
>> "%STAGED_REPORT%\checkpoint_manifest.txt" echo bit_files_found=0
>> "%STAGED_REPORT%\checkpoint_manifest.txt" echo explicit_hwh_command_invoked=NO
>> "%STAGED_REPORT%\checkpoint_manifest.txt" echo board_connected=NO
if not "!IMPLEMENTATION_RC!"=="0" (
  echo ACCELERATOR_FULL_IMPLEMENTATION_GATE_ERROR rc=!IMPLEMENTATION_RC!
  set "FAILED=1"
)
if "!FAILED!"=="0" echo ACCELERATOR_FULL_IMPLEMENTATION_ALL_GATES_PASS

:copy_results
if exist "rtl\logs\profiling-xvlog.log" copy /y "rtl\logs\profiling-xvlog.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\profiling-xelab.log" copy /y "rtl\logs\profiling-xelab.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\profiling-xsim.log" copy /y "rtl\logs\profiling-xsim.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\profiling-xsim-console.log" copy /y "rtl\logs\profiling-xsim-console.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\control-xvlog.log" copy /y "rtl\logs\control-xvlog.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\control-xelab.log" copy /y "rtl\logs\control-xelab.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\control-xsim.log" copy /y "rtl\logs\control-xsim.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\control-xsim-console.log" copy /y "rtl\logs\control-xsim-console.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\vivado-bd.log" copy /y "rtl\logs\vivado-bd.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\vivado-synthesis.log" copy /y "rtl\logs\vivado-synthesis.log" "%STAGED_REPORT%\" >nul
if exist "rtl\logs\vivado-implementation.log" copy /y "rtl\logs\vivado-implementation.log" "%STAGED_REPORT%\" >nul
findstr /n /c:"CRITICAL WARNING:" /c:"ERROR:" "%STAGED_REPORT%\*.log" > "%STAGED_REPORT%\vivado_critical_digest.txt" 2>nul
> "%STAGED_REPORT%\run_status.txt" echo evidence=Windows_Vivado_2018.3_full_block_design_implementation
>> "%STAGED_REPORT%\run_status.txt" echo design_baseline_commit=%DESIGN_BASELINE%
>> "%STAGED_REPORT%\run_status.txt" echo work_root=%WORK_ROOT%
>> "%STAGED_REPORT%\run_status.txt" echo profiling_xsim_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo control_xsim_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo bd_validation_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo synthesis_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo opt_design_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo place_design_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo phys_opt_design_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo route_design_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo post_route_phys_opt_design_requested=YES
>> "%STAGED_REPORT%\run_status.txt" echo write_bitstream_requested=NO
>> "%STAGED_REPORT%\run_status.txt" echo board_connected=NO
>> "%STAGED_REPORT%\run_status.txt" echo vivado_implementation_rc=!IMPLEMENTATION_RC!
>> "%STAGED_REPORT%\run_status.txt" echo metrics_gate=!METRICS_GATE!
>> "%STAGED_REPORT%\run_status.txt" echo exit_failed=%FAILED%
if exist "%RESULT_DIR%" rmdir /s /q "%RESULT_DIR%"
if exist "%STAGED_REPORT%" xcopy /e /i /y "%STAGED_REPORT%" "%RESULT_DIR%" >nul
echo ACCELERATOR_FULL_IMPLEMENTATION_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo ACCELERATOR_FULL_IMPLEMENTATION_ALL_PASS
exit /b %FAILED%
