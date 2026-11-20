@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "RUN_DIR=%TEMP%\zephyr_deepfilter_engine_%RANDOM%_%RANDOM%"
set "REPORT_DIR=%SOURCE_RTL%\reports\deepfilter_engine"
set "FAILED=0"

for %%T in (xvlog.bat xelab.bat xsim.bat) do (
  if not exist "%VIVADO_BIN%\%%T" exit /b 1
)

mkdir "%RUN_DIR%" 2>nul
if errorlevel 1 exit /b 1
pushd "%RUN_DIR%"
if errorlevel 1 exit /b 1

call "%VIVADO_BIN%\xvlog.bat" --relax ^
  "%VIVADO_BIN%\..\data\verilog\src\glbl.v" ^
  "%SOURCE_RTL%\leaf\deepfilter_complex_mac.v" ^
  "%SOURCE_RTL%\integration\sequential_deepfilter_engine.v" ^
  > xvlog-verilog.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xvlog.bat" --sv ^
  "%SOURCE_RTL%\tb\tb_sequential_deepfilter_engine.sv" ^
  > xvlog-tb.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_sequential_deepfilter_engine glbl -L unisims_ver ^
  -s tb_sequential_deepfilter_engine_sim > xelab-console.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_sequential_deepfilter_engine_sim -runall -log xsim.log ^
  > xsim-console.log 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_deepfilter_engine" ^
  xsim.log >nul
if errorlevel 1 set "FAILED=1"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
for %%L in (xvlog-verilog.log xvlog-tb.log xelab.log xelab-console.log ^
  xsim.log xsim-console.log) do (
  if exist "%%L" copy /y "%%L" "%REPORT_DIR%\%%L" >nul
)

if "%FAILED%"=="0" (
  echo DEEPFILTER_ENGINE_XSIM_PASS
) else (
  echo DEEPFILTER_ENGINE_XSIM_FAIL
  for %%L in (xvlog-verilog.log xvlog-tb.log xelab.log xelab-console.log ^
    xsim.log xsim-console.log) do if exist "%%L" type "%%L"
)

echo DEEPFILTER_ENGINE_RUN_DIR=%RUN_DIR%
popd
exit /b %FAILED%
