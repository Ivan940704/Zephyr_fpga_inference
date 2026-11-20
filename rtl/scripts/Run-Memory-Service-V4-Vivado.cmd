@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "WORK_ROOT=%TEMP%\zephyr_memory_service_v4_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "RESULT_DIR=%SOURCE_RTL%\reports\memory_service_v4"
set "FAILED=0"

for %%T in (xvlog.bat xelab.bat xsim.bat vivado.bat) do (
  if not exist "%VIVADO_BIN%\%%T" (
    echo Missing Vivado 2018.3 tool: %VIVADO_BIN%\%%T
    exit /b 1
  )
)

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\reports\memory_service_v4" "%RTL_DIR%\build" 2>nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\memory.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\memory_service.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\model_memory_v4_table.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\model_memory_v4_map.vh" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\memory_service_v4_100mhz.xdc" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\tb\tb_memory_service.v" "%RTL_DIR%\tb\" >nul
copy /y "%SOURCE_RTL%\scripts\synth_memory_service_v4_ooc.tcl" "%RTL_DIR%\scripts\" >nul
copy /y "%SOURCE_RTL%\..\outputs\memory\2026-09-03\v4\parameters_v4.bin" "%RTL_DIR%\" >nul
if errorlevel 1 exit /b 1

pushd "%RTL_DIR%"
if errorlevel 1 exit /b 1

call "%VIVADO_BIN%\xvlog.bat" --sv memory\memory.v memory\model_memory_v4_table.v memory\memory_service.v tb\tb_memory_service.v > reports\memory_service_v4\xvlog_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" tb_memory_service -s tb_memory_service_sim > reports\memory_service_v4\xelab_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" tb_memory_service_sim -runall -log reports\memory_service_v4\tb_memory_service_xsim.log > reports\memory_service_v4\xsim_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_memory_service" reports\memory_service_v4\tb_memory_service_xsim.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal -log reports\memory_service_v4\vivado_ooc_console.txt -source scripts\synth_memory_service_v4_ooc.tcl -tclargs "%RTL_DIR%"
if errorlevel 1 set "FAILED=1"

if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
copy /y "reports\memory_service_v4\*" "%RESULT_DIR%\" >nul 2>nul
echo MEMORY_SERVICE_V4_WORK_ROOT=%WORK_ROOT%
if "%FAILED%"=="0" echo MEMORY_SERVICE_V4_ALL_PASS
popd
exit /b %FAILED%
