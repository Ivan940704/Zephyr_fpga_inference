@echo off
setlocal EnableExtensions

set "SOURCE_RTL=%~dp0.."
set "SPARSE_RTL=%SOURCE_RTL%\..\sparse_memory_v1\rtl"
set "VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin"
set "RUN_DIR=%TEMP%\zephyr_accelerator_top_feature_%RANDOM%_%RANDOM%"
set "REPORT_DIR=%SOURCE_RTL%\reports\accelerator_top_sparse_timing"
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

call "%VIVADO_BIN%\xvlog.bat" --sv -i "%SOURCE_RTL%" -i "%SPARSE_RTL%" ^
  "%PE%\arithmetic\pe_requant_lane.sv" ^
  "%PE%\arithmetic\pe_local_requant_bank_4lane.sv" ^
  "%PE%\pe\pe_hybrid_mac.sv" ^
  "%SPARSE_RTL%\sparse_memory_service_v1.sv" ^
  "%SPARSE_RTL%\sparse_stage_map_v1.sv" ^
  "%SPARSE_RTL%\sparse_union_planner_v1.sv" ^
  "%SPARSE_RTL%\sparse_recurrent_context_store_v1.sv" ^
  "%SPARSE_RTL%\sequential_v4_sparse_memory_subsystem.sv" ^
  > xvlog-sv.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xvlog.bat" --relax ^
  -i "%SOURCE_RTL%" -i "%SPARSE_RTL%" ^
  -i "%SOURCE_RTL%\experiments\realtime_layernorm\data" ^
  "%VIVADO_BIN%\..\data\verilog\src\glbl.v" ^
  "%SPARSE_RTL%\sparse_memory_dma_v1.v" ^
  "%SPARSE_RTL%\sparse_memory_v4_table_v1.v" ^
  "%SPARSE_RTL%\sparse_recurrent_context_store_core_v1.v" ^
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
  "%SOURCE_RTL%\integration\layernorm_mailbox_fsm_adapter.v" ^
  "%SOURCE_RTL%\integration\sequential_feature_dispatcher.v" ^
  "%SOURCE_RTL%\integration\sequential_df_coefficient_store.v" ^
  "%SOURCE_RTL%\leaf\deepfilter_complex_mac.v" ^
  "%SOURCE_RTL%\integration\sequential_deepfilter_engine.v" ^
  "%SOURCE_RTL%\experiments\realtime_layernorm\layernorm_engine_q12.v" ^
  "%SOURCE_RTL%\experiments\realtime_layernorm\layernorm_parameter_rom_q12.v" ^
  "%SOURCE_RTL%\experiments\realtime_layernorm\realtime_layernorm_coordinator.v" ^
  "%SOURCE_RTL%\top\accelerator_top.v" ^
  "%SOURCE_RTL%\tb\tb_fsm.v" ^
  > xvlog-verilog.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_fsm glbl -L unisims_ver -s tb_fsm_sim ^
  > xelab-fsm.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_fsm_sim -runall -log xsim-fsm.log ^
  > xsim-fsm-console.log 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_fsm" xsim-fsm.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xvlog.bat" --sv ^
  -i "%SOURCE_RTL%" ^
  "%SOURCE_RTL%\tb\tb_layernorm_mailbox_fsm_adapter.sv" ^
  "%SOURCE_RTL%\tb\tb_sequential_feature_dispatcher.sv" ^
  "%SOURCE_RTL%\tb\tb_sequential_df_coefficient_store.sv" ^
  "%SOURCE_RTL%\tb\tb_sequential_deepfilter_engine.sv" ^
  "%SOURCE_RTL%\tb\tb_accelerator_top_timing_cut.sv" ^
  > xvlog-tb.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_sequential_deepfilter_engine glbl -L unisims_ver ^
  -s tb_sequential_deepfilter_engine_sim ^
  > xelab-deepfilter-engine.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_sequential_deepfilter_engine_sim -runall ^
  -log xsim-deepfilter-engine.log ^
  > xsim-deepfilter-engine-console.log 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_deepfilter_engine" ^
  xsim-deepfilter-engine.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_sequential_df_coefficient_store glbl -L unisims_ver ^
  -s tb_sequential_df_coefficient_store_sim ^
  > xelab-df-coefficient-store.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_sequential_df_coefficient_store_sim -runall ^
  -log xsim-df-coefficient-store.log ^
  > xsim-df-coefficient-store-console.log 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_df_coefficient_store" ^
  xsim-df-coefficient-store.log >nul
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_sequential_feature_dispatcher glbl -L unisims_ver ^
  -s tb_sequential_feature_dispatcher_sim ^
  > xelab-feature-dispatcher.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_sequential_feature_dispatcher_sim -runall ^
  -log xsim-feature-dispatcher.log ^
  > xsim-feature-dispatcher-console.log 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_sequential_feature_dispatcher" ^
  xsim-feature-dispatcher.log >nul
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

if "%FAILED%"=="0" call "%VIVADO_BIN%\xelab.bat" ^
  tb_accelerator_top_timing_cut glbl -L unisims_ver ^
  -s tb_accelerator_top_timing_cut_sim ^
  > xelab-top-timing-cut.log 2>&1
if errorlevel 1 set "FAILED=1"

if "%FAILED%"=="0" call "%VIVADO_BIN%\xsim.bat" ^
  tb_accelerator_top_timing_cut_sim -runall ^
  -log xsim-top-timing-cut.log > xsim-top-timing-cut-console.log 2>&1
if errorlevel 1 set "FAILED=1"
if "%FAILED%"=="0" findstr /c:"PASS tb_accelerator_top_timing_cut" ^
  xsim-top-timing-cut.log >nul
if errorlevel 1 set "FAILED=1"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" 2>nul
for %%L in (xvlog-sv.log xvlog-verilog.log xvlog-tb.log ^
  xelab-fsm.log xsim-fsm.log xsim-fsm-console.log ^
  xelab-adapter.log xsim-adapter.log xsim-adapter-console.log ^
  xelab-feature-dispatcher.log xsim-feature-dispatcher.log ^
  xsim-feature-dispatcher-console.log ^
  xelab-df-coefficient-store.log xsim-df-coefficient-store.log ^
  xsim-df-coefficient-store-console.log ^
  xelab-deepfilter-engine.log xsim-deepfilter-engine.log ^
  xsim-deepfilter-engine-console.log ^
  xelab-top-timing-cut.log xsim-top-timing-cut.log ^
  xsim-top-timing-cut-console.log ^
  xelab-top.log) do (
  if exist "%%L" copy /y "%%L" "%REPORT_DIR%\%%L" >nul
)

if "%FAILED%"=="0" (
  echo ACCELERATOR_TOP_FEATURE_XSIM_PASS
) else (
  echo ACCELERATOR_TOP_FEATURE_XSIM_FAIL
  for %%L in (xvlog-sv.log xvlog-verilog.log xvlog-tb.log ^
    xelab-fsm.log xsim-fsm.log xsim-fsm-console.log ^
    xelab-adapter.log xsim-adapter.log xsim-adapter-console.log ^
    xelab-feature-dispatcher.log xsim-feature-dispatcher.log ^
    xsim-feature-dispatcher-console.log ^
    xelab-df-coefficient-store.log xsim-df-coefficient-store.log ^
    xsim-df-coefficient-store-console.log ^
    xelab-deepfilter-engine.log xsim-deepfilter-engine.log ^
    xsim-deepfilter-engine-console.log ^
    xelab-top-timing-cut.log xsim-top-timing-cut.log ^
    xsim-top-timing-cut-console.log ^
    xelab-top.log) do (
      if exist "%%L" (
        echo ===== %%L =====
        type "%%L"
      )
    )
  )
)

echo ACCELERATOR_TOP_FEATURE_RUN_DIR=%RUN_DIR%
popd
exit /b %FAILED%
