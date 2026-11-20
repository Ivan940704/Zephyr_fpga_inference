# Handoff: PYNQ PS subband preprocessing boundary

- From: Codex
- To: PS software, AXI/DMA, subband RTL, and performance-measurement tasks
- Branch / commit: requested `codex/pynq-ps-subband-preprocessing`; no commit
  because the outer repository has no initial commit.
- Main files:
  - `team_workspace/decisions/2026-09-01-pynq-ps-subband-preprocessing.md`
  - `PROJECT_STATUS.md`
  - `rtl/README.md`
  - `ZEPHYR_FPGA_ESTIMATE.md`
  - `team_workspace/tasks/2026-09-01-pynq-ps-subband-preprocessing.md`
  - This handoff

## Result

- Subband frequency unfold, fullband/noisy feature concatenation, LayerNorm,
  quantization, and packing are assigned to PYNQ-Z1 PS software.
- PL receives already-normalized INT8 vectors with widths 46, 94, or 158 and
  therefore does not include subband LayerNorm RTL.
- The model produces 9 subband vectors and 782 normalized INT8 elements per
  frame: `4 x 46 + 3 x 94 + 2 x 158`.
- Fullband LayerNorm remains on the external PC/host under the earlier boundary
  until a separate decision changes it.
- Existing PL estimates that include LayerNorm are now explicitly marked as
  historical and must not be presented as current PS/PL-partition results.

## Verification performed

- Checked the shape arithmetic: 782 elements/frame.
- Checked the 126-frame payload arithmetic: 98,532 bytes/s before AXI padding,
  descriptors, weights, results, and other traffic.
- Parsed 23 local links in the updated status and estimate documents: 23
  resolved, 0 missing.
- No RTL or XSim test was required or rerun because this checkpoint changes the
  architecture record only; the prior XSim 17/17 result remains the latest RTL
  evidence.
- The dirty `upstream/` nested repository was inspected read-only and not
  modified.

## Required next checkpoint

Build a PS-side reference preprocessing function that matches the PyTorch
subband construction. Freeze the LayerNorm axis, epsilon, affine order,
rounding, saturation, and INT8 scale; export golden vectors for all three input
widths before selecting float32, NEON, or fixed-point optimization.

After correctness is fixed, define frame descriptors and ping-pong buffers,
then measure CPU time, cache maintenance, DMA latency, and PL idle bubbles on
the physical PYNQ-Z1.

