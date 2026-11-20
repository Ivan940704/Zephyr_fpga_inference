@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "RUN_DIR=%TEMP%\zephyr_accelerator_top_step4_%RANDOM%_%RANDOM%"
set "REPORT_DIR=%SOURCE_RTL%\reports\accelerator_top_step4"
set "FAILED=0"

for %%T in (xvlog.bat xelab.bat xsim.bat) do (
  if not exist "%VIVADO_BIN%\%%T" (
    echo Missing Vivado 2018.3 tool: %VIVADO_BIN%\%%T
    exit /b 1
  )
)

mkdir "%RUN_DIR%" 2>nul
if errorlevel 1 exit /b 1
pushd "%RUN_DIR%"
if errorlevel 1 exit /b 1

set "PE=%SOURCE_RTL%\pe_array\baseline\v1\rtl"

call "%VIVADO_BIN%\xvlog.bat" --sv -i "%SOURCE_RTL%" ^
  "%PE%\arithmetic\pe_requant_lane.sv" ^
  "%PE%\arithmetic\pe_local_requant_bank_4lane.sv" ^
  "%PE%\pe\pe_hybrid_mac.sv" ^
  > xvlog-sv.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xvlog.bat" --relax ^
  -i "%SOURCE_RTL%" ^
  "%VIVADO_BIN%\..\data\verilog\src\glbl.v" ^
  "%SOURCE_RTL%\memory\memory.v" ^
  "%SOURCE_RTL%\memory\model_memory_v4_table.v" ^
  "%SOURCE_RTL%\memory\memory_service.v" ^
  "%SOURCE_RTL%\memory\sequential_recurrent_context_store.v" ^
  "%SOURCE_RTL%\memory\sequential_pe_job_controller.v" ^
  "%PE%\nonlinear\pe_sigmoid_lut_255.v" ^
  "%PE%\postprocess\pe_gate_postprocess.v" ^
  "%PE%\pe\pe_membrane_sequencer.v" ^
  "%PE%\stream\pe_output_serializer.v" ^
  "%PE%\stream\pe_shared_requant_engine.v" ^
  "%PE%\index\pe_spike_decision.v" ^
  "%PE%\index\pe_active_index_writer.v" ^
  "%PE%\pe\pe_cdf_sequencer.v" ^
  "%PE%\top\pe_array_datapath.v" ^
  "%SOURCE_RTL%\memory\layernorm_mailbox.v" ^
  "%SOURCE_RTL%\control\fsm.v" ^
  "%SOURCE_RTL%\memory\sequential_v4_pe_memory_subsystem.v" ^
  "%SOURCE_RTL%\integration\layernorm_mailbox_fsm_adapter.v" ^
  "%SOURCE_RTL%\top\accelerator_top.v" ^
  > xvlog-verilog.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xvlog.bat" --sv ^
  -i "%SOURCE_RTL%" ^
  "%SOURCE_RTL%\tb\tb_layernorm_mailbox_fsm_adapter.sv" ^
  > xvlog-tb.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_layernorm_mailbox_fsm_adapter glbl -L unisims_ver ^
  -s tb_layernorm_mailbox_fsm_adapter_sim ^
  > xelab-adapter.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_layernorm_mailbox_fsm_adapter_sim -runall ^
  -log xsim-adapter.log > xsim-adapter-console.log 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_layernorm_mailbox_fsm_adapter" ^
  xsim-adapter.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  accelerator_top glbl -L unisims_ver -s accelerator_top_elab ^
  > xelab-top.log 2>&1
if errorlevel 1 set "FAILED=1"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
for %%L in (xvlog-sv.log xvlog-verilog.log xvlog-tb.log ^
  xelab-adapter.log xsim-adapter.log xsim-adapter-console.log ^
  xelab-top.log) do (
  if exist "%%L" copy /y "%%L" "%REPORT_DIR%\%%L" >nul
)

if "%FAILED%"=="0" (
  echo ACCELERATOR_TOP_STEP4_XSIM_PASS
) else (
  echo ACCELERATOR_TOP_STEP4_XSIM_FAIL
  for %%L in (xvlog-sv.log xvlog-verilog.log xvlog-tb.log ^
    xelab-adapter.log xsim-adapter.log xsim-adapter-console.log ^
    xelab-top.log) do (
      if exist "%%L" (
        echo ===== %%L =====
        type "%%L"
      )
    )
  )
)

echo ACCELERATOR_TOP_STEP4_RUN_DIR=%RUN_DIR%
popd
exit /b %FAILED%
