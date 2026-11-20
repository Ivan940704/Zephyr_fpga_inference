# Production-v2 32-PE contract checkpoint

- Date: 2026-09-09 (Asia/Taipei)
- Owner: Codex
- Status: Phase 5B verified; Phase 5C requires the next explicit approval
- Branch: `codex/latency-experiment-32pe`

## Decision required

The requested 16-to-32 PE change is an architecture change, not a parameter
edit. The accepted PE baseline fixes exactly sixteen Hybrid MAC lanes, a
sixteen-lane membrane path, sixteen-lane collectors and serializer, and
16-row memory tiles. `rtl/pe_array/baseline/v1/` therefore remains byte-for-
byte read-only. A 32-PE implementation must be developed as `production_v2`
and must not replace or overwrite baseline v1.

The approved first implementation checkpoint is one new formal Verilog-2001
module only:

```text
rtl/pe_array/production_v2/rtl/pe/pe_hybrid_mac_array_32.v
```

It is a structural 32-lane production array around the frozen
`pe_hybrid_mac` leaf. It is not the existing feasibility wrapper, whose
clear/enable/mode controls are common to every lane and cannot implement the
production owner and membrane schedules.

## Phase 5A interface

The module has synchronous `clk` and active-low synchronous `rst_n`, then the
following flattened lane buses:

| Signal | Width | Meaning |
|---|---:|---|
| `acc_clear` | 32 | independent lane clear |
| `acc_enable` | 32 | independent lane command enable |
| `mode` | 64 | two mode bits per lane |
| `operand_a` | 256 | one signed INT8 operand per lane |
| `operand_b` | 256 | one signed INT8 operand per lane |
| `gate_u8` | 256 | one unsigned INT8 gate per lane |
| `spike_enable` | 32 | independent spike gate |
| `direct_value` | 1,024 | one signed INT32 direct value per lane |
| `accumulator` | 1,024 | one signed INT32 accumulator per lane |
| `overflow` | 32 | sticky overflow per lane |

Arithmetic, mode encodings, clear priority, one-cycle command-to-accumulate
latency, and lane II=1 remain identical to the frozen Hybrid MAC leaf. The
module adds no multiplier, requantizer, memory, serializer, or controller.

## Exact v1 incompatibilities discovered

The later production-v2 integration cannot connect to baseline v1 without a
new wrapper and new controller/memory adapters:

1. PE commands and results widen from 16 to 32 lane masks, from 128 to 256
   operand bits, and from 512 to 1,024 accumulator/direct-value bits.
2. Gate and Linear tile masks widen from 16 to 32 and their flattened tags
   widen from 256 to 512 bits.
3. State and weight tiles widen from 128 to 256 bits. The current controller
   derives every neuron index as `tile*16+lane`; production v2 requires
   `tile*32+lane` and a five-bit lane index.
4. Model row-tile counts change from
   `[20,20,4,14,14,5,14,14,12,14,14,8]` to
   `[10,10,2,7,7,3,7,7,6,7,7,4]` for stages 0 through 11.
5. One GSU parameter tile grows from 5,792 to 11,584 bits, or 91 to 181
   64-bit words. One projection parameter tile grows from 1,120 to 2,240
   bits, or 18 to 35 64-bit words. The image generator, generated map,
   memory service response, locality banks, and job-controller extracts all
   require a versioned image-v5 update.
6. A 32-lane Gate/Membrane tile requires eight four-lane groups rather than
   four. The shared four-lane Local RQ Bank, Gate Postprocess, Sigmoid LUT,
   and one Shared RQ Engine remain physically single instances. Internal gate
   group identity therefore grows to three bits; external 16-bit user tags,
   scalar ordering, QBN/Linear demux, and exactly-once semantics do not change.
7. A new 32-lane membrane sequencer, collectors, output serializer, CDF
   sequencer, and PE integration wrapper are required. The serializer remains
   scalar II=1, so doubling MAC lanes does not double downstream scalar
   throughput by itself.
8. The external Zynq PS7 HP and AXI4-Stream boundary remains 64 bits. The
   bandwidth experiment is internal 256-bit tile feeding/prefetch, not a
   claim that the native DDR port has become 128 or 256 bits.

## Checkpoint order after Phase 5A

Only one formal PE checkpoint may be active at a time. Each item stops for
review before the next begins:

1. Phase 5A: 32-lane Hybrid MAC structural array.
2. Phase 5B: image-v5 32-row weight/parameter packing and integer oracle.
3. Phase 5C: 32-row memory-service and job-controller providers.
4. Phase 5D: 32-lane membrane, collectors, serializer, and CDF scheduling.
5. Phase 5E: connected `production_v2` PE wrapper and full sparse top.
6. Phase 5F: 100 MHz then 102 MHz full-top place/route; 104 MHz remains an
   exploratory ceiling unless it gains adequate margin.
7. Phase 6: persistent overlapped DMA and frozen five-file board run.
8. Final validation: after full-Zynq timing and matching BIT/HWH pass, run the
   pinned 100-audio corpus for primary throughput/audio quality and a separate
   fixed-five-plus-file081 hardware-profile pass. The exact fields and gates
   are defined in
   `team_workspace/decisions/2026-09-09-final-100-audio-validation.md`.

Every RTL checkpoint requires a self-checking connected XSim result, exact
hierarchy/resource counts, and timing evidence at its stated boundary. No
BIT/HWH is generated until the complete Zynq design has non-negative WNS/WHS,
clean timing coverage and routing, and no blocking DRC.

## Latency attribution at this checkpoint

This contract adds no RTL and changes no cycle count. Its measured board
latency is therefore `NOT_MEASURED`.

For planning only, the prior file081 profile had 10.484 ms mean PL latency at
100 MHz, including 6.87448 ms of compute and 1.84579 ms of ARM `wait_ps`.
If 70 percent of compute halves with 32 lanes while `wait_ps` remains fixed,
the bounded estimates are:

| Candidate | Analytical mean PL latency | Real-time interpretation |
|---|---:|---|
| 32 PE at 100 MHz | 8.077932 ms | still above the 8 ms hop |
| 32 PE at 102 MHz | 7.955733 ms | mean only; no p99 margin |
| 32 PE at 104 MHz | 7.838234 ms | low-margin OOC clock candidate |
| 32 PE at 125 MHz | 6.831504 ms | not timing-closed in the full design |

These figures are analytical and use a representative historical profile,
not the frozen five-file PYNQ set. They show that 32 PE plus a modest clock
increase is likely necessary but not sufficient: PL LayerNorm removal of the
mailbox dependency, internal feed/prefetch, and overlapped DMA are still
required before claiming sustained real time.

## Phase 5A acceptance checks

- New production RTL is Verilog-2001 `.v`; baseline v1 checksums are unchanged.
- Self-checking XSim covers all four modes, independent lane clear/enable,
  signed boundaries, sticky overflow, simultaneous mixed lane activity, and
  cycle-accurate comparison with the frozen Hybrid MAC behavior.
- Elaborated hierarchy contains exactly 32 `pe_hybrid_mac` instances and no
  other arithmetic/storage leaf.
- OOC synthesis and route are run at 100 and 102 MHz on
  `xc7z020clg400-1`, recording latency, II, LUT, FF, DSP, BRAM, WNS, WHS,
  route status, timing coverage, and DRC.
- The checkpoint stops after its report; no Phase 5B work or baseline
  promotion begins without the next explicit approval.

## Phase 5A verification result

Phase 5A passed its component-level acceptance gate:

- Fresh Vivado 2018.3 XSim: 1,040 cycles, 27,881 accepted lane commands,
  33,280 checked lane results, zero failures, one-cycle command-to-accumulate
  latency, and II=1.
- Fresh 100 MHz OOC post-route: WNS +4.118 ns, internal register-to-register
  WHS +0.051 ns, 3,743 LUT, 2,176 FF, 32 DSP48, zero BRAM, zero routing
  errors, clean timing coverage, and zero DRC errors.
- Fresh 102 MHz OOC post-route: WNS +3.888 ns, internal register-to-register
  WHS +0.051 ns, with the same resource counts and clean gates.
- Vivado preserved exactly 32 `pe_hybrid_mac*` hierarchy references. The
  wildcard suffix accounts only for Vivado's automatic `__1` through `__31`
  reference renaming; each structural lane remains present.
- All-path OOC WHS is -1.226 ns at both frequencies on top-level input-to-
  register paths because this standalone OOC boundary has no physical
  `HD.PARTPIN_LOCS`. This does not invalidate the clean internal hold result,
  but it also means Phase 5A cannot establish full-system hold closure.
- `rtl/pe_array/baseline/v1/SHA256SUMS` remains the authority for the frozen
  baseline and must pass before the checkpoint is committed.

The result proves the independent 32-lane arithmetic leaf array is functionally
and physically feasible at 102 MHz in isolation. It does not prove controller,
memory, serializer, full-Zynq, DMA, board latency, or real-time performance.
Measured frame and board latency remain `NOT_MEASURED`.

## Phase 5B verification result

After explicit approval, Phase 5B added only the versioned image-v5 generator,
artifacts, generated map/tables, and independent integer oracle. It did not
connect or edit the memory service, job controller, production top, or frozen
`baseline/v1` hierarchy.

- `parameters_v5.bin` is 1,056,224 bytes with SHA-256
  `0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a`.
- Stage row-tile counts are exactly
  `[10,10,2,7,7,3,7,7,6,7,7,4]`.
- GSU parameter records are exactly 11,584 bits, 1,448 bytes, or 181 native
  64-bit words. Projection records are exactly 2,240 bits, 280 bytes, or 35
  words. Both have zero record padding.
- Every v5 weight tile equals two corresponding v4 16-row tiles, with zero
  upper lanes when the old tile count is odd. Every parameter field follows
  the same pairing rule and lane 0 remains in the least significant bits.
- The independent oracle passed 7/7 tests, representing 1,802,112 matrix
  source/duplicate values, checking 35,120 parameter values and all 2,040
  global sigmoid bytes. Vivado 2018.3 `xvlog` accepted the generated 14-bit
  parameter-size table and 256-bit readback table.
- v4 image/generator/test/map/table/readback hashes remain unchanged. The
  historical v3/v4 tests still have four pre-existing failures because their
  image headers embed manifest SHA `eb79...`, whereas the current clean nested
  repository manifest is `e561...`; payload semantics are independently
  checked against both current raw tensors and v4 packed artifacts.

The layout cuts exact weight tile request count from 59,756 to 29,990 and
parameter records from 153 to 77. It does not itself reduce measured latency:
the controller still does not consume image-v5, no synthesizable integration
was added, and board/resource results are `NOT_MEASURED`/`NOT_APPLICABLE`.
Phase 5C is now the next review gate and requires explicit approval.
