@echo off
setlocal EnableExtensions
set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "WORK_ROOT=%TEMP%\zephyr_context_store_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "RESULT_DIR=%SOURCE_RTL%\reports\sequential_recurrent_context_store"
set "FAILED=0"

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\reports\sequential_recurrent_context_store" "%RTL_DIR%\build" 2>nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\sequential_recurrent_context_store.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\sequential_recurrent_context_store_100mhz.xdc" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\tb\tb_sequential_recurrent_context_store.v" "%RTL_DIR%\tb\" >nul
copy /y "%SOURCE_RTL%\scripts\synth_sequential_recurrent_context_store_ooc.tcl" "%RTL_DIR%\scripts\" >nul

pushd "%RTL_DIR%"
call "%VIVADO_BIN%\xvlog.bat" --sv memory\sequential_recurrent_context_store.v tb\tb_sequential_recurrent_context_store.v > reports\sequential_recurrent_context_store\xvlog_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" tb_sequential_recurrent_context_store -s tb_context_store_sim > reports\sequential_recurrent_context_store\xelab_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" tb_context_store_sim -runall -log reports\sequential_recurrent_context_store\tb_context_store_xsim.log > reports\sequential_recurrent_context_store\xsim_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_recurrent_context_store" reports\sequential_recurrent_context_store\tb_context_store_xsim.log >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal -log reports\sequential_recurrent_context_store\vivado_ooc_console.txt -source scripts\synth_sequential_recurrent_context_store_ooc.tcl -tclargs "%RTL_DIR%"
if errorlevel 1 set "FAILED=1"

if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
copy /y "reports\sequential_recurrent_context_store\*" "%RESULT_DIR%\" >nul 2>nul
echo CONTEXT_STORE_WORK_ROOT=%WORK_ROOT%
if "%FAILED%"=="0" echo CONTEXT_STORE_ALL_PASS
popd
exit /b %FAILED%
