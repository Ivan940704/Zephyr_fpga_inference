# Task: Implement and verify one shared-weight GSU layer

- Owner: Codex
- Status: complete
- Branch: `codex/single-gsu-layer` requested; the outer repository still has no
  initial commit, so a task branch cannot be created yet.
- Repository contract:
  - Fullband layer 1 is 64 inputs to 320 hidden neurons.
  - Fullband layer 2 is 320 binary inputs to 320 hidden neurons.
  - Both cells use `shared_weights=true`: forget and cell gates share input and
    recurrent MAC weights but retain separate requantization and bias values.
  - Hidden spikes (`hx`) and cell state (`cx`) persist across frames as INT8/bit.
  - The physical design target processes 16 output neurons per row tile.
- Scope:
  - Implement a parameterized, stateful, 16-lane shared-weight GSU layer.
  - Buffer one input frame, encode prior hidden spikes once, and reuse those
    indices for sparse recurrent weight reads over all output tiles.
  - Expose ready/valid interfaces for packed input/recurrent weight tiles and
    per-tile integer parameters so a later `memory.v` can supply them.
  - Compose existing hybrid PE, gate postprocess, sigmoid LUT, and state-update
    modules without duplicating their arithmetic.
  - Verify multiple consecutive frames, recurrent sparsity, state persistence,
    state clearing, clipping, and interface backpressure.
- Files expected to change:
  - `rtl/gsu/gsu_layer.v`
  - `rtl/tb/tb_gsu_layer.v`
  - `rtl/scripts/Run-XSim-Tests.cmd`
  - `rtl/Makefile`
  - `rtl/tests/reference_checks.py`
  - `rtl/README.md`
  - `team_workspace/handoffs/2026-09-01-single-gsu-layer.md`
- Out of scope for this checkpoint:
  - Final fullband layer1/layer2/projection top-level integration.
  - Loading actual tensors from `parameters.bin`; `memory.v` owns that mapping.
  - Non-shared-weight GSU variants, subband layers, AXI/DMA, and bitstream.
  - Synthesis, implementation, timing, utilization, and PYNQ-Z1 measurement.
  - Changes inside the dirty `upstream/` nested repository.
- Acceptance checks:
  - [x] Every gate, state, and spike output matches an independent integer model.
  - [x] The first frame performs no recurrent reads when reset `hx` is zero.
  - [x] Later frames perform exactly `active_hx * row_tiles` recurrent reads.
  - [x] State and hidden spikes persist across frames and clear on command.
  - [x] Weight, parameter, input, and result backpressure are exercised safely.
  - [x] Python reference checks and Windows Vivado 2018.3 XSim regression pass.
  - [x] The interface for the following fullband chain is documented.
