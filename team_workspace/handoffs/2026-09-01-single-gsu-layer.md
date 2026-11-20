# Handoff: one verified shared-weight GSU layer

- From: Codex
- To: Fullband layer1/layer2/projection integration task
- Branch / commit: requested `codex/single-gsu-layer`; no commit because the
  outer repository still has no initial commit.
- Changed files:
  - `rtl/gsu/gsu_layer.v`
  - `rtl/tb/tb_gsu_layer.v`
  - `rtl/scripts/Run-XSim-Tests.cmd`
  - `rtl/Makefile`
  - `rtl/tests/reference_checks.py`
  - `rtl/README.md`
  - GSU task, interface decision, and this handoff under `team_workspace/`.

## Verified behavior

- Complete shared-weight GSU step: packed input MAC, sparse recurrent MAC,
  independent forget/cell gate requantization and bias, configurable sigmoid,
  persistent cell state, folded-BN requantization, and spike generation.
- Two output tiles and four consecutive frames were checked neuron by neuron.
- Frame observations:

| Frame | Previous active spikes | Dense input reads | Recurrent reads | Parameter reads |
| --- | ---: | ---: | ---: | ---: |
| First zero state | 0 | 10 | 0 | 2 |
| Recurrent sparse | 3 | 10 | 6 | 2 |
| Gate clipping | 4 | 10 | 8 | 2 |
| After state clear | 0 | 10 | 0 | 2 |

- Weight-request, parameter-request, and result backpressure were exercised;
  all payloads stayed stable while stalled.
- Gate saturation and the state-clear path were exercised.
- Windows Vivado 2018.3 XSim regression: PASS, 14/14 testbenches.
- Dependency-free Python reference checks: PASS, 12/12.

## Evidence boundary and limitations

- RTL/testbench evidence only; no synthesis, timing, utilization, or PYNQ-Z1
  board result is claimed.
- Test parameters and weights are deterministic synthetic vectors. Actual
  `parameters.bin` loading remains a responsibility of `memory.v`.
- The RTL is parameterized with fullband layer-1 defaults (64 inputs, 320
  hidden neurons, 16 lanes), while the detailed behavioral test uses a smaller
  5-input/8-hidden/two-tile configuration for exhaustive observability.
- Only the model's shared-weight GSU form is supported.

## Fullband continuation interface

- Instance 1: `INPUT_SIZE=64`, `HIDDEN_SIZE=320`, `INPUT_IS_BINARY=0`.
- Instance 2: `INPUT_SIZE=320`, `HIDDEN_SIZE=320`, `INPUT_IS_BINARY=1`.
- Collect the 20 spike tiles from instance 1 and stream 320 binary elements
  into instance 2.
- Collect instance-2 spikes and use them as the binary 320-element input of the
  64-output fullband projection.
- Preserve separate `hx/cx` state inside the two GSU instances across frames.
