# PYNQ-Z1 accelerator profiling image v2

Date: 2026-09-08

Image `0x0004_0002` adds a read-only, non-intrusive per-frame snapshot to the
existing `0x0004_0001` control ABI.  Software accepts both images, but the
profile control/window fails closed unless v2 is loaded.  The profiler observes
existing handshakes and never drives the datapath.

## Control registers

| Offset | Name | Definition |
| ---: | --- | --- |
| `0x0ac` | PROFILE_CONTROL | bit 0 enable; bit 1 one-cycle clear; bit 2 one-cycle manual snapshot |
| `0x0b0` | PROFILE_STATUS | bit 0 enabled; bit 1 snapshot valid; bit 2 frame active; bit 3 serializer busy |
| `0x100..0x3fc` | PROFILE_WINDOW | 192 immutable 32-bit words after serializer busy clears |

PROFILE_CONTROL requires all four byte strobes and rejects any upper bit.  A
normal profile starts on an accepted accelerator START and freezes on DONE.
Any accelerator error seen during the frame invalidates that snapshot.  CLEAR
invalidates the snapshot and zeros all working counters; stale RAM words remain
inaccessible because valid is low.  All working counters are per-frame 32-bit
values.  The unchanged 64-bit window ABI zero-extends every high word, so host
aggregation supplies the unbounded run-level totals.

After DONE, a two-stage serializer writes one of the 192 words per clock into
distributed RAM.  The operation takes 194 clocks (1.94 microseconds at 100 MHz).
Valid is low and busy is high until the final word commits.  The Python reader
polls this state with a bounded timeout before doing its sequence-stability
check.  A new frame admitted before drain completes invalidates the colliding
snapshot rather than stalling or perturbing the accelerator.

## Window layout

| Word indices | Contents |
| --- | --- |
| 0..7 | schema `0x50520001`, flags, frame/owner/end state, sequence, frame cycles and state-cycle sum |
| 8..33 | 13 global-state cycle counters, low word then high word |
| 34..46 | 13 global-state visit counters |
| 48..71 | 12 per-stage load cycle counters |
| 72..95 | 12 per-stage compute cycle counters |
| 96..119 | 12 per-stage stall cycle counters |
| 120..191 | 36 summary counters, low word then high word |

The summary counters cover AXI AR bursts/requested beats, R beats/bytes,
AR/R stalls and maximum outstanding requests; input/output AXIS beats,
backpressure and completed packets; mailbox release/claim/commit/errors;
controller jobs, actual/dense/sparse/dense-equivalent requests, retired/skipped
MACs; sparse actual/saved bytes, bursts, load cycles and diagnostic events;
R-last completions, frame-error cycles and invalid-state cycles.

At 100 MHz, `frame_cycles / 100_000_000` is PL frame latency.  For every valid
snapshot, `frame_cycles == state_cycle_sum == sum(all 13 state cycles)` is a
mandatory conservation check.  Software reads the sequence before and after
the entire window and rejects a torn snapshot.  It also checks the requested
frame ID, schema and valid/enabled status.

## Evidence boundary

`tb_accelerator_profiling_counters` proves enable/clear/error semantics,
the 194-cycle busy-to-valid transition, same-cycle event capture, cycle
conservation, state/stage counters, AXI and stream counters, and exact
retired/skipped MAC arithmetic in XSim.  The
AXI-Lite control test proves the control/status registers and both ends of the
registered window read path.  These are RTL simulation facts, not post-route timing or board
measurements.  Board results require the matching v2 BIT/HWH and raw
`hardware_profile.jsonl` emitted by the runtime.
