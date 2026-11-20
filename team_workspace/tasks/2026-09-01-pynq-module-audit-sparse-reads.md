# Task: Audit PYNQ-Z1 module feasibility and real sparse weight reads

- Owner: Codex
- Status: complete
- Branch: `codex/pynq-module-audit-sparse-reads`
- Scope:
  - Apply the accepted PYNQ-Z1 Gate A/B/C checklist to every current
    synthesizable RTL module and identify which modules are not yet qualified.
  - Inspect the current `upstream/parameters/parameters.bin` and manifest without
    modifying the dirty nested repository.
  - Verify with real INT8 weights that selected spike indices reproduce a dense
    binary matrix-vector reference while issuing only selected-column reads.
  - Determine whether the current row-major blob/image supports contiguous
    16-lane reads and record the required consumer-native layout.
- Files expected to change:
  - `rtl/tests/test_sparse_parameter_reads.py`
  - `outputs/memory/2026-09-01/sparse_parameter_read_report.json`
  - `docs/PYNQ_Z1_MODULE_AUDIT_AND_SPARSE_READS.md`
  - `team_workspace/decisions/2026-09-01-sparse-column-packed-weight-layout.md`
  - `team_workspace/handoffs/2026-09-01-pynq-module-audit-sparse-reads.md`
  - `PROJECT_STATUS.md`
- Out of scope:
  - Modifying `upstream/` or changing the trained model.
  - Implementing the v3 image generator or memory-service RTL.
  - Full-system synthesis, implementation, bitstream, or board measurement.

## PYNQ-Z1 feasibility

- Placement: analysis/test runs on host; resulting storage contract targets PL
  memory service backed by PS DDR.
- Target part / clock: `xc7z020clg400-1`; 100 MHz PL/AXI baseline. Existing
  isolated PE lane retains its separately measured 200 MHz target.
- Numeric formats and vector/tensor shapes: manifest-defined INT8 matrices;
  INT8 binary-spike selected weights; INT32 reference accumulation; 16 output
  lanes per packed word.
- Parallel instances / lanes: analysis assumes one shared 16-lane PE consumer;
  final system instance count remains an integration decision.
- Estimated LUT / FF / DSP / BRAM per instance: this task adds no RTL instance.
  Existing module evidence is audited rather than extrapolated as measured
  system utilization.
- Scaled total at the intended instance count: unknown until the PE array,
  memory service, AXI infrastructure, and top-level configuration are fixed;
  this missing total is itself a Gate A finding.
- Local buffer and state bytes, ports, banking: compare current 512 KiB raw
  cache, 256 KiB single-stage baseline, and 16-byte column/tile weight words.
  Banking and cache depth remain unverified by synthesis.
- DDR bytes per frame/audio and required sustained bandwidth: report exact
  selected-word formula and measured test read counts; real spike density and
  sustained DDR bandwidth remain unavailable.
- AXI payload, packet count, DMA/cache-maintenance frequency: current fixed
  baseline is 64-bit AXI data with a missing 64-to-128-bit memory-service
  adapter. Final stage/tile packet schedule remains unknown.
- Estimated cycles/frame, initiation interval, and RTF contribution: compute
  word count is derived; full cycle model, overlap, DMA latency, and RTF are
  unknown.
- Clock domains / CDC: PS/AXI/PL boundary is not integrated; any 100-to-200 MHz
  crossing requires explicit CDC.
- Resource or bandwidth hot spot: BRAM capacity, strided row-major gathers,
  serial spike encoding, parameter-response width, and unscaled PE resources.
- Fallback if the estimate does not fit: column/lane-packed DDR image with a
  smaller tile ping-pong cache; reduce lanes/time-multiplex; keep preprocessing
  on PS/host.
- Evidence level: repository facts + deterministic host tests + existing XSim
  and one existing OOC synthesis report, kept separate.
- Feasibility: `UNKNOWN` for full integration; individual module status will be
  reported as qualified prototype, pass with risks, unknown, or blocked.

## Acceptance checks

- [x] Every current synthesizable RTL module is listed with Gate A/B/C evidence
  and a clear qualification verdict.
- [x] Blob size, hash, tensor ranges, shapes, dtypes, and offsets are checked.
- [x] Real-weight sparse selected-index accumulation exactly matches dense
  binary reference for deterministic zero/sparse/dense patterns.
- [x] Raw row-major contiguity and proposed 16-lane packed-word order are tested.
- [x] Exact logical read reduction is reported without claiming unmeasured DDR
  or board speedup.
- [x] Project status, decision, handoff, test results, and limitations are
  recorded and committed.
