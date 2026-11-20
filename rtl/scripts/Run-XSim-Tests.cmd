@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "XVLOG=C:\Xilinx\Vivado\2018.3\bin\xvlog.bat"
set "XELAB=C:\Xilinx\Vivado\2018.3\bin\xelab.bat"
set "XSIM=C:\Xilinx\Vivado\2018.3\bin\xsim.bat"
set "RESULT_DIR=%SOURCE_RTL%\test-results"
if defined ZEPHYR_XSIM_RESULT_DIR set "RESULT_DIR=%ZEPHYR_XSIM_RESULT_DIR%"
set "WORK_ROOT=%TEMP%\zephyr_xsim_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "FAILED=0"
set "PASSED=0"
set "TOTAL=0"

if not exist "%XVLOG%" (
  echo XSim was not found under C:\Xilinx\Vivado\2018.3\bin.
  exit /b 1
)

mkdir "%RTL_DIR%\leaf" "%RTL_DIR%\gsu" "%RTL_DIR%\linear" "%RTL_DIR%\sparse" "%RTL_DIR%\fullband" "%RTL_DIR%\axi" "%RTL_DIR%\memory" "%RTL_DIR%\control" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" "%RTL_DIR%\logs" "%RTL_DIR%\build" "%WORK_ROOT%\outputs\memory\2026-09-01\v3" 2>nul
if errorlevel 1 (
  echo Failed to create the Windows-native XSim work directory.
  exit /b 1
)

copy /y "%SOURCE_RTL%\leaf\*.v" "%RTL_DIR%\leaf\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\gsu\*.v" "%RTL_DIR%\gsu\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\linear\*.v" "%RTL_DIR%\linear\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\sparse\*.v" "%RTL_DIR%\sparse\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\fullband\*.v" "%RTL_DIR%\fullband\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\axi\*.v" "%RTL_DIR%\axi\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.v" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\memory\*.vh" "%RTL_DIR%\memory\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\control\*.v" "%RTL_DIR%\control\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\tb\*.v" "%RTL_DIR%\tb\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\scripts\xsim_run_all.tcl" "%RTL_DIR%\scripts\" >nul
if errorlevel 1 exit /b 1
copy /y "%SOURCE_RTL%\..\outputs\memory\2026-09-01\v3\parameters_v3.bin" "%WORK_ROOT%\outputs\memory\2026-09-01\v3\" >nul
if errorlevel 1 exit /b 1

if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
> "%RESULT_DIR%\xsim-console.log" echo XSim standalone leaf-module test results
>> "%RESULT_DIR%\xsim-console.log" echo Work directory: %WORK_ROOT%

pushd "%RTL_DIR%"
if errorlevel 1 (
  echo Failed to enter the Windows-native XSim work directory.
  exit /b 1
)

> all.prj echo nosort
for %%F in (leaf\*.v) do >> all.prj echo verilog xil_defaultlib "%%~fF"
for %%F in (gsu\*.v) do >> all.prj echo verilog xil_defaultlib "%%~fF"
for %%F in (linear\*.v) do >> all.prj echo verilog xil_defaultlib "%%~fF"
for %%F in (sparse\*.v) do >> all.prj echo verilog xil_defaultlib "%%~fF"
for %%F in (fullband\*.v) do >> all.prj echo verilog xil_defaultlib "%%~fF"
for %%F in (axi\*.v) do >> all.prj echo verilog xil_defaultlib "%%~fF"
for %%F in (memory\*.v) do >> all.prj echo sv xil_defaultlib "%%~fF"
for %%F in (control\*.v) do >> all.prj echo verilog xil_defaultlib "%%~fF"
for %%F in (tb\tb_*.v) do >> all.prj echo sv xil_defaultlib "%%~fF"

echo === XVLOG compile ===
call "%XVLOG%" --incr --relax -prj all.prj > "logs\xvlog.log" 2>&1
if errorlevel 1 (
  echo XVLOG_ERROR
  >> "%RESULT_DIR%\xsim-console.log" echo XVLOG_ERROR
  type "logs\xvlog.log"
  copy /y "logs\*.log" "%RESULT_DIR%\" >nul
  popd
  exit /b 1
)
findstr /b /c:"ERROR:" "logs\xvlog.log" >nul
if not errorlevel 1 (
  echo XVLOG_ERROR
  >> "%RESULT_DIR%\xsim-console.log" echo XVLOG_ERROR
  type "logs\xvlog.log"
  copy /y "logs\*.log" "%RESULT_DIR%\" >nul
  popd
  exit /b 1
)

rem Keep the test loop inline.  CALL :label cannot reliably scan an LF-only
rem batch file when this runner is launched through a WSL UNC path.
for %%F in (tb\tb_*.v) do (
  set /a TOTAL+=1
  echo === XSIM %%~nF ===

  call "%XELAB%" --relax --debug typical --snapshot "%%~nF_behav" "xil_defaultlib.%%~nF" > "logs\%%~nF-xelab.log" 2>&1
  if errorlevel 1 (
    echo XSIM_ERROR %%~nF: elaboration failed
    >> "%RESULT_DIR%\xsim-console.log" echo XSIM_ERROR %%~nF: elaboration failed
    set "FAILED=1"
  ) else (
    call "%XSIM%" "%%~nF_behav" -tclbatch "scripts/xsim_run_all.tcl" -log "logs\%%~nF-xsim.log" > "logs\%%~nF-console.log" 2>&1
    if errorlevel 1 (
      echo XSIM_ERROR %%~nF: simulation failed
      >> "%RESULT_DIR%\xsim-console.log" echo XSIM_ERROR %%~nF: simulation failed
      set "FAILED=1"
    ) else (
      findstr /c:"PASS %%~nF" "logs\%%~nF-xsim.log" >nul
      if errorlevel 1 (
        echo XSIM_ERROR %%~nF: PASS marker not found
        >> "%RESULT_DIR%\xsim-console.log" echo XSIM_ERROR %%~nF: PASS marker not found
        set "FAILED=1"
      ) else (
        set /a PASSED+=1
        echo XSIM_PASS %%~nF
        >> "%RESULT_DIR%\xsim-console.log" echo XSIM_PASS %%~nF
      )
    )
  )
)

>> "%RESULT_DIR%\xsim-console.log" echo XSIM_SUMMARY passed=%PASSED% total=%TOTAL%
if "%FAILED%"=="0" (
  >> "%RESULT_DIR%\xsim-console.log" echo XSIM_ALL_TESTS_COMPLETED
) else (
  >> "%RESULT_DIR%\xsim-console.log" echo XSIM_ALL_TESTS_FAILED
)

copy /y "logs\*.log" "%RESULT_DIR%\" >nul
type "%RESULT_DIR%\xsim-console.log"
echo XSim temporary work directory: %WORK_ROOT%
popd
exit /b %FAILED%
