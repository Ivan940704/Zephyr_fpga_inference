# Decision: Separate parameter reads, LayerNorm mailbox, and external DMA

- Date: 2026-09-01
- Participants: Ivan, Codex
- Status: accepted production architecture baseline; mailbox RTL, implementation,
  driver, and board evidence pending
- Revision: the initial version sent every runtime feature/result through
  DDR-backed AXI DMA. This revision replaces only the per-frame fullband-to-PS-
  to-subband LayerNorm round trip with a GP-mapped PL BRAM mailbox.
- Supersedes: partially supersedes `2026-09-01-axi-interface-partition.md` for
  PL-consumed parameters and the LayerNorm intermediate. It retains AXI4-Lite
  control, external 64-bit AXI4-Stream ingress/egress, native ready/valid
  arithmetic interfaces, and the historical prototype verification evidence.
- Refines:
  - `2026-09-01-sparse-column-packed-weight-layout.md`
  - `2026-09-01-gsu-shared-weight-tile-interface.md`
  - `2026-09-01-pynq-ps-subband-preprocessing.md`
  - `2026-09-01-global-fsm-subband-parallelism.md`

## Context

The imported `rtl/memory/memory.v` is a 64-bit AXI4 AR/R loader plus raw BRAM
cache. The earlier AXI prototype also verified a 64-bit AXI4-Stream weight
loader, but left the production parameter backend unresolved. Treating both
paths as the default would create two owners for weights and two incompatible
cache contracts.

Static PL parameters, the CPU LayerNorm round trip, and external runtime I/O
have different lifetime, size, coherency, and consumer requirements.
Parameters are a versioned DDR image loaded by stage. The LayerNorm dependency
is only 64 bytes PL-to-PS and 782 bytes PS-to-PL per frame, so DDR allocation,
DMA setup, and cache maintenance are avoidable. External ingress/final egress
remain DDR-backed streams.

## Decision

Use these disjoint production paths:

```text
PL-consumed static parameters:
PS DDR -> memory.v custom AXI4 read (AR/R)
       -> parameter BRAM stage/tile cache
       -> memory_service -> native PE interfaces

CPU LayerNorm intermediate (no DDR controller):
PL fullband projection
  -> dual-slot 4 KiB mailbox BRAM
  -> AXI BRAM Controller -> PS M_AXI_GP -> CPU preprocessing/LayerNorm
  -> PS M_AXI_GP -> AXI BRAM Controller
  -> mailbox BRAM -> atomic subband-input commit -> PL

External ingress/final egress:
PS DDR <-> Xilinx AXI DMA <-> 64-bit AXI4-Stream <-> PL

Control/status:
PS -> accelerator 32-bit AXI4-Lite -> PL top/FSM/memory status
PS -> M_AXI_GP -> AXI BRAM Controller -> mailbox data window
PS -> AXI DMA S_AXI_LITE          -> AXI DMA control/status
```

- The parameter path includes PL-consumed weights, bias, requant records, LUT,
  and other static coefficients used by PL operators.
- Float LayerNorm affine/scale data used by PS preprocessing remains in PS and
  is not copied into the PL parameter cache.
- The immutable row-major `parameters.bin` remains the model source of truth.
  Host tooling generates a separate versioned v3 image with physical weight
  order `{operator,matrix,source_index,row_tile,lane}`.
- `memory.v` remains a raw loader. A separate `memory_service` owns stage-table
  lookup, cache tags, 2x64-to-128-bit weight assembly, packed parameter/LUT
  responses, backpressure, and invalid-request handling.
- The first correctness baseline is a provisional 256 KiB single-stage cache
  and one shared PE/memory service. It must pass the PYNQ-Z1 Gate A and
  representative OOC synthesis before it is treated as fitting the board.
- One independent 4 KiB dual-port mailbox BRAM holds two 64-byte fullband-output
  slots and two 782-byte normalized-subband slots. CPU access uses a
  device/uncached GP memory mapping; frame ID, slot ownership, ordering barrier,
  publish/commit, and release make each handoff atomic. Exact relative offsets
  and padding are defined in `docs/memory/MEMORY_DESIGN_GUIDELINES.md`.
- Xilinx AXI DMA does not load the parameter cache or carry the LayerNorm
  intermediate in the first production version. It carries only external
  fullband ingress and final egress. AXI4-Lite never carries tensor payload;
  the mailbox has a separate GP memory-mapped data aperture.
- DDR parameter, external MM2S input, and external S2MM result regions are
  non-overlapping and use explicit PS/DMA/PL ownership plus flush/invalidate.
  The mailbox is not a DDR allocation and has no duplicate DDR source of truth.
- The global FSM waits for stage-load success before starting an operator,
  publishes fullband output only after all 64 bytes are present, and leaves
  `WAIT_PS` only after a complete 782-byte slot is committed with the expected
  frame ID. A partial/error bank or mailbox frame is never visible to compute.

## Consequences

- The earlier AXI-Stream weight loader remains valid prototype evidence and may
  be reused if a future version formally changes the transport, but it is not
  the production source of parameter-cache ownership.
- The existing 64-to-128-bit packing concept is retained at the local cache
  boundary: two adjacent 64-bit parameter words form one 16-lane weight word.
- The mailbox bypasses the DDR controller, so parameter loading and the
  LayerNorm round trip do not contend for DDR. The custom parameter master and
  external AXI DMA may still contend for PS DDR; HP port, interconnect,
  sidebands, reset/CDC, QoS, serialization/concurrency, timeout, and measured
  bandwidth remain Vivado/board-design work.
- The 4 KiB mailbox is structurally about one BRAM36 at 32-bit depth, but the
  asymmetric dual-port mapping and AXI BRAM Controller/interconnect cost remain
  analytical until synthesis. GP MMIO and CPU preprocessing latency require a
  compiled driver microbenchmark and board measurement.
- A full-stage preload does not exploit spike sparsity to reduce DDR bytes.
  Active-source or tile prefetch remains an evidence-driven later option.
- The 512 KiB default cache is not the baseline because its structural estimate
  is about 128/140 BRAM36. The 256 KiB estimate is about 64/140 BRAM36, but both
  are analytical until synthesis.
- Three parallel subband engines/banks remain disabled by default; one 64-bit
  cache port cannot serve three independent 128-bit consumers per cycle.

## Evidence boundary

- Repository/RTL facts support the existing raw loader, native consumer widths,
  source-major layout decision, FSM stage boundary, and independent AXIS
  adapter behavior.
- Current XSim and host regressions do not verify the new connected production
  path, AXI BRAM Controller/mailbox protocol, GP MMIO latency, Xilinx AXI DMA
  IP, HP-port arbitration, CDC, coherency, full implementation, bandwidth,
  RTF, or board behavior.
- The ordered implementation and acceptance gates are defined in
  `docs/memory/MEMORY_DESIGN_GUIDELINES.md`.
