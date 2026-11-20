@echo off
setlocal EnableExtensions

for %%I in ("%~dp0..\..") do set "SOURCE_REPO_ROOT=%%~fI"
if not defined VIVADO_BIN set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "WORK_ROOT=%TEMP%\zephyr_realtime_dispatch_%RANDOM%_%RANDOM%"
set "FAILED=0"

if not exist "%VIVADO%" exit /b 1
mkdir "%WORK_ROOT%\rtl\experiments\realtime_layernorm\tb" 2>nul
mkdir "%WORK_ROOT%\rtl\experiments\realtime_layernorm\data" 2>nul
mkdir "%WORK_ROOT%\rtl\experiments\realtime_layernorm\scripts" 2>nul
mkdir "%WORK_ROOT%\rtl\integration" 2>nul
mkdir "%WORK_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim" 2>nul
mkdir "%WORK_ROOT%\logs" 2>nul
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\*.v" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\" >nul
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\tb\tb_realtime_layernorm_dispatch_path.v" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\tb\" >nul
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\tb\realtime_layernorm_coordinator_vectors.txt" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\tb\" >nul
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\data\*" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\data\" >nul
copy /y "%SOURCE_REPO_ROOT%\rtl\experiments\realtime_layernorm\scripts\run_realtime_layernorm_dispatch_path_xsim.tcl" "%WORK_ROOT%\rtl\experiments\realtime_layernorm\scripts\" >nul
copy /y "%SOURCE_REPO_ROOT%\rtl\integration\sequential_feature_dispatcher.v" "%WORK_ROOT%\rtl\integration\" >nul

pushd "%WORK_ROOT%"
call "%VIVADO%" -mode batch -nojournal -log "logs\xsim.log" -source "rtl\experiments\realtime_layernorm\scripts\run_realtime_layernorm_dispatch_path_xsim.tcl" -tclargs "%WORK_ROOT%"
if errorlevel 1 set "FAILED=1"
findstr /c:"REALTIME_DISPATCH_PATH_XSIM_GATE_PASS" "logs\xsim.log" >nul
if errorlevel 1 set "FAILED=1"

if not exist "%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim" mkdir "%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim"
copy /y "logs\xsim.log" "%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim\xsim.log" >nul 2>nul
> "%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim\run_status.txt" echo evidence=Windows_Vivado_2018.3
>> "%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim\run_status.txt" echo scope=coordinator_to_production_dispatcher
>> "%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim\run_status.txt" echo exit_failed=%FAILED%
>> "%SOURCE_REPO_ROOT%\rtl\reports\realtime_layernorm_dispatch_path_xsim\run_status.txt" echo work_root=%WORK_ROOT%
echo REALTIME_DISPATCH_PATH_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo REALTIME_DISPATCH_PATH_XSIM_ALL_PASS
exit /b %FAILED%
