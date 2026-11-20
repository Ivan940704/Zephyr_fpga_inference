@echo off
setlocal EnableExtensions

rem Windows Vivado 2018.3 runner for the PE Array connected-datapath hierarchy
rem and 200 MHz OOC checkpoint.  Sources are copied away from WSL/UNC paths to
rem a local temporary directory; baseline/v1 is read-only input.
for %%I in ("%~dp0..") do set "SOURCE_PE_ROOT=%%~fI"
if not defined VIVADO_BIN set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "VIVADO=%VIVADO_BIN%\vivado.bat"
set "WORK_ROOT=%TEMP%\zephyr_pe_array_datapath_%RANDOM%_%RANDOM%"
set "WORK_PE_ROOT=%WORK_ROOT%\pe_array"
set "RESULT_DIR=%SOURCE_PE_ROOT%\reports\pe_array_datapath"
set "FAILED=0"
if /i "%~1"=="hierarchy-only" set "OOC_REQUESTED=NO"
if not defined OOC_REQUESTED set "OOC_REQUESTED=YES"

if not exist "%VIVADO%" (
  echo Missing Vivado 2018.3 tool: "%VIVADO%"
  exit /b 1
)
if not exist "%SOURCE_PE_ROOT%\rtl\top\pe_array_datapath.v" (
  echo Missing wrapper: "%SOURCE_PE_ROOT%\rtl\top\pe_array_datapath.v"
  exit /b 1
)

mkdir "%WORK_PE_ROOT%\rtl\top" "%WORK_PE_ROOT%\baseline\v1" "%WORK_PE_ROOT%\constraints" "%WORK_PE_ROOT%\scripts\synth" "%WORK_PE_ROOT%\logs" 2>nul
if errorlevel 1 exit /b 1

xcopy /e /i /y "%SOURCE_PE_ROOT%\baseline\v1\rtl" "%WORK_PE_ROOT%\baseline\v1\rtl" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_PE_ROOT%\rtl\top\pe_array_datapath.v" "%WORK_PE_ROOT%\rtl\top\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_PE_ROOT%\constraints\pe_array_datapath_200mhz.xdc" "%WORK_PE_ROOT%\constraints\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_PE_ROOT%\scripts\synth\check_pe_array_datapath_hierarchy.tcl" "%WORK_PE_ROOT%\scripts\synth\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_PE_ROOT%\scripts\synth\synth_pe_array_datapath_ooc.tcl" "%WORK_PE_ROOT%\scripts\synth\" >nul
if errorlevel 1 exit /b 1

pushd "%WORK_PE_ROOT%"
if errorlevel 1 exit /b 1

echo === PE ARRAY DATAPATH HIERARCHY CHECK ===
call "%VIVADO%" -mode batch -nojournal -log "logs\vivado-hierarchy.log" -source "scripts\synth\check_pe_array_datapath_hierarchy.tcl" -tclargs "."
if errorlevel 1 (
  echo PE_ARRAY_DATAPATH_HIERARCHY_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PE_ARRAY_DATAPATH_HIERARCHY_PASS" "logs\vivado-hierarchy.log" >nul
if errorlevel 1 (
  echo PE_ARRAY_DATAPATH_HIERARCHY_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
echo PE_ARRAY_DATAPATH_HIERARCHY_PASS
if /i "%~1"=="hierarchy-only" goto :copy_results

echo === PE ARRAY DATAPATH 200 MHZ OOC SYNTHESIS ===
call "%VIVADO%" -mode batch -nojournal -log "logs\vivado-ooc.log" -source "scripts\synth\synth_pe_array_datapath_ooc.tcl" -tclargs "."
if errorlevel 1 (
  echo PE_ARRAY_DATAPATH_OOC_ERROR
  set "FAILED=1"
  goto :copy_results
)
findstr /c:"PE_ARRAY_DATAPATH_OOC_PASS" "logs\vivado-ooc.log" >nul
if errorlevel 1 (
  echo PE_ARRAY_DATAPATH_OOC_PASS_MARKER_MISSING
  set "FAILED=1"
  goto :copy_results
)
echo PE_ARRAY_DATAPATH_OOC_PASS

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
copy /y "logs\*.log" "%RESULT_DIR%\" >nul 2>nul
if exist "reports\pe_array_datapath" xcopy /e /i /y "reports\pe_array_datapath" "%RESULT_DIR%" >nul
> "%RESULT_DIR%\run_status.txt" echo evidence=Windows_Vivado_2018.3
>> "%RESULT_DIR%\run_status.txt" echo hierarchy_check_requested=YES
>> "%RESULT_DIR%\run_status.txt" echo connected_ooc_synthesis_requested=%OOC_REQUESTED%
>> "%RESULT_DIR%\run_status.txt" echo implementation_run=OOC_PLACE_AND_ROUTE
>> "%RESULT_DIR%\run_status.txt" echo bitstream=NOT_GENERATED
>> "%RESULT_DIR%\run_status.txt" echo exit_failed=%FAILED%
echo PE_ARRAY_DATAPATH_WORK_ROOT=%WORK_ROOT%
popd

if "%FAILED%"=="0" echo PE_ARRAY_DATAPATH_VIVADO_ALL_PASS
exit /b %FAILED%
