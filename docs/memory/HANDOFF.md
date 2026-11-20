# Sparse-memory accelerator-top integration handoff

Status: current integration handoff

Dense PE/memory provenance commit: `67b515757364fd9c9cabb404dcae303a45d9ea17`

Promoted sparse subsystem checkpoint: `6a13782`
Target: PYNQ-Z1 / `xc7z020clg400-1`, 100 MHz, one shared PE datapath

The production RTL top now instantiates
`sparse_memory_v1/rtl/sequential_v4_sparse_memory_subsystem.sv`; the earlier
dense wrapper is retained only as excluded provenance. Read
[`SPARSE_ACCELERATOR_TOP_INTEGRATION.md`](SPARSE_ACCELERATOR_TOP_INTEGRATION.md)
first for the promoted ABI, current top wiring, fresh XSim, and routed-OOC
result. This handoff retains the longer transport, mailbox, and board-boundary
contract.

Feature dispatch, coefficient storage, sequential DeepFilter execution, and
final result streaming are present in `accelerator_top`. The still-missing
system boundary is the Zynq PS7/control/DMA/CDC block design, matching
BIT/HWH/software, and board validation. The current sparse top is routable and
below the 80 percent resource review lines. Its single-clock routed-OOC timing
passes at 100 MHz with WNS `+0.115 ns` and WHS `+0.016 ns`; this is not a
full block-design or board timing sign-off.

## 1. Source-of-truth order

Use these records in this order:

1. [`SPARSE_ACCELERATOR_TOP_INTEGRATION.md`](SPARSE_ACCELERATOR_TOP_INTEGRATION.md)
   for the promoted sparse ABI, top wiring, and current evidence;
2. this handoff for accelerator-top ownership and system-boundary gaps;
3. [`PE_MEMORY_V4_FREEZE.md`](../frozen/PE_MEMORY_V4_FREEZE.md) and its
   checksum file for the byte-level PE/memory freeze; `fsm.v` is excluded;
4. [`MANIFEST.md`](MANIFEST.md) and [`SHA256SUMS`](SHA256SUMS) for the complete
   current compile allowlist, including the independently evolving FSM;
5. [`SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md`](SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md)
   for the normative PE/memory behavior;
6. [`SEQUENTIAL_V4_PE_MEMORY_SUBSYSTEM_PHASE_A_INTERFACE_REVIEW.md`](SEQUENTIAL_V4_PE_MEMORY_SUBSYSTEM_PHASE_A_INTERFACE_REVIEW.md)
   for the wrapper ABI;
7. production RTL for implementation truth; and
8. [`rtl/reports/accelerator_top_sparse_timing/summary.md`](../../rtl/reports/accelerator_top_sparse_timing/summary.md)
   for the current timing-closure evidence and its boundary; and
9. [`rtl/reports/accelerator_top_sparse/summary.md`](../../rtl/reports/accelerator_top_sparse/summary.md)
   for the immutable pre-fix timing baseline.

The old parameter-memory ping-pong line is archived under
`archive/parameter_memory_ping_pong/`.  It is non-normative and must not be
added to the production compile.  The older generic
`rtl/leaf/ping_pong_weight_buffer.v` belongs to a separate AXI-stream prototype
and is also not a production source.

The v3-specific portions of `MEMORY_DESIGN_GUIDELINES.md` and all v3 board
artifacts are historical.  Their transport split remains useful, but the v4
contract above controls the current parameter image and PE/memory subsystem.

## 2. Current integration boundary

```text
                         +-----------------------------+
start/control ---------->| global fsm.v                |
                         | shared mode only            |
                         +--+--------+---------+----+---+
                            |stage   |FB/SB job |    |DF job
                            v        v          |    v
                    +------------------------+  |  coefficient store +
PS DDR / HP AXI --->| sequential_v4_sparse_  |  |  sequential DeepFilter
                    | memory_subsystem       |  |  + final result stream
dense INT8 feature->|  sparse service/planner|  |
provider            |  sparse context store  |  |
                    |  job controller        |  |
                    |  frozen PE             |  |
                    +-------------+----------+  |
                                  | signed INT8 coefficients
                                  v             |
                           coefficient router --+
                                  |
                    FB stage 2: 64 bytes
                                  v
                    +--------------------------+
PS GP / BRAM ctrl <-| layernorm_mailbox        |
                    | 2x FB_OUT, 2x SB_IN      |
                    +-------------+------------+
                                  |
                     782 normalized SB bytes
                                  v
                         dense feature provider
```

The connected subsystem executes all twelve v4 GSU/projection stages, all
4/3/2 subband contexts, persistent recurrent state/list updates, and
compute-side sparsity. Dense mode copies full stages; sparse mode plans the
context union and issues sparse scatter loads while preserving mandatory
matrix/parameter residency. There is still one shared 256 KiB cache and no
ping-pong overlap.

## 3. Clock and reset contract

| Item | Required integration behavior |
|---|---|
| PL clock | One 100 MHz clock drives `fsm`, subsystem, mailbox PL logic, and the AXI-facing logic used by this baseline. |
| Subsystem reset | `rst_n` is active-low and synchronously observed by the production modules. |
| Mailbox clock | The native BRAM interface and PL stream/control logic are single-clock in `layernorm_mailbox`; any AXI clock difference must be resolved above it. |
| CDC | None is implemented inside the subsystem or mailbox.  Clock converters/reset synchronizers belong to the future top/BD. |
| Fatal recovery | `reset_required` is sticky. Recovery must reset `fsm`, sparse subsystem, frozen PE, context store, sparse DMA/service, feature/coefficient glue, and the associated AXI master/interconnect state as one coordinated epoch. |
| `clear_error` | Legacy-compatible input only.  It does not restore a fatal Sequential v4 subsystem. |
| `clear_state` | Connect `fsm.clear_state_pulse` to the subsystem.  It clears recurrent/list validity, not parameter image or payload RAM. |
| Parameter identity | `parameter_base_addr` and image version must remain stable for a reset epoch after global LUT initialization. |

Do not release only the controller while retaining stale AXI, PE, or context
state.  If the top cannot prove the coordinated reset set, it must remain in a
non-running fault state.

## 4. Global FSM wiring

Use `parallel_subbands=1'b0`.  The subsystem accepts only `stage_bank==0` and
only subband engine bit zero; other values intentionally become fatal.

| `fsm.v` edge | Subsystem/top connection |
|---|---|
| `stage_req_valid/ready`, `stage_id`, `stage_bank`, `stage_load_done/error` | Direct to the same-named subsystem ports. |
| `sparse_load_enable`, `stage_sparse_load_enable`, `sparse_mode_active` | Sample the software control only at frame acceptance; drive the sampled frame-stable value on every stage request and expose it as status. |
| `fb_start/ready`, `fb_stage`, `fb_done/error` | Direct to the subsystem. |
| `sb_start/ready`, `sb_stage`, `sb_shared_branch`, `sb_context_0..2`, `sb_done/error` | Direct to the subsystem; shared mode uses only bit/context zero for the physical engine. |
| `pe_barrier_idle`, `pe_fault` | Direct from the subsystem.  They are drain/fault evidence, not payload channels. |
| `pe_abort_pulse` | OR with the external abort request before driving subsystem `abort`. |
| `clear_state_pulse` | Drive subsystem `clear_state`. |
| `fb_result_valid/ready` | Requires top glue.  `ready` may assert only after the complete 64-byte FB projection has been published to the matching mailbox slot. |
| `ps_subbands_valid/ready` | Bridge to the mailbox committed-frame handshake; do not tie high in production. |
| `df_start/ready/done/error` | Direct to the integrated sequential DeepFilter engine and nine-context coefficient store. |
| `final_output_valid/ready` | Direct to the integrated final-result AXI4-Stream boundary; the surrounding DMA remains a BD task. |

The validated shared-mode stage order is:

```text
0, 1, 2, 3, 6, 9, 4, 7, 10, 5, 8, 11
```

The FSM sparse-mode/error executable example is `rtl/tb/tb_fsm.v`. The complete
sparse PE/memory behavior remains covered by the frozen CP6 connected test;
the current top runner elaborates that sparse wrapper together with the real
mailbox, dispatcher, coefficient store, and DeepFilter engine.

## 5. Subsystem port map

The complete declaration remains authoritative in
`sparse_memory_v1/rtl/sequential_v4_sparse_memory_subsystem.sv`.

| Group | Direction at subsystem | Ports | Top owner/consumer |
|---|---|---|---|
| Clock/reset/config | input | `clk`, `rst_n`, `abort`, `clear_error`, `clear_state`, `parameter_base_addr[31:0]` | clock/reset/control registers and coordinated-fault logic |
| Stage load | mixed | `stage_req_valid`, `stage_req_ready`, `stage_id[3:0]`, `stage_bank[1:0]`, `sparse_load_enable`, `stage_load_done`, `stage_load_error` | global FSM |
| Fullband jobs | mixed | `fb_start`, `fb_start_ready`, `fb_stage[1:0]`, `fb_done`, `fb_error` | global FSM |
| Subband jobs | mixed | `sb_start[2:0]`, `sb_start_ready`, `sb_stage[1:0]`, `sb_shared_branch[1:0]`, `sb_context_0..2[1:0]`, `sb_done[2:0]`, `sb_error[2:0]` | global FSM; only engine bit zero is legal |
| Dense feature request | output | `feature_req_valid`, `feature_req_stage_id[3:0]`, `feature_req_branch[1:0]`, `feature_req_context[1:0]`, `feature_req_source[9:0]`, `feature_req_tag[7:0]` | external feature dispatcher |
| Dense feature request flow | input | `feature_req_ready` | external feature dispatcher |
| Dense feature response | input | `feature_rsp_valid`, signed `feature_rsp_value[7:0]`, `feature_rsp_tag[7:0]`, `feature_rsp_error` | external feature dispatcher |
| Dense feature response flow | output | `feature_rsp_ready` | external feature dispatcher |
| Projection coefficients | output | `coefficient_valid`, signed `coefficient_value[7:0]`, `coefficient_index[8:0]`, `coefficient_tag[15:0]`, `coefficient_last` | stage-aware coefficient router |
| Projection backpressure | input | `coefficient_ready` | stage-aware coefficient router |
| AXI read address | output | `m_axi_araddr[31:0]`, `m_axi_arid[0:0]`, `m_axi_arlen[7:0]`, `m_axi_arsize[2:0]`, `m_axi_arburst[1:0]`, `m_axi_arprot[2:0]`, `m_axi_arcache[3:0]`, `m_axi_arqos[3:0]`, `m_axi_arlock`, `m_axi_arvalid` | AXI interconnect/PS HP path |
| AXI read address flow | input | `m_axi_arready` | AXI interconnect/PS HP path |
| AXI read data | input | `m_axi_rdata[63:0]`, `m_axi_rid[0:0]`, `m_axi_rresp[1:0]`, `m_axi_rlast`, `m_axi_rvalid` | AXI interconnect/PS HP path |
| AXI read data flow | output | `m_axi_rready` | AXI interconnect/PS HP path |
| FSM lifecycle | output | `pe_barrier_idle[2:0]`, `pe_fault[2:0]`, `reset_required` | global FSM and top fault controller |
| Read-only diagnostics | output | planner/context ownership and error identity; stage dense/planned/actual/saved bytes; union/copy/burst/load-cycle/LUT counters; PE/controller status and component error records | AXI4-Lite status/debug only; never use as ownership authorization |

Default parameters are 32-bit AXI address, 64-bit AXI data, one-bit AXI ID,
and one outstanding read burst.  `memory.v` emits only AR/R traffic, uses INCR
bursts, limits bursts to 16 beats, and does not cross a 4 KiB boundary.
`parameter_base_addr` must be at least 64-byte aligned; the image should be
placed in a PS-owned contiguous DDR allocation and flushed before PL ownership
is granted.

## 6. External dense-feature provider

The provider is required; no feature RAM or DMA adapter is present in the
subsystem.

- Stage 0 matrix 0 requests the 64-element normalized fullband feature vector.
- Stages 3, 6, and 9 matrix 0 request the matching mailbox-returned subband
  context: 46, 94, or 158 signed INT8 elements.
- The tuple `{stage_id, branch, context, source, tag}` identifies one request.
- There is at most one transaction in flight, but the provider must still hold
  request/response payload stable under backpressure and echo the exact tag.
- A response error or identity mismatch is fatal and therefore requires the
  coordinated reset described above.
- The provider must not expose a mailbox slot to a new frame until the mailbox
  commit/consume ownership transition is complete.

The future top may implement this as a small dispatcher over a fullband ingress
buffer and the mailbox stream; that storage and arbitration are not part of
commit `67b5157`.

## 7. Projection coefficient sink

The coefficient output is a stage-aware stream routed by the integrated
mailbox publisher and DeepFilter coefficient store.

- For stage 2, route exactly 64 signed INT8 coefficients in increasing index
  order into `layernorm_mailbox.fb_begin_*` / `fb_data_*`.  Assert the mailbox
  `fb_data_last` only for index 63 and associate the current frame ID.
- For stages 5, 8, and 11, `sequential_df_coefficient_store` retains the nine
  branch/context projections with verified identity, completeness, TLAST, and
  frame ownership before the sequential DeepFilter engine can read them.
- `coefficient_ready` must reflect the selected sink's real capacity.  The
  producer holds value/index/tag/last while stalled.
- Do not route subband projection coefficients into the active-index or
  LayerNorm mailbox paths.

## 8. PS LayerNorm mailbox ownership

`rtl/memory/layernorm_mailbox.v` is a separate production candidate; it is not
instantiated by the Sequential v4 subsystem.

| Region | Offset | Payload | Direction |
|---|---:|---:|---|
| `FB_OUT_SLOT0` | `0x000` | 64 bytes | PL to PS |
| `FB_OUT_SLOT1` | `0x040` | 64 bytes | PL to PS |
| `SB_IN_SLOT0` | `0x400` | 782 bytes plus two zero pad bytes | PS to PL |
| `SB_IN_SLOT1` | `0x800` | 782 bytes plus two zero pad bytes | PS to PL |

Port A is the 1024x32 native BRAM interface for an AXI BRAM Controller reached
through PS `M_AXI_GP`.  Port B is internal PL ownership.  AXI4-Lite control
registers must carry claim/commit/release events and frame IDs; bulk mailbox
payload must not be copied through AXI4-Lite registers or the parameter DDR
reader.

The current mailbox permits its documented recoverable error behavior, while
the Sequential v4 subsystem is reset-only after fatal error.  The future top
must define one system policy: any mailbox error that invalidates the active
frame must abort the FSM and enter the same coordinated reset epoch rather than
allowing PE work to continue with stale features.

## 9. Remaining system boundary

The coefficient store, noisy-bin history, sequential 5/3/1-tap complex
DeepFilter engine, `df_*` lifecycle, and final result stream are now integrated
in RTL. The remaining production boundary is outside this OOC top: PS7,
AXI4-Lite control, AXI DMA/interconnect, clock/reset synchronizers, cache/
coherency software, and matching BIT/HWH deployment. Until those are connected
and measured on the PYNQ-Z1, do not describe this RTL as board-validated
end-to-end inference.

## 10. Timing, resources, and constraints

The current routed OOC result for the sparse `accelerator_top` is:

| Metric | Measured value |
|---|---:|
| Post-synthesis WNS | `-0.005 ns` at 10.000 ns |
| Post-route WNS / TNS | `+0.115 ns / 0.000 ns` (`timing_met=1`) |
| Post-route WHS / THS | `+0.016 ns / 0.000 ns` (`hold_met=1`) |
| Slice LUTs / registers | `24,461 / 28,443` |
| RAMB36E1 / RAMB18E1 | `71 / 4` |
| DSP48E1 | `46` |
| Failed / unrouted / partially routed nets | `0 / 0 / 0` |

`accelerator_top` registers the subsystem barrier once before the global FSM.
The external diagnostic remains immediate; the scheduler sees a conservative
one-cycle-delayed idle assertion. This cuts the former controller-to-FSM-to-
controller combinational path while preserving the ready/valid contract.

The OOC constraint creates one 100 MHz clock and intentionally has no external
input/output delays. These results include the FSM, sparse PE/memory wrapper,
mailbox, feature/coefficient paths, sequential DeepFilter engine, and top-level
routing. They exclude the Zynq block design, AXI IP, CDC, and board I/O timing.

## 11. Accelerator-top integration checklist

1. Verify the sparse production allowlist with `sha256sum -c`.
2. Keep `parallel_subbands=0` and the frame-sampled sparse-mode contract.
3. Preserve the registered FSM barrier timing cut and rerun both setup and hold
   gates after any scheduler, sparse-service, or top-level control change.
4. Connect the mailbox through an AXI BRAM Controller and explicit AXI4-Lite
   claim/commit/release registers.
5. Connect the parameter AR/R master through the intended PS HP port and prove
   address width, ID, cache/coherency, and reset behavior.
6. Implement one coordinated reset/fault controller and verify that no new
   outward valid is created after fatal discovery.
7. Run a multi-frame connected top reference test with real v4 image, mailbox
   backpressure, AXI errors, abort, and reset restart.
8. Perform full XC7Z020 synthesis/place/route with generated-clock, CDC,
    input/output delay, AXI, congestion, and utilization reports.
9. Only after matching BIT/HWH/software and board measurements may DDR
    bandwidth, mailbox latency, RTF, power, or audio quality be claimed.

## 12. Known limitations

- Dense mode transfers full stages. Sparse mode reduces eligible weight bytes
  using context-union scatter loads while mandatory matrices, parameters, and
  the reset-epoch LUT remain required.
- Only one stage, job, native memory transaction, and shared PE stream advance
  at a time.
- Global LUT initialization transfers 2,040 bytes once per reset epoch.
- Nonzero stage bank, subband engine bits one/two, identity mismatch, AXI
  error/timeout, PE overflow, or protocol error is fatal.
- The OOC shell does not prove top-level timing, CDC, AXI IP behavior, DDR
  bandwidth, mailbox software ordering, or board operation.
- Existing v3 parameter-BRAM BIT/HWH/LTX artifacts do not implement this v4
  subsystem and must not be reused as if they did.
