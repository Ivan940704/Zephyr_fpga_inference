# Sequential feature dispatcher checkpoint

Date: 2026-09-06 (Asia/Taipei)

Status: RTL and XSim PASS; OOC synthesis completes, but 100 MHz timing is not
closed.

## Scope

`rtl/integration/sequential_feature_dispatcher.v` closes the dense-feature
provider boundary of the frozen Sequential-v4 PE/memory subsystem without
editing any frozen PE or memory source.

- Accept one 64-byte, 64-bit AXI4-Stream fullband packet for the current frame.
- Require eight full `TKEEP=8'hff` beats and `TLAST` only on beat seven.
- Hold the packet until the matching frame completes.
- Serve stage 0 sources 0..63 from that local fullband buffer.
- Map the mailbox adapter's committed 782-byte subband payload as follows:

| Stage | Controller branch | FSM subband | Contexts | Sources/context | Mailbox bytes |
|---:|---:|---:|---:|---:|---:|
| 3 | 1 | 0 | 0..3 | 46 | 0..183 |
| 6 | 2 | 1 | 0..2 | 94 | 184..465 |
| 9 | 3 | 2 | 0..1 | 158 | 466..781 |

The frozen subsystem translates the FSM's subband numbering `0/1/2` to job
controller logical branches `1/2/3`; branch zero is reserved for fullband.

The dispatcher allows only one request in flight, echoes the exact request
tag, holds the response under backpressure, and turns malformed packets,
frame misuse, invalid tuples, mailbox response errors, and unexpected protocol
events into sticky reset-required faults.

`accelerator_top` now gates `start_ready` on a complete fullband packet whose
frame ID matches the global FSM.  A one-shot start arm preserves the FSM's
held-high-start protection.  The dispatcher is connected internally to the
subsystem feature request/response and to the mailbox adapter's subband read
port; the old raw feature-provider and debug subband-read ports are no longer
top-level production boundaries.

## Verification

Command:

```text
rtl/scripts/Run-Accelerator-Top-Feature-XSim.cmd
```

Result:

- `tb_sequential_feature_dispatcher`: PASS, 101 checks and six mapped
  subband reads.  Coverage includes fullband indices 0/17/63, all six subband
  region boundaries, request/response backpressure, frame release, malformed
  `TKEEP`, early `TLAST`, and an invalid stage/branch tuple.
- Existing `tb_layernorm_mailbox_fsm_adapter`: PASS, 782 bytes and five reads.
- `tb_sequential_df_coefficient_store`: PASS, 64 checks and all 1,152
  coefficient bytes.
- `tb_sequential_deepfilter_engine`: PASS, 2,573 checks, 2,304 coefficient
  reads across two frames, causal zero padding/history, and output stalls.
- Complete `accelerator_top` source allowlist elaboration: PASS.

Vivado 2018.3 OOC synthesis for `xc7z020clg400-1` completed with zero errors:

| Metric | Result |
|---|---:|
| Target period | 10.000 ns |
| Post-synthesis WNS | -2.863 ns |
| Estimated critical delay / Fmax | 12.863 ns / 77.742 MHz |
| LUT / FF | 21,839 / 24,906 |
| RAMB36 / RAMB18 | 71 / 4 |
| DSP48E1 | 43 |

The post-synthesis timing gate therefore fails.  Routed OOC implementation
improves WNS to `-0.467 ns` with 21,387 Slice LUTs, 25,270 registers,
71 RAMB36, 4 RAMB18, and 43 DSP.  Routing errors and unconstrained internal
endpoints are zero, but timing still fails.  The routed worst path runs from
`u_pe_memory_subsystem/u_context_store/logical_to_slot_q_reg[4][1]` to that
same frozen context store's `error_code_reg[0]`; it does not enter the feature,
coefficient, or DeepFilter blocks.  This is routed OOC evidence, not a PS7/DMA
block design, bitstream, or board result.

## Remaining production gaps

- AXI4-Lite control registers, AXI DMA, PS7 block design, reset/CDC closure;
- a team decision to close the frozen 100 MHz path or select a lower production
  FCLK, followed by complete BD implementation, bitstream, and board test.
