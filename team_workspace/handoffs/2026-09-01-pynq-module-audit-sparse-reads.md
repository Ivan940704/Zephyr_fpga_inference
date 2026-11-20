# Handoff: PYNQ-Z1 module audit and real sparse parameter reads

- Date: 2026-09-01
- Owner: Codex
- Branch: `codex/pynq-module-audit-sparse-reads`
- Task: `team_workspace/tasks/2026-09-01-pynq-module-audit-sparse-reads.md`
- Detailed report: `docs/PYNQ_Z1_MODULE_AUDIT_AND_SPARSE_READS.md`

## Outcome

All 23 current synthesizable RTL modules were checked against the accepted
PYNQ-Z1 Gate A/B/C criteria:

- 1 isolated module checkpoint passes: `pe_requant_lane` (single lane only).
- 3 current configurations are blocked: `gsu_layer`, `fullband_three_layer`,
  and the default 512 KiB `memory` cache.
- 18 modules have behavioral or structural evidence but remain
  `UNKNOWN/incomplete` for intended-count PYNQ integration.
- `axis_int8_loopback` is a wiring harness, not a production block.
- 0 modules/full system have Gate C evidence.

The audit is retroactive: all earlier hardware task cards predate the checklist
and lack a formal PYNQ-Z1 feasibility section. Existing stored XSim 20/20 remains
valid behavior evidence; no legacy RTL was changed and no new XSim result is
claimed in this checkpoint.

## Main PYNQ findings

- A full legacy `gsu_layer` structurally instantiates 112 concurrent 32x32
  requantizer multipliers. `fullband_three_layer` contains two such GSUs plus 16
  projection requantizers, for 240 concurrent 32x32 multipliers before counting
  hybrid MAC multipliers. This is not an acceptable XC7Z020 baseline; continue
  with the isolated 4-lane local + 1-lane shared time-multiplex PE plan.
- The default `memory` depth is 512 KiB. A 64-bit-wide structural BRAM mapping is
  approximately 128/140 BRAM36 (91.4%), above the 80% review trigger. The largest
  v2 stage is 260,120 bytes and maps to approximately 64 BRAM36 as a single-bank
  64-bit baseline; two equal banks return to approximately 128 BRAM36.
- The raw cache is 64 bits while a weight response is 128 bits. GSU and projection
  parameter responses are 5,792 and 1,120 bits respectively; lowering/unpacking
  and response buffering remain absent.
- `top.v`, global `fsm.v`, full `pe_array.v`, memory service, DMA/block design,
  full-system synthesis/implementation, and board evidence remain absent.

All resource statements above are structural/analytical except the previously
stored `pe_requant_lane` OOC result (475 LUT, 431 FF, 4 DSP, WNS +0.263 ns at a
5 ns constraint). They are not full implementation or board measurements.

## Real `parameters.bin` result

The test reads `upstream/parameters` without changing the dirty nested
repository. It verified:

- blob size 2,193,288 bytes and SHA-256
  `572da396d01fbc20a9ed23f17fbbb0c29e3539fe9f7c3c9eb8c1c2c82f22f894`;
- 12 operators (8 GSU, 4 Linear), 212 operator tensors, and 8 unlowered
  LayerNorm tensors, for 220 gap-free/non-overlapping tensor ranges;
- every tensor dtype/shape byte count and SHA-256;
- all 16 GSU INT8 matrix gate halves are byte-identical;
- 1,802,112 source INT8 weight bytes reduce to 956,096 effective bytes after
  shared-gate deduplication, saving 846,016 duplicate bytes;
- 37,112 / 956,096 effective weights are zero (3.8816% overall). This is not
  used by the current activation-sparsity RTL.

The current blob and v2 image are row-major. A 16-lane word for one active source
has raw lane stride equal to the input width (46..320 bytes), so it is not a
contiguous 16-byte read. The accepted v3 physical order is now:

```text
operator -> matrix -> source_index -> row_tile -> lane
word_index = source_index * row_tiles + row_tile
```

This makes the user's “selected row” a row of the transposed storage image and
one row tile a contiguous 128-bit word. The decision is documented at
`team_workspace/decisions/2026-09-01-sparse-column-packed-weight-layout.md`.

## Real-weight selected-index regression

The dependency-free test covers 20 effective matrices and five deterministic
patterns each (100 comparisons). Raw dense binary matvec and selected packed-word
INT32 accumulation match exactly for every comparison. Of those matrices, 16
are runtime sparse-eligible: 8 recurrent GSU, 4 second-GSU input, and 4
projection matrices. Four first-GSU input matrices are dense feature paths.

For one invocation of each of the 16 eligible matrices:

| Pattern | Selected 128-bit words | Dense words | Reduction |
| --- | ---: | ---: | ---: |
| zero | 0 | 54,304 | 100% |
| 3 active indices per matrix | 645 | 54,304 | 98.8122% |
| approximately 6.25% active | 3,394 | 54,304 | 93.75% |
| approximately 25% active | 13,576 | 54,304 | 75% |
| dense | 54,304 | 54,304 | 0% |

The 6.25% case is 54,304 selected weight bytes versus 868,864 dense bytes. This
is a logical payload result, not actual audio-frame traffic or PYNQ speedup.
Loading a complete stage before compute transfers the same DDR bytes regardless
of spike density; reducing DDR traffic requires active-source on-demand fetch or
an active tile cache.

## Verification commands and actual results

```text
python3 rtl/tests/test_sparse_parameter_reads.py
5/5 PASS

python3 rtl/tests/reference_checks.py
13/13 PASS

python3 -m pytest -q \
  rtl/tests/test_axi_memory_image.py \
  rtl/tests/test_sparse_parameter_reads.py
7/7 PASS

python3 -c '<compare build_report() with stored JSON>'
REPORT_REPRODUCIBLE PASS
```

Generated report:

- `outputs/memory/2026-09-01/sparse_parameter_read_report.json`
- SHA-256:
  `29c5aac781eaf28b678e53e808f17eddd0e095302e17dbcb5da004e7baee4869`

No HDL source was modified. The existing Windows Vivado 2018.3 XSim 20/20 log
was inspected but not rerun. `tb_memory` still lacks a current Vivado 2018.3 run.

## Changed files

- `rtl/tests/test_sparse_parameter_reads.py`
- `outputs/memory/2026-09-01/sparse_parameter_read_report.json`
- `docs/PYNQ_Z1_MODULE_AUDIT_AND_SPARSE_READS.md`
- `docs/memory/MEMORY_INTEGRATION_ANALYSIS.md`
- `team_workspace/tasks/2026-09-01-pynq-module-audit-sparse-reads.md`
- `team_workspace/decisions/2026-09-01-sparse-column-packed-weight-layout.md`
- `team_workspace/handoffs/2026-09-01-pynq-module-audit-sparse-reads.md`
- `PROJECT_STATUS.md`

## Limitations and next checkpoint

- Synthetic binary index patterns use real weights but not real model spike
  traces or normalized feature/state golden vectors.
- Packed bytes are generated/verified in host memory; no v3 image artifact,
  memory-service RTL, AXI transaction, or Vivado resource result was produced.
- The aggregate read table invokes each eligible matrix once and is not a full
  frame schedule for the three subband regions.
- Next, implement the v3 generator and an independent 64-to-128-bit
  selected-source memory-service adapter TB. Then synthesize 256 KiB single-stage
  and smaller ping-pong tile-cache alternatives before fullband integration.
