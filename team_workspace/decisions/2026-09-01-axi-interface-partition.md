# Decision: AXI interface partition for PYNQ-Z1

- Date: 2026-09-01
- Participants: Ivan, Codex
- Status: accepted for the interface prototype
- Production refinement: the later
  `2026-09-01-parameter-and-runtime-data-transport-partition.md` partially
  supersedes this decision for PL-consumed weights/parameters and the CPU
  LayerNorm intermediate. The prototype verification below remains historical
  evidence; 32-bit AXI4-Lite remains the control boundary and 64-bit
  AXI4-Stream remains the external fullband-ingress/final-egress boundary.
- Context:
  - PYNQ PS software must exchange control, normalized features, fullband
    results, subband inputs, weights, parameters, and final results with PL.
  - Existing GSU, projection, weight, parameter, and result ports already use
    ready/valid semantics.
  - PYNQ-Z1 resources are limited, so a complete AXI endpoint inside every PE
    would add unnecessary control and interconnect cost.
- Decision:
  - Use a 32-bit AXI4-Lite slave at the PL top-level for low-bandwidth control
    and status registers.
  - Use 64-bit AXI4-Stream at external PS/DMA-facing ingress/egress boundaries.
    INT8 data is
    packed in increasing byte-lane order; `TKEEP` marks valid bytes and `TLAST`
    terminates a logical packet/vector.  This prototype scope included a stream
    weight-loader experiment; the production stream scope is later narrowed to
    external fullband input and final/DeepFilter output.
  - Carry the 64-byte fullband projection and 782-byte normalized-subband
    LayerNorm round trip through a separate 4 KiB dual-port BRAM mailbox,
    accessed by the CPU through PS `M_AXI_GP` and an AXI BRAM Controller. This
    path has slot/frame ownership and atomic commit, does not use DDR/DMA, and
    does not place payload in AXI4-Lite registers.
  - Repack two 64-bit weight beats into one 128-bit word for the current
    16-lane PE/weight-buffer interface.  The production parameter path retains
    this packing concept at the raw-cache boundary rather than on runtime AXIS.
  - Keep arithmetic engines on their existing lightweight native ready/valid
    interfaces.  AXI adapters belong at GSU/projection/memory/top boundaries,
    not inside each PE.
  - Use Xilinx AXI DMA and Zynq PS/HP interconnect in the later Vivado block
    design rather than implementing a custom DDR AXI master in this checkpoint.
    This checkpoint limitation is superseded for the production parameter path;
    it remains true for the external ingress/final-egress DMA path.
- Verified in this checkpoint:
  - AXI4-Stream ingress/native/egress loopback passed 325 bytes across seven
    packets with source gaps, 20 sink-stall cycles, partial/non-contiguous
    `TKEEP`, `TLAST`, reset flushing, and malformed zero-keep detection.
  - The weight loader repacked five pairs of 64-bit beats into five 128-bit
    words, honored output backpressure, wrote the inactive ping-pong bank, and
    detected early `TLAST` and partial `TKEEP` errors.
  - AXI4-Lite passed seven writes and nine reads, independent AW/W arrival,
    `WSTRB`, B/R backpressure, one-cycle control pulses, sticky status, IRQ,
    and reset with a partial transaction.
- Consequences:
  - The first egress adapter is intentionally resource-light and inserts a
    bubble while a completed beat is outstanding.  A FIFO/skid-buffer version
    is needed if full one-beat-per-cycle throughput becomes necessary.
  - The AXI4-Lite prototype accepts one outstanding write and one outstanding
    read; registers are word-aligned and unmapped locations return zero/OKAY.
  - Actual AXI BRAM Controller/mailbox integration, GP MMIO latency, AXI DMA IP,
    address mapping, DDR cache coherency, interrupts, CDC, synthesis, timing,
    and PYNQ-Z1 board transfer remain unverified.
- Supersedes: none
