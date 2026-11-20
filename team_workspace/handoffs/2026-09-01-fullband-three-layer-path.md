# Handoff: fullband GSU1 -> GSU2 -> projection prototype

- From: Codex
- To: Weight-memory loader and full-size verification tasks
- Branch / commit: requested `codex/fullband-three-layer-path`; no commit
  because the outer repository has no initial commit.
- Main files:
  - `rtl/leaf/linear_postprocess.v`
  - `rtl/linear/linear_projection.v`
  - `rtl/fullband/fullband_three_layer.v`
  - `rtl/tb/tb_linear_postprocess.v`
  - `rtl/tb/tb_linear_projection.v`
  - `rtl/tb/tb_fullband_three_layer.v`
  - Updated runners, references, README, task, and this handoff.

## RTL behavior verified

- The controller executes layer 1, layer 2, and projection strictly in order.
- Layer-1 and layer-2 spike vectors use separate buffers.
- The two GSU instances preserve independent recurrent hx/cx state.
- Layer 1 uses dense INT8 input reads.
- Layer 2 skips zero binary input columns and separately skips inactive
  recurrent columns.
- Projection reads only active layer-2 spike columns and applies INT32 bias,
  integer requantization, guard shift, and symmetric INT8 saturation.
- All engines share a ready/valid memory interface tagged with layer ID.

## Reduced-dimension integration observations

| Frame | L1 previous/out active | L2 previous/out active | L1 reads input+rec | L2 reads input+rec | Projection reads |
| --- | ---: | ---: | ---: | ---: | ---: |
| Frame one | 0 / 2 | 0 / 2 | 6 + 0 | 4 + 0 | 4 |
| Frame two | 2 / 2 | 2 / 2 | 6 + 4 | 4 + 4 | 4 |
| Extreme input | 2 / 0 | 2 / 3 | 6 + 4 | 0 + 4 | 6 |
| After clear | 0 / 2 | 0 / 2 | 6 + 0 | 4 + 0 | 4 |

Every final projection output matched the independent three-layer integer
reference. Weight/parameter/result backpressure and layer ordering checks also
passed.

## Verification

- Windows Vivado 2018.3 XSim: PASS, 17/17 testbenches.
- Dependency-free Python reference: PASS, 13/13.
- No compile, elaboration, warning, fatal, or fail diagnostics in the final
  XSim logs.

## Not yet verified

- The integration test is intentionally reduced-dimension. Fullband defaults
  are 64 -> 320 -> 320 -> 64 with 16 lanes, but this exact configuration has
  not been simulated or synthesized.
- The test uses deterministic synthetic weights and integer parameters, not
  tensors loaded from `upstream/parameters/parameters.bin`.
- No `memory.v`, manifest-offset loader, BRAM banking, AXI/DMA, timing report,
  utilization report, bitstream, or PYNQ-Z1 result exists yet.
- PC LayerNorm and host/PL transfer remain outside this RTL block.

## Recommended next checkpoint

Implement `memory.v` tensor mapping for the three fullband operators, export a
small set of real PC-model frame vectors, then run full-size XSim against those
actual weights before synthesis.
