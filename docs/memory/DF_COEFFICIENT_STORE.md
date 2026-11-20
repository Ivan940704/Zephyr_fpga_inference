# Sequential DeepFilter coefficient-store checkpoint

Date: 2026-09-06 (Asia/Taipei)

Status: RTL, XSim, and standalone 100 MHz OOC synthesis PASS.  The combined
accelerator top still fails its pre-existing 100 MHz timing gate.

## Scope

`rtl/integration/sequential_df_coefficient_store.v` is the checked boundary
between the frozen PE/memory subsystem's DeepFilter projection stream and a
future DeepFilter execution engine.  It does not modify the frozen PE array or
Sequential-v4 memory sources.

The store owns one frame at a time and packs 1,152 signed INT8 coefficients:

| Projection stage | Filter order | Contexts | Bytes/context | Address range |
|---:|---:|---:|---:|---:|
| 5 | 5 | 4 | 80 | 0..319 |
| 8 | 3 | 3 | 192 | 320..895 |
| 11 | 1 | 2 | 128 | 896..1151 |

Within each context the flattening order is
`{component, local_bin, tap}`.  The accepted logical context IDs are `3,5,7,9`
for stage 5, `11,13,15` for stage 8, and `17,19` for stage 11.  Each byte must
arrive in exact index order with `last` asserted only on the final index.

Nine context-complete bits form an atomic frame barrier.  The global FSM's
DeepFilter start is accepted only when all nine bits are set.  Frame mismatch,
invalid identity, index disorder, malformed `last`, premature consumption,
invalid native reads, and lifecycle misuse raise a sticky reset-required
error.  The native read response is held under backpressure.

## Verification

`rtl/scripts/Run-DF-Coefficient-Store-XSim.cmd` passes with 64 checks and all
1,152 coefficients.  Coverage includes every context, first/last addresses,
read-response backpressure, frame release, wrong tags, out-of-order indices,
early `last`, and premature `consume_start`.

Vivado 2018.3 standalone OOC synthesis for `xc7z020clg400-1`:

| Metric | Result |
|---|---:|
| Target period | 10.000 ns |
| Post-synthesis WNS | +3.709 ns |
| Estimated critical delay / Fmax | 6.291 ns / 158.957 MHz |
| LUT / FF | 211 / 84 |
| RAMB36 / RAMB18 | 0 / 1 |
| DSP48E1 | 0 |

The combined `accelerator_top` source allowlist also elaborates and synthesizes
with zero synthesis errors.  It uses 21,585 LUT, 24,809 FF, 69 RAMB36,
4 RAMB18, and 37 DSP.  Its WNS remains -2.863 ns at 100 MHz on the same path
inside the frozen subsystem.  These are post-synthesis results, not
place/route, bitstream, or board evidence.

## Next boundary

`sequential_deepfilter_engine` now owns this boundary, buffers five spectrum
frames, reads the documented addresses, performs complex INT8xINT8-to-INT32
MACs, and drains a frozen 256-beat result packet.  PS control, DMA, reset/CDC,
block-design implementation, and combined timing closure still remain before
bitstream generation or board programming.
