# Sequential DeepFilter engine checkpoint

Date: 2026-09-06 (Asia/Taipei)

Status: standalone RTL, synthetic two-frame XSim, and 100 MHz OOC synthesis
PASS.  Combined accelerator-top routed OOC timing remains open.

## Runtime contract

`rtl/integration/sequential_deepfilter_engine.v` receives one 512-byte noisy
spectrum packet per frame.  Each 64-bit AXI4-Stream beat packs four bins in
little-endian byte lanes: real at byte `2*n`, imaginary at byte `2*n+1`.
`TKEEP` must be `8'hff` and `TLAST` appears only on beat 63.

The engine keeps the current spectrum plus four completed frames in a circular
BRAM.  Coefficient tap zero multiplies the oldest sample and the final tap
multiplies the current sample, matching PyTorch's left-padded `unfold` order.
Unavailable history is zero:

| Frequency bins | Filter order | Coefficient-store range |
|---:|---:|---:|
| 0..31 | 5 | 0..319 |
| 32..127 | 3 | 320..895 |
| 128..255 | 1 | 896..1151 |

Each term uses signed INT8 spectrum and coefficient real/imaginary parts.  The
complex products accumulate in signed INT32 using `real = sr*cr - si*ci` and
`imag = sr*ci + si*cr`, matching `IntegerDeepFilterReference` in the nested
model repository.

Output is one 256-beat 64-bit AXI4-Stream packet.  Bits 31:0 contain signed
INT32 real and bits 63:32 contain signed INT32 imaginary; `TKEEP=8'hff` and
`TLAST` marks bin 255.  Bin 256/Nyquist remains outside this hardware packet.
The PS/software boundary must dequantize each band using its spectrum scale
times coefficient scale before floating-point ISTFT.

## Verification

`rtl/scripts/Run-DeepFilter-Engine-XSim.cmd` passes 2,573 checks.  Two synthetic
frames use coefficient `1+j` to verify first-frame causal zero padding,
second-frame history, all 2,304 coefficient reads, 512 output values, output
backpressure stability, exact `TLAST`, and malformed-ingress fault latching.
This is arithmetic/protocol evidence; it is not a real-audio quality result.

Standalone Vivado 2018.3 OOC synthesis for `xc7z020clg400-1`:

| Metric | Result |
|---|---:|
| Target period | 10.000 ns |
| Post-synthesis WNS | +2.542 ns |
| Estimated critical delay / Fmax | 7.458 ns / 134.084 MHz |
| LUT / FF | 284 / 96 |
| RAMB36 / RAMB18 | 2 / 0 |
| DSP48E1 | 6 |

The two RAMB36 blocks are the five-frame spectrum store and 256-bin result
store.  The engine completes 576 complex taps per frame.  The intentionally
sequential coefficient interface favors deterministic correctness and low
resource use over peak throughput.

## Combined-top gate

The complete top synthesizes with zero errors at 21,839 LUT, 24,906 FF,
71 RAMB36, 4 RAMB18, and 43 DSP.  Routed OOC implementation uses 21,387 Slice
LUTs and 25,270 registers, has zero routing errors and zero unconstrained
internal endpoints, but WNS is -0.467 ns at 100 MHz.  The failing path is
entirely inside the frozen recurrent-context store.  No bitstream or board
programming is authorized by this checkpoint.
