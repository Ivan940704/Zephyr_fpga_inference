@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Build a disposable Windows-local copy because Vivado 2018.3 is unreliable
rem when project databases are created directly on a WSL UNC path.  This flow
rem validates the full BD and runs synthesis, then deliberately stops before
rem opt_design/place_design/route_design/write_bitstream.
set "SOURCE_RTL=%~dp0.."
set "SOURCE_REPO=%SOURCE_RTL%\.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "WORK_ROOT=%TEMP%\zephyr_full_preimpl_%RANDOM%_%RANDOM%"
set "STAGED_REPO=%WORK_ROOT%\repo"
set "RTL_DIR=%STAGED_REPO%\rtl"
set "STAGED_REPORT=%RTL_DIR%\reports\accelerator_full_bd_preimplementation"
set "RESULT_DIR=%SOURCE_RTL%\reports\accelerator_full_bd_preimplementation"
set "FAILED=0"

for %%T in ("%VIVADO_BIN%\xvlog.bat" "%VIVADO_BIN%\xelab.bat" "%VIVADO_BIN%\xsim.bat" "%VIVADO_BIN%\vivado.bat") do (
  if not exist %%T (
    echo Missing Vivado 2018.3 tool: %%T
    exit /b 1
  )
)

mkdir "%RTL_DIR%\axi" "%RTL_DIR%\control" "%RTL_DIR%\integration" "%RTL_DIR%\leaf" "%RTL_DIR%\memory" "%RTL_DIR%\profiling" "%RTL_DIR%\top" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\logs" "%RTL_DIR%\reports\accelerator_full_bd_preimplementation" "%RTL_DIR%\pe_array\baseline\v1\rtl" "%STAGED_REPO%\sparse_memory_v1\rtl" 2>nul
if errorlevel 1 exit /b 1

for %%D in (axi control integration leaf memory profiling top) do (
  xcopy /e /i /y "%SOURCE_RTL%\%%D" "%RTL_DIR%\%%D" >nul
  if errorlevel 1 exit /b 1
)
xcopy /e /i /y "%SOURCE_RTL%\pe_array\baseline\v1\rtl" "%RTL_DIR%\pe_array\baseline\v1\rtl" >nul
if errorlevel 1 exit /b 1
xcopy /e /i /y "%SOURCE_REPO%\sparse_memory_v1\rtl" "%STAGED_REPO%\sparse_memory_v1\rtl" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\tb\tb_accelerator_control_axil.sv" "%RTL_DIR%\tb\" >nul
if errorlevel 1 exit /b 1
for %%F in (create_accelerator_full_bd.tcl synth_accelerator_full_bd.tcl xsim_run_all.tcl) do (
  copy /y "%SOURCE_RTL%\scripts\%%F" "%RTL_DIR%\scripts\" >nul
  if errorlevel 1 exit /b 1
)

pushd "%STAGED_REPO%"
if errorlevel 1 exit /b 1

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
  -tclargs "rtl"
if errorlevel 1 (
  echo ACCELERATOR_FULL_BD_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"validate_bd_design=PASS" "%STAGED_REPORT%\bd_validation.txt" >nul
if errorlevel 1 (
  echo ACCELERATOR_FULL_BD_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
echo ACCELERATOR_FULL_BD_PASS

echo === ACCELERATOR FULL BLOCK DESIGN SYNTHESIS ===
call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log "rtl\logs\vivado-synthesis.log" ^
  -source "rtl\scripts\synth_accelerator_full_bd.tcl" ^
  -tclargs "rtl"
if errorlevel 1 (
  echo ACCELERATOR_FULL_SYNTH_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"evidence=full_block_design_post_synthesis_only" "%STAGED_REPORT%\synthesis_metrics.txt" >nul
if errorlevel 1 (
  echo ACCELERATOR_FULL_SYNTH_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"implementation_status=Not started" "%STAGED_REPORT%\synthesis_metrics.txt" >nul
if errorlevel 1 (
  echo ACCELERATOR_FULL_IMPLEMENTATION_STOP_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)

set "FORBIDDEN=0"
for /r "%WORK_ROOT%" %%F in (*.bit) do (
  echo FORBIDDEN_BITSTREAM_ARTIFACT %%F
  set "FORBIDDEN=1"
)
for /r "%WORK_ROOT%" %%F in (*post_route*.dcp *_routed.dcp) do (
  echo FORBIDDEN_IMPLEMENTATION_CHECKPOINT %%F
  set "FORBIDDEN=1"
)
findstr /c:"opt_design=NOT_RUN" "%STAGED_REPORT%\synthesis_metrics.txt" >nul
if errorlevel 1 set "FORBIDDEN=1"
findstr /c:"place_design=NOT_RUN" "%STAGED_REPORT%\synthesis_metrics.txt" >nul
if errorlevel 1 set "FORBIDDEN=1"
findstr /c:"route_design=NOT_RUN" "%STAGED_REPORT%\synthesis_metrics.txt" >nul
if errorlevel 1 set "FORBIDDEN=1"
if "!FORBIDDEN!"=="1" (
  echo ACCELERATOR_FULL_PREIMPLEMENTATION_BOUNDARY_VIOLATED
  set "FAILED=1"
  goto :copy_results
)
echo ACCELERATOR_FULL_SYNTH_PASS
echo ACCELERATOR_FULL_IMPLEMENTATION_NOT_RUN

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
if exist "%STAGED_REPORT%" xcopy /e /i /y "%STAGED_REPORT%" "%RESULT_DIR%" >nul
copy /y "rtl\logs\*.log" "%RESULT_DIR%\" >nul 2>nul
> "%RESULT_DIR%\run_status.txt" echo evidence=Windows_Vivado_2018.3_full_bd_preimplementation
>> "%RESULT_DIR%\run_status.txt" echo work_root=%WORK_ROOT%
>> "%RESULT_DIR%\run_status.txt" echo control_xsim_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo bd_validation_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo full_synthesis_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo opt_design_requested=NO
>> "%RESULT_DIR%\run_status.txt" echo place_design_requested=NO
>> "%RESULT_DIR%\run_status.txt" echo route_design_requested=NO
>> "%RESULT_DIR%\run_status.txt" echo write_bitstream_requested=NO
>> "%RESULT_DIR%\run_status.txt" echo board_connected=NO
>> "%RESULT_DIR%\run_status.txt" echo exit_failed=%FAILED%
echo ACCELERATOR_FULL_PREIMPLEMENTATION_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo ACCELERATOR_FULL_PREIMPLEMENTATION_ALL_PASS
exit /b %FAILED%
