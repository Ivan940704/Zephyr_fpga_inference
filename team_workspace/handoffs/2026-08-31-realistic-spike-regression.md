# Handoff: presentation-scale spike-pattern regression

- From: Codex
- To: Zephyr FPGA sparse-memory and integration tasks
- Branch / commit: requested `codex/realistic-spike-regression`; no commit
  because the outer repository still has no initial commit.
- Changed files:
  - `rtl/tb/tb_sparsity_aware_matvec_realistic.v`
  - `rtl/tests/reference_checks.py`
  - `rtl/README.md`
  - `team_workspace/tasks/2026-08-31-realistic-spike-regression.md`
  - This handoff record.

## Evidence boundary

- Repository fact: model weights and activation ranges exist under `upstream/`.
- Repository fact: no WAV/FLAC audio, NPY/NPZ spike dump, or other exported
  per-frame spike trace was found.
- Analytical assumption: deterministic sparse, clustered, and temporally
  correlated profiles approximate traffic shapes the hardware must tolerate.
- RTL/testbench evidence: results below come from behavioral XSim simulation.
- Vivado synthesis/implementation evidence: not measured.
- PYNQ-Z1 board evidence: not measured.

## Verification

- `python3 rtl/tests/reference_checks.py`: PASS, 11/11.
- Windows Vivado 2018.3 `xvlog`, `xelab`, and `xsim` through
  `rtl/scripts/Run-XSim-Tests.cmd`: PASS, 13/13 testbenches.
- No warning, error, fatal, or fail diagnostic appeared in the final XSim logs.
- The realistic test runs at 320 columns x 320 rows with 16 PE lanes and 20 row
  tiles. It processes 13 frames after only one initial reset.

| Profile | Active | Reads | Dense reads | Saved reads | Cycles |
| --- | ---: | ---: | ---: | ---: | ---: |
| `silent` | 0 | 0 | 6,400 | 6,400 | 366 |
| `scattered_95pct_sparse` | 16 | 320 | 6,400 | 6,080 | 2,217 |
| `cluster_wrap_95pct_sparse` | 16 | 320 | 6,400 | 6,080 | 2,191 |
| `scattered_90pct_sparse` | 32 | 640 | 6,400 | 5,760 | 4,085 |
| `scattered_80pct_sparse` | 64 | 1,280 | 6,400 | 5,120 | 7,800 |
| `scattered_70pct_sparse` | 96 | 1,920 | 6,400 | 4,480 | 11,438 |
| `scattered_50pct_sparse` | 160 | 3,200 | 6,400 | 3,200 | 18,927 |
| `dense_reference_limit` | 320 | 6,400 | 6,400 | 0 | 37,421 |
| `temporal_base_32` | 32 | 640 | 6,400 | 5,760 | 4,060 |
| `temporal_repeat_100pct` | 32 | 640 | 6,400 | 5,760 | 4,029 |
| `temporal_churn_8_of_32` | 32 | 640 | 6,400 | 5,760 | 4,042 |
| `moving_burst_base` | 32 | 640 | 6,400 | 5,760 | 4,025 |
| `moving_burst_shift4` | 32 | 640 | 6,400 | 5,760 | 4,082 |

## Assertions covered

- Every one of the 320 outputs in every frame matched a dense reference.
- DUT and testbench read counters equaled `active_count * 20`.
- Every active `{column, row_tile}` address occurred exactly once.
- No inactive column was requested; no request/result tile was duplicated.
- Request address and result tile/data stayed stable under backpressure.
- Variable memory response delay and result stalls were exercised.
- Temporal checks confirmed 32/32 overlap for repeat, 24/32 for eight-spike
  churn, and 28/32 for a four-column burst shift.

## Limitations and next action

- These profiles are deterministic synthetic stimuli, not measured Zephyr
  spike traces. To validate the real distribution, export layer-specific
  320-bit vectors from PC inference on representative audio and replay them in
  this testbench, preferably through `$readmemh`.
- Cycle counts include the current serial encoder plus deliberately injected
  memory/output stalls. They do not establish RTF, Fmax, or board latency.
- The next performance-focused step is to compare 16-bit and 32-bit-per-cycle
  encoders and a banked weight memory using the same trace/profile suite.
