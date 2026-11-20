@echo off
setlocal EnableExtensions

rem Windows Vivado 2018.3 runner for connected PE Array datapath XSim.
for %%I in ("%~dp0..") do set "PE_ROOT=%%~fI"
if not defined VIVADO_BIN set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "RUN_TCL=%PE_ROOT%\scripts\sim\run_pe_array_datapath_xsim.tcl"
set "RUN_DIR=%TEMP%\zephyr_pe_array_datapath_runner_%RANDOM%_%RANDOM%"

if not exist "%VIVADO%" (
  echo Missing Vivado 2018.3 tool: "%VIVADO%"
  exit /b 1
)
if not exist "%RUN_TCL%" (
  echo Missing XSim runner: "%RUN_TCL%"
  exit /b 1
)

mkdir "%RUN_DIR%" 2>nul
if errorlevel 1 exit /b 1
pushd "%RUN_DIR%"
if errorlevel 1 exit /b 1

call "%VIVADO%" -mode batch -nojournal -log "vivado-xsim.log" ^
  -source "%RUN_TCL%" -tclargs "%PE_ROOT%"
set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" goto :done

findstr /c:"PE_ARRAY_DATAPATH_CONNECTED_XSIM_PASS" "vivado-xsim.log" >nul
if errorlevel 1 (
  echo PE_ARRAY_DATAPATH_CONNECTED_XSIM_PASS_MARKER_MISSING
  set "STATUS=1"
) else (
  echo PE_ARRAY_DATAPATH_CONNECTED_XSIM_PASS
)

:done
echo PE_ARRAY_DATAPATH_XSIM_RUN_DIR=%RUN_DIR%
popd
exit /b %STATUS%
