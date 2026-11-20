@echo off
setlocal EnableExtensions

rem Windows Vivado 2018.3 runner for this checkpoint only.  Source is staged
rem off WSL/UNC because Vivado batch tools are more reliable on a local drive.
set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "XVLOG=%VIVADO_BIN%\xvlog.bat"
set "XELAB=%VIVADO_BIN%\xelab.bat"
set "XSIM=%VIVADO_BIN%\xsim.bat"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "WORK_ROOT=%TEMP%\zephyr_parameter_bram_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "IMAGE_DIR=%WORK_ROOT%\outputs\memory\2026-09-01\v3"
set "RESULT_DIR=%SOURCE_RTL%\reports\parameter_bram_bringup"
set "FAILED=0"

for %%T in ("%XVLOG%" "%XELAB%" "%XSIM%" "%VIVADO%") do (
  if not exist %%T (
    echo Missing Vivado 2018.3 tool: %%T
    exit /b 1
  )
)

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\logs" "%RTL_DIR%\build" "%RTL_DIR%\reports\parameter_bram_bringup" "%IMAGE_DIR%" 2>nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.v" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.vh" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.xdc" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
for %%F in (tb_parameter_bram_bringup.v tb_memory.v tb_memory_service.v tb_layernorm_mailbox.v) do (
  copy /y "%SOURCE_RTL%\tb\%%F" "%RTL_DIR%\tb\" >nul
  if errorlevel 1 exit /b 1
)
for %%F in (xsim_run_all.tcl synth_parameter_bram_bringup_ooc.tcl create_parameter_bram_bringup_bd.tcl) do (
  copy /y "%SOURCE_RTL%\scripts\%%F" "%RTL_DIR%\scripts\" >nul
  if errorlevel 1 exit /b 1
)
copy /y "%SOURCE_RTL%\..\outputs\memory\2026-09-01\v3\parameters_v3.bin" "%IMAGE_DIR%\" >nul
if errorlevel 1 exit /b 1

pushd "%RTL_DIR%"
if errorlevel 1 exit /b 1

if /i "%~1"=="bd-only" goto :run_bd

> parameter_bram.prj echo nosort
for %%F in (memory\*.v) do >> parameter_bram.prj echo sv xil_defaultlib "%%~fF"
>> parameter_bram.prj echo sv xil_defaultlib "%RTL_DIR%\tb\tb_parameter_bram_bringup.v"
for %%F in (tb_memory.v tb_memory_service.v tb_layernorm_mailbox.v) do >> parameter_bram.prj echo sv xil_defaultlib "%RTL_DIR%\tb\%%F"

echo === PARAMETER BRAM XVLOG ===
call "%XVLOG%" --incr --relax -prj parameter_bram.prj > "logs\xvlog.log" 2>&1
if errorlevel 1 (
  echo PARAMETER_BRAM_XVLOG_ERROR
  type "logs\xvlog.log"
  set "FAILED=1"
  goto :copy_results
)

echo === PARAMETER BRAM XELAB ===
call "%XELAB%" --relax --debug typical --snapshot parameter_bram_behav "xil_defaultlib.tb_parameter_bram_bringup" > "logs\xelab.log" 2>&1
if errorlevel 1 (
  echo PARAMETER_BRAM_XELAB_ERROR
  type "logs\xelab.log"
  set "FAILED=1"
  goto :copy_results
)

echo === PARAMETER BRAM XSIM ===
call "%XSIM%" parameter_bram_behav -tclbatch "scripts/xsim_run_all.tcl" -log "logs\xsim.log" > "logs\xsim-console.log" 2>&1
if errorlevel 1 (
  echo PARAMETER_BRAM_XSIM_ERROR
  type "logs\xsim.log"
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PASS tb_parameter_bram_bringup" "logs\xsim.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_XSIM_PASS_MARKER_MISSING
  type "logs\xsim.log"
  set "FAILED=1"
  goto :copy_results
)
echo PARAMETER_BRAM_XSIM_PASS
rem Keep this loop inline.  cmd.exe's CALL :label scanner is unreliable for an
rem LF-only batch file launched from WSL/UNC, while ERRORLEVEL remains safe to
rem evaluate inside the loop.
for %%T in (tb_memory tb_memory_service tb_layernorm_mailbox) do (
  echo === PARAMETER BRAM REGRESSION %%T ===
  call "%XELAB%" --relax --debug typical --snapshot "%%T_behav" "xil_defaultlib.%%T" > "logs\%%T-xelab.log" 2>&1
  if errorlevel 1 (
    echo PARAMETER_BRAM_REGRESSION_XELAB_ERROR %%T
    set "FAILED=1"
  ) else (
    call "%XSIM%" "%%T_behav" -tclbatch "scripts/xsim_run_all.tcl" -log "logs\%%T-xsim.log" > "logs\%%T-console.log" 2>&1
    if errorlevel 1 (
      echo PARAMETER_BRAM_REGRESSION_XSIM_ERROR %%T
      set "FAILED=1"
    ) else (
      findstr /c:"PASS %%T" "logs\%%T-xsim.log" >nul
      if errorlevel 1 (
        echo PARAMETER_BRAM_REGRESSION_PASS_MARKER_MISSING %%T
        set "FAILED=1"
      ) else (
        echo PARAMETER_BRAM_REGRESSION_PASS %%T
      )
    )
  )
)
if "%FAILED%"=="1" goto :copy_results

echo === PARAMETER BRAM INTEGRATED OOC SYNTHESIS ===
call "%VIVADO%" -mode batch -nojournal -log "logs\vivado-synthesis.log" -source "scripts/synth_parameter_bram_bringup_ooc.tcl" -tclargs "."
if errorlevel 1 (
  echo PARAMETER_BRAM_SYNTH_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PARAMETER_BRAM_SYNTH_TIMING_PASS" "logs\vivado-synthesis.log" >nul
if errorlevel 1 (
  echo PARAMETER_BRAM_SYNTH_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
echo PARAMETER_BRAM_SYNTH_PASS

:run_bd
echo === PARAMETER BRAM BLOCK DESIGN VALIDATION ===
call "%VIVADO%" -mode batch -nojournal -log "logs\vivado-bd.log" -source "scripts/create_parameter_bram_bringup_bd.tcl" -tclargs "."
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
echo PARAMETER_BRAM_BD_PASS

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
if not exist "%RESULT_DIR%\xsim" mkdir "%RESULT_DIR%\xsim"
copy /y "logs\*.log" "%RESULT_DIR%\xsim\" >nul 2>nul
if exist "reports\parameter_bram_bringup\synthesis" xcopy /e /i /y "reports\parameter_bram_bringup\synthesis" "%RESULT_DIR%\synthesis" >nul
if exist "reports\parameter_bram_bringup\bd" xcopy /e /i /y "reports\parameter_bram_bringup\bd" "%RESULT_DIR%\bd" >nul
> "%RESULT_DIR%\run_status.txt" echo evidence=Windows_Vivado_2018.3
>> "%RESULT_DIR%\run_status.txt" echo xsim_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo integrated_ooc_synthesis_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo bd_validation_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo implementation_run=NOT_RUN
>> "%RESULT_DIR%\run_status.txt" echo bitstream=NOT_GENERATED
>> "%RESULT_DIR%\run_status.txt" echo exit_failed=%FAILED%
echo PARAMETER_BRAM_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo PARAMETER_BRAM_VIVADO_ALL_PASS
exit /b %FAILED%
