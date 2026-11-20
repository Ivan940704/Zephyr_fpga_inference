@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "XVLOG=%VIVADO_BIN%\xvlog.bat"
set "XELAB=%VIVADO_BIN%\xelab.bat"
set "XSIM=%VIVADO_BIN%\xsim.bat"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "WORK_ROOT=%TEMP%\zephyr_memory_v1_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "IMAGE_DIR=%WORK_ROOT%\outputs\memory\2026-09-03\v4"
set "RESULT_DIR=%SOURCE_RTL%\reports\memory_v1"
set "FAILED=0"

for %%T in ("%XVLOG%" "%XELAB%" "%XSIM%" "%VIVADO%") do (
  if not exist %%T (
    echo Missing Vivado 2018.3 tool: %%T
    exit /b 1
  )
)

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\logs" "%RTL_DIR%\build" "%RTL_DIR%\reports\memory_v1" "%IMAGE_DIR%" 2>nul
if errorlevel 1 exit /b 1

copy /y "%SOURCE_RTL%\memory\*.v" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.vh" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.xdc" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
for %%F in (tb_memory.v tb_memory_service.v tb_layernorm_mailbox.v) do (
  copy /y "%SOURCE_RTL%\tb\%%F" "%RTL_DIR%\tb\" >nul
  if errorlevel 1 exit /b 1
)
copy /y "%SOURCE_RTL%\scripts\xsim_run_all.tcl" "%RTL_DIR%\scripts\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\scripts\synth_memory_v1_ooc.tcl" "%RTL_DIR%\scripts\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\..\outputs\memory\2026-09-03\v4\parameters_v4.bin" "%IMAGE_DIR%\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\..\outputs\memory\2026-09-03\v4\parameters_v4.bin" "%RTL_DIR%\" >nul
if errorlevel 1 exit /b 1

pushd "%RTL_DIR%"
if errorlevel 1 exit /b 1

> memory_v1.prj echo nosort
for %%F in (memory\*.v) do >> memory_v1.prj echo sv xil_defaultlib "%%~fF"
for %%F in (tb\tb_memory.v tb\tb_memory_service.v tb\tb_layernorm_mailbox.v) do >> memory_v1.prj echo sv xil_defaultlib "%%~fF"

echo === MEMORY_V1 XVLOG ===
call "%XVLOG%" --incr --relax -prj memory_v1.prj > "logs\xvlog.log" 2>&1
if errorlevel 1 (
  echo MEMORY_V1_XVLOG_ERROR
  type "logs\xvlog.log"
  set "FAILED=1"
  goto :copy_results
)

for %%T in (tb_memory tb_memory_service tb_layernorm_mailbox) do call :run_test %%T
if "%FAILED%"=="1" goto :copy_results

echo === MEMORY_V1 OOC SYNTHESIS ===
call "%VIVADO%" -mode batch -nojournal -log "logs\vivado-memory-v1.log" -source "scripts/synth_memory_v1_ooc.tcl" -tclargs "."
findstr /c:"MEMORY_V1_OOC_ALL_COMPLETED" "logs\vivado-memory-v1.log" >nul
if errorlevel 1 (
  echo MEMORY_V1_OOC_ERROR
  set "FAILED=1"
) else (
  findstr /c:"MEMORY_V1_OOC_ALL_TIMING_PASS" "logs\vivado-memory-v1.log" >nul
  if errorlevel 1 (
    echo MEMORY_V1_OOC_TIMING_FAIL
    set "FAILED=1"
  ) else (
    echo MEMORY_V1_OOC_PASS
  )
)

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
if not exist "%RESULT_DIR%\xsim" mkdir "%RESULT_DIR%\xsim"
copy /y "logs\*.log" "%RESULT_DIR%\xsim\" >nul 2>nul
if exist "reports\memory_v1\memory_service" xcopy /e /i /y "reports\memory_v1\memory_service" "%RESULT_DIR%\memory_service" >nul
if exist "reports\memory_v1\layernorm_mailbox" xcopy /e /i /y "reports\memory_v1\layernorm_mailbox" "%RESULT_DIR%\layernorm_mailbox" >nul
echo MEMORY_V1_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo MEMORY_V1_VIVADO_ALL_PASS
exit /b %FAILED%

:run_test
set "TB_NAME=%~1"
echo === MEMORY_V1 XSIM %TB_NAME% ===
call "%XELAB%" --relax --debug typical --snapshot "%TB_NAME%_behav" "xil_defaultlib.%TB_NAME%" > "logs\%TB_NAME%-xelab.log" 2>&1
if errorlevel 1 (
  echo MEMORY_V1_XELAB_ERROR %TB_NAME%
  set "FAILED=1"
  goto :eof
)
call "%XSIM%" "%TB_NAME%_behav" -tclbatch "scripts/xsim_run_all.tcl" -log "logs\%TB_NAME%-xsim.log" > "logs\%TB_NAME%-console.log" 2>&1
if errorlevel 1 (
  echo MEMORY_V1_XSIM_ERROR %TB_NAME%
  set "FAILED=1"
  goto :eof
)
findstr /c:"PASS %TB_NAME%" "logs\%TB_NAME%-xsim.log" >nul
if errorlevel 1 (
  echo MEMORY_V1_PASS_MARKER_MISSING %TB_NAME%
  type "logs\%TB_NAME%-xsim.log"
  set "FAILED=1"
  goto :eof
)
echo MEMORY_V1_XSIM_PASS %TB_NAME%
goto :eof
