@echo off
setlocal EnableExtensions
set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "WORK_ROOT=%TEMP%\zephyr_sequential_controller_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "RESULT_DIR=%SOURCE_RTL%\reports\sequential_pe_job_controller"
set "FAILED=0"

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\reports\sequential_pe_job_controller" "%RTL_DIR%\build" 2>nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\sequential_pe_job_controller.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\model_memory_v4_map.vh" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\sequential_pe_job_controller_100mhz.xdc" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\tb\tb_sequential_pe_job_controller.sv" "%RTL_DIR%\tb\" >nul
copy /y "%SOURCE_RTL%\scripts\synth_sequential_pe_job_controller_ooc.tcl" "%RTL_DIR%\scripts\" >nul

pushd "%RTL_DIR%"
call "%VIVADO_BIN%\xvlog.bat" --sv -i . memory\sequential_pe_job_controller.v tb\tb_sequential_pe_job_controller.sv > reports\sequential_pe_job_controller\xvlog_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" tb_sequential_pe_job_controller -s tb_sequential_controller_sim > reports\sequential_pe_job_controller\xelab_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" tb_sequential_controller_sim -runall -log reports\sequential_pe_job_controller\tb_controller_xsim.log > reports\sequential_pe_job_controller\xsim_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_pe_job_controller" reports\sequential_pe_job_controller\tb_controller_xsim.log >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal -log reports\sequential_pe_job_controller\vivado_ooc_console.txt -source scripts\synth_sequential_pe_job_controller_ooc.tcl -tclargs "%RTL_DIR%"
if errorlevel 1 set "FAILED=1"

if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
copy /y "reports\sequential_pe_job_controller\*" "%RESULT_DIR%\" >nul 2>nul
echo SEQUENTIAL_CONTROLLER_WORK_ROOT=%WORK_ROOT%
if "%FAILED%"=="0" echo SEQUENTIAL_CONTROLLER_ALL_PASS
popd
exit /b %FAILED%
