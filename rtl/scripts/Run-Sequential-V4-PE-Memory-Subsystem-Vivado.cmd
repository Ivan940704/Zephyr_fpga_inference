@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "WORK_ROOT=%TEMP%\zephyr_sequential_v4_subsystem_%RANDOM%_%RANDOM%"
set "RTL_DIR=%WORK_ROOT%\rtl"
set "RESULT_DIR=%SOURCE_RTL%\reports\sequential_v4_pe_memory_subsystem"
set "FAILED=0"
set "OOC_ONLY=0"
set "SIM_ONLY=0"
if /i "%~1"=="ooc-only" set "OOC_ONLY=1"
if /i "%~1"=="sim-only" set "SIM_ONLY=1"

for %%T in (xvlog.bat xelab.bat xsim.bat vivado.bat) do (
  if not exist "%VIVADO_BIN%\%%T" (
    echo Missing Vivado 2018.3 tool: %VIVADO_BIN%\%%T
    exit /b 1
  )
)

mkdir "%RTL_DIR%\memory" "%RTL_DIR%\control" "%RTL_DIR%\tb" "%RTL_DIR%\scripts" ^
  "%RTL_DIR%\reports\sequential_v4_pe_memory_subsystem" ^
  "%RTL_DIR%\build" 2>nul
if errorlevel 1 exit /b 1

copy /y "%SOURCE_RTL%\memory\memory.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\model_memory_v4_table.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\model_memory_v4_map.vh" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\memory_service.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\sequential_recurrent_context_store.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\sequential_pe_job_controller.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\sequential_v4_pe_memory_subsystem.v" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\memory\sequential_v4_pe_memory_subsystem_100mhz.xdc" "%RTL_DIR%\memory\" >nul
copy /y "%SOURCE_RTL%\control\fsm.v" "%RTL_DIR%\control\" >nul
copy /y "%SOURCE_RTL%\tb\tb_sequential_v4_pe_memory_subsystem.sv" "%RTL_DIR%\tb\" >nul
copy /y "%SOURCE_RTL%\tb\tb_sequential_v4_pe_memory_subsystem_fsm.sv" "%RTL_DIR%\tb\" >nul
copy /y "%SOURCE_RTL%\tb\sequential_v4_stage0_two_frame_state.hex" "%RTL_DIR%\tb\" >nul
copy /y "%SOURCE_RTL%\scripts\check_sequential_v4_pe_memory_subsystem_hierarchy.tcl" "%RTL_DIR%\scripts\" >nul
copy /y "%SOURCE_RTL%\scripts\synth_sequential_v4_pe_memory_subsystem_ooc.tcl" "%RTL_DIR%\scripts\" >nul
copy /y "%SOURCE_RTL%\..\outputs\memory\2026-09-03\v4\parameters_v4.bin" "%RTL_DIR%\" >nul
if errorlevel 1 exit /b 1

xcopy /e /i /y "%SOURCE_RTL%\pe_array\baseline\v1\rtl" ^
  "%RTL_DIR%\pe_array\baseline\v1\rtl" >nul
if errorlevel 1 exit /b 1

pushd "%RTL_DIR%"
if errorlevel 1 exit /b 1

set "PE=pe_array\baseline\v1\rtl"
if "%OOC_ONLY%"=="1" goto :run_ooc
call "%VIVADO_BIN%\xvlog.bat" --sv -i . ^
  "%PE%\arithmetic\pe_requant_lane.sv" ^
  "%PE%\arithmetic\pe_local_requant_bank_4lane.sv" ^
  "%PE%\pe\pe_hybrid_mac.sv" ^
  > reports\sequential_v4_pe_memory_subsystem\xvlog_sv_console.txt 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xvlog.bat" --relax -i . ^
  "%VIVADO_BIN%\..\data\verilog\src\glbl.v" ^
  memory\memory.v ^
  memory\model_memory_v4_table.v ^
  memory\memory_service.v ^
  memory\sequential_recurrent_context_store.v ^
  memory\sequential_pe_job_controller.v ^
  "%PE%\nonlinear\pe_sigmoid_lut_255.v" ^
  "%PE%\postprocess\pe_gate_postprocess.v" ^
  "%PE%\pe\pe_membrane_sequencer.v" ^
  "%PE%\stream\pe_output_serializer.v" ^
  "%PE%\stream\pe_shared_requant_engine.v" ^
  "%PE%\index\pe_spike_decision.v" ^
  "%PE%\index\pe_active_index_writer.v" ^
  "%PE%\pe\pe_cdf_sequencer.v" ^
  "%PE%\top\pe_array_datapath.v" ^
  control\fsm.v ^
  memory\sequential_v4_pe_memory_subsystem.v ^
  > reports\sequential_v4_pe_memory_subsystem\xvlog_console.txt 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xvlog.bat" --sv -i . ^
  tb\tb_sequential_v4_pe_memory_subsystem.sv ^
  tb\tb_sequential_v4_pe_memory_subsystem_fsm.sv ^
  > reports\sequential_v4_pe_memory_subsystem\xvlog_tb_console.txt 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_sequential_v4_pe_memory_subsystem glbl -L unisims_ver ^
  -s tb_sequential_v4_subsystem_sim ^
  > reports\sequential_v4_pe_memory_subsystem\xelab_console.txt 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_sequential_v4_subsystem_sim -runall ^
  -log reports\sequential_v4_pe_memory_subsystem\tb_subsystem_xsim.log ^
  > reports\sequential_v4_pe_memory_subsystem\xsim_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_v4_pe_memory_subsystem" ^
  reports\sequential_v4_pe_memory_subsystem\tb_subsystem_xsim.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_sequential_v4_pe_memory_subsystem_fsm glbl -L unisims_ver ^
  -s tb_sequential_v4_subsystem_fsm_sim ^
  > reports\sequential_v4_pe_memory_subsystem\xelab_fsm_console.txt 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_sequential_v4_subsystem_fsm_sim -runall ^
  -log reports\sequential_v4_pe_memory_subsystem\tb_subsystem_fsm_xsim.log ^
  > reports\sequential_v4_pe_memory_subsystem\xsim_fsm_console.txt 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_v4_pe_memory_subsystem_fsm" ^
  reports\sequential_v4_pe_memory_subsystem\tb_subsystem_fsm_xsim.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log reports\sequential_v4_pe_memory_subsystem\vivado_hierarchy_console.txt ^
  -source scripts\check_sequential_v4_pe_memory_subsystem_hierarchy.tcl ^
  -tclargs "%RTL_DIR%"
if errorlevel 1 set "FAILED=1"
if "%SIM_ONLY%"=="1" goto :copy_results

:run_ooc
if "%FAILED%"=="0" call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal ^
  -log reports\sequential_v4_pe_memory_subsystem\vivado_ooc_console.txt ^
  -source scripts\synth_sequential_v4_pe_memory_subsystem_ooc.tcl ^
  -tclargs "%RTL_DIR%"
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"timing_met=1" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"ramb36_primitives=68" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"ramb18_primitives=2" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"dsp48_primitives=37" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"resources_below_80_percent=1" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"routing_errors_zero=1" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"unconstrained_internal_endpoints_zero=1" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"clockless_registers_zero=1" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"combinational_loops_zero=1" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /x /c:"latch_loops_zero=1" ^
  reports\sequential_v4_pe_memory_subsystem\metrics_post_route.txt >nul
if errorlevel 1 set "FAILED=1"

:copy_results
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"
copy /y "reports\sequential_v4_pe_memory_subsystem\*" "%RESULT_DIR%\" >nul 2>nul
echo SEQUENTIAL_V4_SUBSYSTEM_WORK_ROOT=%WORK_ROOT%
if "%FAILED%"=="0" echo SEQUENTIAL_V4_SUBSYSTEM_ALL_PASS
popd
exit /b %FAILED%
