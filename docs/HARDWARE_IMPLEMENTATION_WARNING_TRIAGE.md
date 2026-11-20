# Full-design implementation warning triage

Date: 2026-09-07
Evidence baseline: `eb496dd2184a875518428bd5b2a9b76ad39c1a0d`
Vivado: 2018.3, `xc7z020clg400-1`, fully routed

No warning below is suppressed, demoted, or waived. The current post-route
report has 0 DRC Error, 0 DRC Critical Warning, 107 DRC Warning violations,
13 Advisory violations, and 5 methodology Warnings. The block-design log
separately retains the PS7 DDR preset critical warnings described below. The
final standard timing report closed at `+0.301 ns`, while the 250 ps
engineering-guardband view also passed at `+0.051 ns`.

| Class | Count | Owner / origin | Assessment and required action |
| --- | ---: | --- | --- |
| `DPIP-1` | 43 | PE hybrid MAC and inferred DSP arithmetic | Performance/power pipeline advice, not a functional DRC. Preserve current cycle ABI for this checkpoint. Any new DSP stage requires matching scheduler and bit-exact latency updates; reassess if the path enters the setup top 20. |
| `DPOP-1` | 1 | remaining inferred DSP arithmetic | The former planned-byte DSP path is now explicitly registered and no longer appears in the setup top paths. The remaining advice is non-blocking; any additional stage still requires matching scheduler and bit-exact latency updates. |
| `DPOP-2` | 20 | PE hybrid MAC | DSP MREG advice. Same latency/bit-exact owner as `DPIP-1`; no automatic fix or waiver. |
| `REQP-1839` / `REQP-1840` | 20 / 20 shown | Xilinx AXI DMA / AXI4-to-AXI3 interconnect FIFO RAMB control | Vivado caps both displayed rule classes and emits two `CHECK-3` notices. Generated FIFO async-reset controls are not fully covered by default STA. Keep AXI infrastructure out of software reset, require DMA Halted+Idle before recovery, and rerun DRC after reset-domain separation. Physical-board DMA stress/reset testing remains required. |
| `RTSTAT-10` | 1 | generated HP interconnect FIFO status nets | 25 optimized/no-load internal nets, not an unrouted user interface. Confirm route-status routing errors stay zero. |
| `LUTAR-1` methodology | 5 | HP0..HP3 AXI4-to-AXI3 converter FIFOs | Generated FIFO reset logic drives async preset/clear. System-only infrastructure reset and DMA-idle protocol reduce software-reset exposure, but board reset/DMA stress is still mandatory. |
| `REQP-24`, `REQP-165`, `REQP-181` | 13 advisory | inferred RAM/DSP configurations | Advisory-only. Retain for provenance and revisit with any memory/DSP microarchitecture change. |
| `PSU-1` / `PSU-2` DDR DQS | repeated in BD log | installed PYNQ-Z1 PS7 board preset (`-0.009`, `-0.033`) | Not a PL post-route DRC and not accepted as board proof. Confirm the board preset/board revision, then run destructive-free DDR memory and DMA stress before inference. A failure blocks deployment. |

## Current decision

The warnings do not add a pre-bitstream blocker; the `+0.250 ns` setup
engineering-margin gate now passes. The rerun after reset-domain separation
confirms that generated AXI reset warnings remain; keeping that
infrastructure on the system reset and requiring Halted+Idle before asserting
the custom-datapath reset mitigates software exposure but does not eliminate
the generated structures. Board DMA/reset stress remains mandatory.
