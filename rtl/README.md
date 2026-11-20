# Sparse-memory accelerator integration RTL and retained prototypes

The current production top is `top/accelerator_top.v` with
`../sparse_memory_v1/rtl/sequential_v4_sparse_memory_subsystem.sv`. It connects
the sparse planner/scatter loader, one 256 KiB stage cache, recurrent
state/active-list storage, the sequential job controller, and the frozen PE
datapath. Dense mode loads complete stages; sparse mode uses context unions to
reduce eligible weight bytes while retaining mandatory matrices and parameter
records.

The top also connects the 4 KiB LayerNorm mailbox, feature dispatcher,
coefficient store, sequential DeepFilter engine, and final-result stream. The
remaining system boundary is the PS7/AXI control/DMA/CDC block design and board
software. Start from `docs/memory/SPARSE_ACCELERATOR_TOP_INTEGRATION.md` and
the production compile allowlist. The legacy dense subsystem and superseded
parameter-memory ping-pong line remain excluded provenance.

## Fixed boundary

- STFT, ISTFT, and the fullband LayerNorm currently remain on the external
  PC/host side.
- Subband frequency unfold, fullband/noisy feature concatenation, subband
  LayerNorm, and INT8 packing run as software on the PYNQ-Z1 PS CPU.
- The PL RTL input boundary is already-normalized INT8 feature data: 64 values
  for fullband layer 1, or 46/94/158 values for a subband GSU input vector.
- The production PS LayerNorm round trip is specified as a GP-mapped 4 KiB
  dual-port mailbox BRAM; external ingress/final egress retain AXI DMA. Neither
  the AXI BRAM Controller/driver path nor the LayerNorm bit-exact software
  contract has been implemented or benchmarked; the mailbox RTL itself is now
  implemented and verified standalone.
- Neural weights, activations, and recurrent state are INT8.
- MAC and bias accumulation are INT32.
- Requantization uses a signed integer multiplier followed by the Python
  reference's sign-symmetric round-to-nearest right shift.
- Saturation range is `[-127, 127]`.
- DeepFilter operands are INT8 complex values with INT32 real/imaginary sums.

## Modules

| Module | Unit-test purpose |
| --- | --- |
| `signed_round_shift.v` | Positive, negative, tie, zero-shift behavior |
| `saturate_int8.v` | INT8 boundary and clipping behavior |
| `integer_requantizer.v` | Signed multiplier/right-shift behavior |
| `linear_postprocess.v` | Linear accumulator requantization, bias, guard shift, and INT8 clipping |
| `hybrid_pe.v` | Dense, spike, gate-state, and direct accumulation modes |
| `sigmoid_lut.v` | Signed input-to-0..254 address mapping and configuration |
| `gsu_gate_postprocess.v` | Dual-path GSU requantization, bias, guard shift, saturation |
| `gsu_state_update.v` | GSU state interpolation, folded-BN requantization, spike output |
| `spike_indexer.v` | Sparse/dense/zero vectors and ready/valid backpressure |
| `deepfilter_complex_mac.v` | Complex orders 1, 3, and 5 arithmetic |
| `output_serializer.v` | Lane ordering, `last`, and backpressure |
| `ping_pong_weight_buffer.v` | Legacy AXI-stream prototype only; inactive-bank load, active-bank read, and bank swap |
| `gsu/gsu_layer.v` | Stateful shared-weight GSU layer with dense/binary input MAC, sparse recurrent MAC, two gates, sigmoid, state update, and 16-neuron result tiles |
| `linear/linear_projection.v` | Binary sparse matrix-vector projection plus per-output INT8 requantization |
| `sparse/sparsity_aware_matvec.v` | Encode active spikes, buffer indices, request only selected weight columns, and accumulate row tiles |
| `fullband/fullband_three_layer.v` | Sequential fullband GSU1 -> GSU2 -> projection controller with shared layer-tagged memory interfaces |
| `axi/axis_int8_ingress.v` | Unpack 64-bit AXI4-Stream beats into byte-wide native ready/valid data while preserving `TKEEP`/`TLAST` |
| `axi/axis_int8_egress.v` | Pack byte-wide native ready/valid data into 64-bit AXI4-Stream beats |
| `axi/axis_int8_loopback.v` | End-to-end AXI ingress -> native link -> AXI egress wiring proof |
| `axi/axis_weight_loader.v` | Repack two 64-bit AXI beats into one 128-bit, 16-lane weight-buffer word |
| `axi/axi_lite_control.v` | 32-bit AXI4-Lite control/status registers with independent AW/W capture |
| `../sparse_memory_v1/rtl/sparse_memory_dma_v1.v` | One-outstanding AXI4 read DMA plus scatter-copy support into a single 256 KiB cache |
| `../sparse_memory_v1/rtl/sparse_memory_service_v1.sv` | Dense/sparse stage loading, planner coordination, mandatory residency, traffic diagnostics, LUT stream, and reset-only fatal errors |
| `../sparse_memory_v1/rtl/sparse_union_planner_v1.sv` | Build per-stage source unions from the required recurrent contexts |
| `../sparse_memory_v1/rtl/sparse_recurrent_context_store_v1.sv` | Planner/controller arbitration over persistent recurrent states and active lists |
| `../sparse_memory_v1/rtl/sequential_v4_sparse_memory_subsystem.sv` | Production sparse memory, context store, controller, frozen PE, and diagnostics wrapper |
| `memory/layernorm_mailbox.v` | 4 KiB true-dual-port dual-slot 64-byte FB / 782-byte SB mailbox with frame ownership and atomic commit |
| `memory/sequential_pe_job_controller.v` | Row-tile GSU/projection scheduler with compute-side sparsity and a 512-bit matrix-0 snapshot |
| `memory/sequential_v4_pe_memory_subsystem.v` | Legacy dense production provenance; excluded from the active sparse compile |
| `memory/model_memory_v3_map.vh` | Generated v3 image/version, stage offsets and ABI constants |
| `memory/model_memory_v3_table.v` | Historical generated v3 12-stage address/shape table |
| `memory/model_memory_map.vh` | Generated stage/tensor offsets for the compact v2 parameter image |
| `control/fsm.v` | Global scheduler with frame-sampled sparse mode, success-only-load-done fatal handling, shared-engine schedule, timeout, abort, and sticky errors |
| `top/accelerator_top.v` | Production RTL assembly for FSM, sparse PE/memory, mailbox, dispatcher, coefficient store, DeepFilter, and final-result stream |

## Global FSM and subband schedule

`control/fsm.v` sequences one frame through fullband GSU1, GSU2, projection,
the PL-to-PS-to-PL preprocessing dependency, all three subband stages,
DeepFilter, and final output. It issues the current memory-layout stage IDs
`0..11`, latches the subband scheduling mode at frame start, and exposes
ready/valid or start/done contracts rather than embedding arithmetic or AXI.

The resource-safe baseline time-multiplexes physical subband engine 0 across
logical branches 0/1/2 and their 4/3/2 contexts. The experimental mode assumes
three independent engines and weight banks, starts all branches together for
each GSU1/GSU2/projection stage, independently advances unequal context counts,
and waits for all three projections before DeepFilter. XSim proves both control
schedules, but does not prove that three complete datapaths fit the board.

Vivado 2018.3 OOC synthesis of the FSM alone for `xc7z020clg400-1` used 121
LUT, 67 FF, zero DSP, and zero BRAM. The 10 ns constraint passed with WNS
+4.792 ns and no unconstrained endpoints. Current raw stage-cache analysis
estimates that three simultaneous GSU2 weight banks alone need about 102 of the
PYNQ-Z1's 140 BRAM36 blocks; keeping all three complete branch parameter sets
resident needs about 210 BRAM36. Therefore the single-engine schedule is the
default integration baseline and true three-engine mode remains high-risk until
complete PE-array and banked-memory OOC/integration evidence exists. See
`docs/GLOBAL_FSM_AND_SUBBAND_SCHEDULE.md` for the state and feasibility tables.

## Sequential v4 PE/memory baseline and PS mailbox

`memory/memory.v` accepts an aligned source byte address, destination BRAM word
address, and byte count. It splits transfers at the configured burst limit and
4 KiB boundaries, checks `RID/RRESP/RLAST`, drains accepted bursts after
abort/timeout, and exposes one-cycle synchronous raw BRAM reads. The production
configuration is one 32K x 64-bit (256 KiB) cache with local writes disabled.

`tools/generate_memory_v4.py` reads the immutable raw parameter blob and emits
the consumer-native image under `outputs/memory/2026-09-03/v4/`. Weights use
`{operator,matrix,source_index,row_tile,lane}` physical order. Multipliers and
shifts are range-checked into signed 32-bit and unsigned 6-bit fields; GSU and
projection parameter records are 5,792 and 1,120 response bits respectively.
The global sigmoid payload is stored once at image offset 64 and configured
into the frozen PE once per reset epoch.  The generated v4 stage table is the
only address source used by `memory_service.v`.

`memory_service.v` permits one outstanding native request, assembles each
128-bit weight from two 64-bit cache reads, holds response/tag/error under
backpressure, and requires an explicit matching stage release.  The connected
controller processes one row tile at a time and uses persistent active lists
to skip inactive cache reads and PE commands. `layernorm_mailbox.v` maps two
64-byte PL-to-PS slots at byte offsets `0x000/0x040` and two 784-byte physical
PS-to-PL slots at `0x400/0x800`; exactly 782 payload bytes plus two zero padding
bytes must be committed.

The maximum v4 stage transfer is 219,360 bytes.  Routed subsystem OOC at
100 MHz measured WNS +0.242 ns, 19,546 LUT, 23,601 FF, 68 RAMB36E1,
2 RAMB18E1, and 37 DSP48E1.  Mailbox standalone OOC measured one RAMB36E1 and
WNS +1.647 ns.  Neither result includes the complete accelerator top, mailbox
interconnect, DMA, DeepFilter, or board behavior.  See the current integration
handoff for the exact evidence boundary and missing ownership glue.

## Single GSU layer contract

`gsu/gsu_layer.v` implements one complete integer GSU time step for the
checkpoint's `shared_weights=true` cells. The input and recurrent paths share
the same MAC result between the forget and cell gates, while each gate retains
its own input/recurrent requantization, bias, and clipping. The layer then runs
the calibrated sigmoid LUT, persistent `cx` update, folded-BN requantization,
and binary spike generation.

The default parameters match fullband layer 1: 64 input elements, 320 hidden
neurons, and 16 output lanes. `INPUT_IS_BINARY=1` selects the sparse binary
input behavior needed by fullband layer 2. Packed weight requests identify
`{input_or_recurrent, row_tile, source_index}`; parameter requests identify one
16-neuron row tile. The weights and per-channel parameters deliberately remain
external so `memory.v` can later choose BRAM/DDR tiling without changing the
GSU arithmetic interface.

The self-checking GSU test uses two four-neuron tiles and four consecutive
frames. It checks every forget gate, cell gate, state, spike, and clipping flag.
The first frame has zero recurrent reads; later frames produce exactly
`previous_active_spikes * row_tiles` recurrent reads. A state-clear command
returns the following frame to the zero-state result. Weight requests,
parameter requests, and result output are all stalled during the test to verify
ready/valid stability.

## Fullband three-layer path

`fullband/fullband_three_layer.v` instantiates the requested sequence with
fullband defaults:

1. GSU layer 1: dense INT8 `64 -> 320`.
2. GSU layer 2: binary sparse `320 -> 320`.
3. Linear projection: binary sparse `320 -> 64`.

Layer-1 result tiles are collected into a 320-bit spike vector and streamed to
layer 2. Layer-2 spikes are collected separately and streamed to the
projection. The two GSU instances retain independent recurrent states across
frames. All three engines share one external weight and parameter interface;
`layer_id` selects fullband layer 1, layer 2, or projection, matching the
eventual role of `memory.v`.

The standalone projection test covers zero, sparse, and dense inputs and
checks every requantized/clipped output. The three-layer integration test runs
four consecutive reduced-dimension frames, including stateful recurrence, an
extreme input, output backpressure, and state clearing. One frame produces no
layer-1 spikes, and the test verifies that layer-2 input reads become zero while
its independent recurrent reads continue.

The integration test uses reduced dimensions for exhaustive inspection. The
RTL defaults express the real 64/320/320/64 shapes, but actual tensors from
`parameters.bin`, full-size simulation, synthesis, and PYNQ-Z1 execution have
not yet been verified.

## AXI interface wiring checkpoint

The first PS/PL-facing interface prototype uses a 32-bit AXI4-Lite control
slave and 64-bit AXI4-Stream data adapters.  Arithmetic blocks retain their
smaller native ready/valid interfaces.  The stream ingress accepts arbitrary
nonzero `TKEEP`, skips invalid byte lanes, and places native `last` on the final
kept byte of a `TLAST` beat.  The egress packs bytes in increasing lane order
and holds `TDATA/TKEEP/TLAST` stable under backpressure.

The production transport has since narrowed this stream boundary to external
fullband ingress and final/DeepFilter egress. The per-frame CPU preprocessing
round trip uses the separate 4 KiB dual-port BRAM mailbox described above: PL
publishes 64 fullband bytes, the CPU will access it through PS `M_AXI_GP` plus
an AXI BRAM Controller, and PL consumes a committed 782-byte normalized-
subband slot. The RTL mailbox exists; its AXI IP connection and software driver
remain pending. This path bypasses DDR/DMA and does not reuse the parameter
cache or AXI4-Lite registers for payload.

`axis_weight_loader.v` converts two full 64-bit beats into the existing
128-bit weight word.  It has a ready/valid BRAM-write side, detects truncated
words and partial `TKEEP`, and was tested while writing the inactive bank of
`ping_pong_weight_buffer.v`.

The 2026-09-01 Windows XSim tests observed:

| Testbench | Coverage summary | Result |
| --- | --- | --- |
| `tb_axis_int8_link` | 325 bytes, 7 packets, lengths 1/8/13/46/94/158 plus non-contiguous `TKEEP`, 20 output-stall cycles, reset and malformed zero-keep case | PASS |
| `tb_axis_weight_loader` | Five 128-bit words from ten 64-bit beats, address order, ping-pong bank readback, stalls, early `TLAST`, partial `TKEEP`, mid-word reset | PASS |
| `tb_axi_lite_control` | Seven writes, nine reads, AW/W skew, `WSTRB`, B/R stalls, pulses, sticky status/IRQ and partial-transaction reset | PASS |

This proves behavioral wiring only. No LayerNorm mailbox/AXI BRAM Controller,
Xilinx AXI DMA IP, Vivado block design, PS driver, CDC, synthesis, timing, or
PYNQ-Z1 board transfer has been tested.

## Sparsity-aware execution contract

For a binary spike vector `x` and INT8 weight matrix `W`, the sparse path
computes the same result as dense `W*x`, but it requests a packed weight word
only when `x[column] == 1`. Because the active spike value is one, spike-mode
PEs add the selected column weights instead of instantiating an INT8 multiplier.

The logical weight address is `{column, row_tile}`. Each response contains one
packed word of `LANES` INT8 weights. Active indices are encoded once and reused
across every row tile, matching presentation pages 27, 29, and 30.

The 8-column, 8-row, 4-lane XSim proof produced:

| Active columns | Sparse reads | Dense reads | Reduction |
| ---: | ---: | ---: | ---: |
| 0 | 0 | 16 | 100% |
| 2 | 4 | 16 | 75% |
| 4 | 8 | 16 | 50% |
| 8 | 16 | 16 | 0% |

All four sparse results matched the dense reference. The current prototype
reuses the serial `spike_indexer`; it verifies correctness and weight-read
skipping but does not yet meet the analytical assumption of scanning 32 spike
bits per cycle.

## Presentation-scale spike regression

`tb/tb_sparsity_aware_matvec_realistic.v` exercises the intended 320-column,
320-row, 16-lane organization (20 row tiles). It runs 13 consecutive frames
after one initial reset and compares all 320 result rows of every frame with an
independently constructed dense matrix-vector reference. The memory model adds
deterministic request backpressure and 0..3-cycle response latency; the result
consumer also stalls for repeatable two-cycle intervals.

The main 2026-08-31 XSim measurements were:

| Profile | Active / 320 | Sparse reads | Dense reads | Reads saved | Simulated cycles |
| --- | ---: | ---: | ---: | ---: | ---: |
| Silence | 0 | 0 | 6,400 | 6,400 | 366 |
| Scattered, 95% sparse | 16 | 320 | 6,400 | 6,080 | 2,217 |
| Clustered wraparound, 95% sparse | 16 | 320 | 6,400 | 6,080 | 2,191 |
| Scattered, 90% sparse | 32 | 640 | 6,400 | 5,760 | 4,085 |
| Scattered, 80% sparse | 64 | 1,280 | 6,400 | 5,120 | 7,800 |
| Scattered, 70% sparse | 96 | 1,920 | 6,400 | 4,480 | 11,438 |
| Scattered, 50% sparse | 160 | 3,200 | 6,400 | 3,200 | 18,927 |
| Dense limit | 320 | 6,400 | 6,400 | 0 | 37,421 |

Temporal tests include an unchanged 32-spike frame, a frame that retains 24 of
32 spikes and replaces eight, and a 32-spike contiguous burst shifted by four
columns. Their measured overlaps were respectively 32, 24, and 28 active
columns. Every request addressed an active column; every active
`{column, row_tile}` pair occurred exactly once; no inactive column was read.

These deterministic patterns approximate plausible sparse and correlated SNN
traffic but are not measured model data. The repository currently has model
weights and activation ranges, but no representative audio sample or exported
per-frame spike trace. The cycle values also include the prototype's serial
320-bit scan and artificial stalls, so they are regression evidence rather than
PYNQ-Z1 latency or real-time-factor measurements.

## Running the tests

With Icarus Verilog:

```bash
cd rtl
make test
```

The v3 image/golden regression can be run from the repository root:

```bash
python3 -m pytest -q rtl/tests
```

The memory-only Windows runner executes the three memory XSim testbenches and
then synthesizes both production-v1 RTL tops for `xc7z020clg400-1` at 100 MHz:

```powershell
rtl\scripts\Run-Memory-V1-Vivado.cmd
```

It requires `PASS` markers, successful true-BRAM inference and nonnegative WNS,
and copies logs/utilization/timing/check reports to
`rtl/reports/memory_v1/`.

With a Vivado installation available in the current shell:

```powershell
vivado.bat -mode batch -source rtl/scripts/run_all_xsim.tcl
```

On the configured Windows laptop, run or double-click
`rtl/scripts/Run-XSim-Tests.cmd`. The batch runner uses Vivado 2018.3's
`xvlog`, `xelab`, and `xsim` executables directly. It copies the sources to a
Windows-native temporary directory before simulation so old Vivado releases do
not need to create project files on a WSL UNC path.

The runner requires each self-checking testbench to print its own `PASS tb_*`
marker. It returns a nonzero status for compilation/elaboration/simulation
errors or a missing marker, and writes the summary plus per-test logs under
`rtl/test-results/`.

The verified 2026-09-01 run completed with `passed=22 total=22`, including the
memory and global-FSM testbenches, with no XSim compile or elaboration error.
`tb_fsm` covers shared and three-engine schedules, unequal 4/3/2 context
latencies, request/output backpressure, reset, abort, timeout, and injected
memory/fullband/subband/DeepFilter errors.

The FSM OOC checkpoint can be regenerated with:

```powershell
vivado.bat -mode batch -source rtl/scripts/synth_fsm_ooc.tcl -tclargs rtl
```

The dependency-free reference-vector checks can be run separately:

```bash
python3 rtl/tests/reference_checks.py
```

The Python checks validate the arithmetic expected by the Verilog testbenches;
they are not a substitute for compiling and running the HDL simulations.

The parameter-image integrity test is separate because it reads the nested
model repository and the imported binary/JSON snapshot:

```bash
python3 -m pytest rtl/tests/test_axi_memory_image.py
```
