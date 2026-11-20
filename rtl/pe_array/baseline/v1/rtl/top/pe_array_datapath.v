`timescale 1ns/1ps

// Structural integration wrapper for the formal PE-side baseline.
//
// This block deliberately contains no layer/tile scheduler, parameter RAM,
// coefficient/spectrum storage, general FIFO/scoreboard, requantizer,
// multiplier, or arithmetic datapath.  It owns only physical-resource muxes,
// ready/valid joins/forks, the gate/membrane temporary context explicitly
// required by the integration contract, and protocol accounting.
//
// Compile this wrapper only with the eleven RTL module types archived under
// baseline/v1.  Accepted leaf RTL is not duplicated or modified here.
module pe_array_datapath #(
    parameter integer INDEX_WIDTH     = 9,
    parameter integer BIN_INDEX_WIDTH = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // External phase ownership.  Requests are level signals.  The wrapper
    // never selects a priority when more than one owner requests NONE.
    input  wire                         raw_owner_request,
    output wire                         raw_owner_grant,
    input  wire                         gate_owner_request,
    output wire                         gate_owner_grant,
    output wire [3:0]                   compute_owner,
    output wire                         compute_idle,

    // Controller-owned Hybrid-PE commands for RAW and GATE phases.
    input  wire [15:0]                  ctrl_pe_acc_clear,
    input  wire [15:0]                  ctrl_pe_acc_enable,
    input  wire [1:0]                   ctrl_pe_mode,
    input  wire [16*8-1:0]              ctrl_pe_operand_a,
    input  wire [16*8-1:0]              ctrl_pe_operand_b,
    input  wire [16*8-1:0]              ctrl_pe_gate_u8,
    input  wire [15:0]                  ctrl_pe_spike_enable,
    input  wire [16*32-1:0]             ctrl_pe_direct_value,
    output wire [16*32-1:0]             pe_accumulator,
    output wire [15:0]                  pe_overflow,

    // One gate tile context.  Per-lane tags are opaque sixteen-bit user tags.
    input  wire                         gate_tile_valid,
    output wire                         gate_tile_ready,
    input  wire [15:0]                  gate_tile_lane_valid,
    input  wire [16*16-1:0]             gate_tile_tags,
    input  wire [2:0]                   gate_tile_table_select,
    output wire                         gate_collect_complete,

    // Gate request to the physical four-lane Local RQ Bank.  value is the
    // live signed-INT32 accumulator packet selected by the external schedule;
    // this wrapper intentionally does not snapshot raw accumulators.
    input  wire                         gate_rq_valid,
    output wire                         gate_rq_ready,
    input  wire [3:0]                   gate_rq_lane_valid,
    input  wire [4*32-1:0]              gate_rq_value,
    input  wire [4*32-1:0]              gate_rq_multiplier,
    input  wire [4*6-1:0]               gate_rq_shift,
    input  wire                         gate_rq_gate,
    input  wire                         gate_rq_component,
    input  wire [1:0]                   gate_rq_group,
    input  wire [4*16-1:0]              gate_rq_tags,

    // Bias is joined atomically with the matching RECURRENT RQ response.
    // The provider holds valid and every field stable until ready.
    input  wire                         gate_bias_valid,
    output wire                         gate_bias_ready,
    input  wire                         gate_bias_gate,
    input  wire [1:0]                   gate_bias_group,
    input  wire [3:0]                   gate_bias_lane_valid,
    input  wire [4*32-1:0]              gate_bias_value,
    input  wire [4*16-1:0]              gate_bias_tags,

    // Resident sigmoid-table configuration stream.
    input  wire                         sigmoid_cfg_start_valid,
    output wire                         sigmoid_cfg_start_ready,
    input  wire                         sigmoid_cfg_data_valid,
    output wire                         sigmoid_cfg_data_ready,
    input  wire [7:0]                   sigmoid_cfg_data,
    output wire                         sigmoid_cfg_done,
    output wire                         sigmoid_table_valid,

    // Membrane job.  i_t/lambda/lane-mask/tags come from the gate collector.
    input  wire                         membrane_start_valid,
    output wire                         membrane_start_ready,
    input  wire [16*8-1:0]              membrane_u_prev,
    input  wire [16*32-1:0]             membrane_cx_multiplier,
    input  wire [16*6-1:0]              membrane_cx_shift,
    input  wire [16*32-1:0]             membrane_cell_multiplier,
    input  wire [16*6-1:0]              membrane_cell_shift,
    input  wire [INDEX_WIDTH-1:0]       membrane_base_index,
    input  wire                         membrane_logical_last,
    output wire                         membrane_busy,
    output wire                         membrane_done,
    output wire [3:0]                   membrane_phase,

    // A Linear tile is captured directly from the live PE accumulators.
    input  wire                         linear_tile_valid,
    output wire                         linear_tile_ready,
    input  wire [15:0]                  linear_tile_lane_valid,
    input  wire [INDEX_WIDTH-1:0]       linear_tile_base_index,
    input  wire [16*16-1:0]             linear_tile_tags,
    input  wire                         linear_tile_logical_last,

    // Parameter stream atomically joined with the held serializer scalar.
    // query_* is combinational look-ahead, not a separately accepted request.
    output wire                         rq_param_query_valid,
    output wire                         rq_param_query_op_kind,
    output wire [INDEX_WIDTH-1:0]       rq_param_query_index,
    output wire [15:0]                  rq_param_query_tag,
    input  wire                         rq_param_valid,
    output wire                         rq_param_ready,
    input  wire                         rq_param_op_kind,
    input  wire signed [31:0]           rq_param_multiplier,
    input  wire [5:0]                   rq_param_shift,
    input  wire signed [31:0]           rq_param_bias,
    input  wire [INDEX_WIDTH-1:0]       rq_param_index,
    input  wire [15:0]                  rq_param_tag,

    // Dense QBN state write: one transaction for every QBN scalar.
    output wire                         state_write_valid,
    input  wire                         state_write_ready,
    output wire signed [7:0]            state_write_value,
    output wire [INDEX_WIDTH-1:0]       state_write_index,
    output wire [15:0]                  state_write_tag,
    output wire                         state_write_last,

    // Atomic active-index command after the formal spike-decision/writer pair.
    output wire                         active_cmd_valid,
    input  wire                         active_cmd_ready,
    output wire                         active_cmd_write,
    output wire [INDEX_WIDTH-1:0]       active_cmd_index,
    output wire [15:0]                  active_cmd_tag,
    output wire                         active_cmd_finalize,

    // Linear shared-RQ output.  Coefficient reshape/storage is external.
    output wire                         coefficient_valid,
    input  wire                         coefficient_ready,
    output wire signed [7:0]            coefficient_value,
    output wire [INDEX_WIDTH-1:0]       coefficient_index,
    output wire [15:0]                  coefficient_tag,
    output wire                         coefficient_last,

    // CDF native memory/controller boundary.  Coefficients and spectrum
    // history are supplied one tap packet at a time by external storage.
    input  wire                         cdf_start_valid,
    output wire                         cdf_start_ready,
    input  wire [2:0]                   cdf_order,
    input  wire [7:0]                   cdf_bin_valid,
    input  wire [BIN_INDEX_WIDTH-1:0]   cdf_bin_base,
    input  wire [1:0]                   cdf_band,
    input  wire [15:0]                  cdf_tag,
    input  wire                         cdf_tap_valid,
    output wire                         cdf_tap_ready,
    input  wire [2:0]                   cdf_tap_index,
    input  wire [8*8-1:0]               cdf_spectrum_real,
    input  wire [8*8-1:0]               cdf_spectrum_imag,
    input  wire [8*8-1:0]               cdf_coefficient_real,
    input  wire [8*8-1:0]               cdf_coefficient_imag,
    output wire                         cdf_result_valid,
    input  wire                         cdf_result_ready,
    output wire [8*32-1:0]              cdf_result_real,
    output wire [8*32-1:0]              cdf_result_imag,
    output wire [7:0]                   cdf_result_bin_valid,
    output wire [2:0]                   cdf_result_order,
    output wire [BIN_INDEX_WIDTH-1:0]   cdf_result_bin_base,
    output wire [1:0]                   cdf_result_band,
    output wire [15:0]                  cdf_result_tag,
    output wire                         cdf_busy,
    output wire                         cdf_done,
    output wire [2:0]                   cdf_phase,
    output wire [2:0]                   cdf_active_tap_index,

    // Derived state.  These are handshake-accounted, never latency counters.
    output wire                         hybrid_idle,
    output wire                         local_rq_idle,
    output wire                         postprocess_idle,
    output wire                         sigmoid_idle,
    output wire                         serializer_idle,
    output wire                         shared_rq_idle,
    output wire                         qbn_fork_idle,
    output wire [4:0]                   local_rq_outstanding,
    output wire [4:0]                   postprocess_outstanding,
    output wire [4:0]                   shared_rq_outstanding,
    output wire                         overflow_any,
    output wire                         protocol_error
);

    localparam [3:0] OWNER_NONE     = 4'b0000;
    localparam [3:0] OWNER_RAW      = 4'b0001;
    localparam [3:0] OWNER_GATE     = 4'b0010;
    localparam [3:0] OWNER_MEMBRANE = 4'b0100;
    localparam [3:0] OWNER_CDF      = 4'b1000;

    localparam COMPONENT_INPUT     = 1'b0;
    localparam COMPONENT_RECURRENT = 1'b1;
    localparam OP_QBN              = 1'b0;
    localparam OP_LINEAR           = 1'b1;

    reg [3:0] owner_q;
    wire owner_raw;
    wire owner_gate;
    wire owner_membrane;
    wire owner_cdf;
    wire membrane_owner_request;
    wire cdf_owner_request;
    wire [3:0] owner_requests;
    reg  membrane_serializer_reserved_q;
    reg  [INDEX_WIDTH-1:0] membrane_base_index_q;
    reg  membrane_logical_last_q;
    reg  sig_cfg_busy_q;
    reg  serializer_context_valid_q;
    reg  serializer_op_kind_q;
    reg  membrane_launch_window_q;
    reg  linear_capture_window_q;
    wire serializer_out_valid;
    wire serializer_busy;

    // owner_q is a registered one-hot lock.  Use its bits directly for the
    // resource grants so one owner's bit cannot enter another owner's leaf
    // cone through a four-bit equality decoder.
    assign owner_raw      = owner_q[0];
    assign owner_gate     = owner_q[1];
    assign owner_membrane = owner_q[2];
    assign owner_cdf      = owner_q[3];
    assign raw_owner_grant  = owner_raw;
    assign gate_owner_grant = owner_gate;
    assign compute_owner    = owner_q;

    // ---------------------------------------------------------------------
    // Physical Hybrid PE array and command owner mux.
    // ---------------------------------------------------------------------
    wire [15:0]      phy_pe_acc_clear;
    wire [15:0]      phy_pe_acc_enable;
    wire [16*2-1:0]  phy_pe_mode;
    wire [16*8-1:0]  phy_pe_operand_a;
    wire [16*8-1:0]  phy_pe_operand_b;
    wire [16*8-1:0]  phy_pe_gate_u8;
    wire [15:0]      phy_pe_spike_enable;
    wire [16*32-1:0] phy_pe_direct_value;
    wire [16*32-1:0] phy_pe_accumulator;
    wire [15:0]      phy_pe_overflow;
    wire [15:0]      source_pe_acc_clear;
    wire [15:0]      source_pe_acc_enable;
    wire [16*2-1:0]  source_pe_mode;
    wire [16*8-1:0]  source_pe_operand_a;
    wire [16*8-1:0]  source_pe_operand_b;
    wire [16*8-1:0]  source_pe_gate_u8;
    wire [15:0]      source_pe_spike_enable;
    wire [16*32-1:0] source_pe_direct_value;
    reg  [15:0]      pe_cmd_acc_clear_q;
    reg  [15:0]      pe_cmd_acc_enable_q;
    (* keep = "true" *) reg [16*2-1:0] pe_cmd_mode_q;
    reg  [16*8-1:0]  pe_cmd_operand_a_q;
    reg  [16*8-1:0]  pe_cmd_operand_b_q;
    reg  [16*8-1:0]  pe_cmd_gate_u8_q;
    reg  [15:0]      pe_cmd_spike_enable_q;
    reg  [16*32-1:0] pe_cmd_direct_value_q;
    reg  [3:0]       pe_cmd_owner_q;
    reg              pe_cmd_mem_direct_valid_q;
    reg  [1:0]       pe_cmd_mem_direct_group_q;
    reg              mem_direct_commit_valid_q;
    reg  [1:0]       mem_direct_commit_group_q;
    reg  [3:0]       mem_final_acc_ready_q;
    wire             physical_command_pipe_empty;
    wire             phy_rq_out_valid;
    reg              phy_rq_out_ready;
    wire [3:0]       phy_rq_out_lane_valid;
    reg  [15:0]      gate_expected_mask_q;
    reg  [16*8-1:0]  gate_i_values_q;
    reg  [16*8-1:0]  gate_lambda_values_q;

    wire [15:0]      mem_pe_acc_clear;
    wire [15:0]      mem_pe_acc_enable;
    wire [1:0]       mem_pe_mode;
    wire [16*8-1:0]  mem_pe_gate_u8;
    wire [16*8-1:0]  mem_pe_operand_b;
    wire [16*32-1:0] mem_pe_direct_value;
    wire             mem_rq_in_valid;
    wire             mem_rq_in_ready;
    reg  [15:0]      membrane_gate_issue_fast;
    reg  [15:0]      membrane_response_issue_fast;
    reg  [16*32-1:0] membrane_direct_value_fast;
    reg  [16*8-1:0]  membrane_u_prev_fast_q;
    wire [16*8-1:0]  membrane_gate_u8_fast;
    wire [16*8-1:0]  membrane_operand_b_fast;

    wire [15:0]      cdf_pe_acc_clear;
    wire [15:0]      cdf_pe_acc_enable;
    wire [1:0]       cdf_pe_mode;
    wire [16*8-1:0]  cdf_pe_operand_a;
    wire [16*8-1:0]  cdf_pe_operand_b;
    wire [1:0]       membrane_pe_mode_fast;

    // First half of the fixed two-stage CDF/physical-PE timing boundary.  The
    // second half is the common physical command register below, shared by
    // every owner rather than duplicated for CDF.
    // This is a continuously consumed command pipeline, not an elastic
    // buffer: it has no ready, pointers, occupancy count, or payload storage
    // beyond the exact commands being delivered on following cycles.  The
    // second stage isolates the high-fanout owner/grant decode from all
    // sixteen physical multiplier inputs in the connected hierarchy.
    reg  [15:0]      cdf_cmd_acc_clear_q;
    reg  [15:0]      cdf_cmd_acc_enable_q;
    reg  [16*8-1:0]  cdf_cmd_operand_a_q;
    reg  [16*8-1:0]  cdf_cmd_operand_b_q;
    reg               cdf_cmd_issue_q;
    wire             cdf_prepipe_empty;
    wire             cdf_command_pipe_empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            cdf_cmd_acc_clear_q  <= 16'd0;
            cdf_cmd_acc_enable_q <= 16'd0;
            cdf_cmd_operand_a_q  <= {16*8{1'b0}};
            cdf_cmd_operand_b_q  <= {16*8{1'b0}};
            cdf_cmd_issue_q       <= 1'b0;
        end else begin
            // The leaf self-zeros every command while ungranted.  Capturing
            // those zeros naturally drains this boundary.
            cdf_cmd_acc_clear_q  <= cdf_pe_acc_clear;
            cdf_cmd_acc_enable_q <= cdf_pe_acc_enable;
            cdf_cmd_operand_a_q  <= cdf_pe_operand_a;
            cdf_cmd_operand_b_q  <= cdf_pe_operand_b;
            cdf_cmd_issue_q      <= |cdf_pe_acc_enable;
        end
    end

    assign cdf_prepipe_empty =
        ((cdf_cmd_acc_clear_q | cdf_cmd_acc_enable_q) == 16'd0);
    assign cdf_command_pipe_empty = cdf_prepipe_empty
        && physical_command_pipe_empty;

    // Membrane/CDF leaf commands are already grant-qualified and self-zero
    // while unowned.  A one-hot OR keeps their same-cycle clear/enable
    // semantics without making the controller owner select the long leaf
    // ready cones.  This is still an all-or-none physical-resource mux.
    wire ctrl_pe_command_owner;
    wire [15:0] ctrl_pe_issue;
    wire [15:0] membrane_pe_issue;
    wire [15:0] cdf_pe_issue;
    wire membrane_gate_command_fast;
    wire membrane_response_command_fast;
    assign ctrl_pe_command_owner = (owner_raw && !linear_capture_window_q)
        || (owner_gate && !membrane_launch_window_q);
    assign ctrl_pe_issue = {16{ctrl_pe_command_owner}}
        & ctrl_pe_acc_enable;
    assign membrane_pe_issue = membrane_gate_issue_fast
        | membrane_response_issue_fast;
    assign cdf_pe_issue = cdf_cmd_acc_enable_q;
    assign membrane_gate_command_fast = (membrane_phase == 4'd2)
        || (membrane_phase == 4'd9);
    assign membrane_response_command_fast =
        (membrane_phase != 4'd0) && phy_rq_out_valid
        && phy_rq_out_ready;
    // The immutable membrane leaf computes these same payloads from its
    // private start registers.  Reusing the wrapper's already-registered gate
    // collectors, plus an atomic u_prev snapshot, keeps the leaf's response
    // bookkeeping out of every physical DSP input.  Disabled lanes are
    // don't-care.
    assign membrane_gate_u8_fast = (membrane_phase == 4'd2)
        ? gate_lambda_values_q : ~gate_lambda_values_q;
    assign membrane_operand_b_fast = (membrane_phase == 4'd2)
        ? membrane_u_prev_fast_q : gate_i_values_q;
    // During legal membrane ownership every Local-RQ response is immediately
    // accepted by the leaf.  Its mode is therefore GATE except on the exact
    // response-valid/DIRECT edge.  This equivalent shallow decode prevents
    // the leaf pending-mask diagnostic cone from feeding all Hybrid DSP A
    // inputs; the immutable leaf mode remains checked in simulation.
    assign membrane_pe_mode_fast = {1'b1,
        membrane_response_command_fast};
    // Source selection is per lane.  Every command field is then captured by
    // one common register boundary: clear/enable/mode/data can never skew,
    // and no live owner/leaf/RQ cone reaches a physical Hybrid DSP input.
    assign source_pe_acc_clear =
        ({16{ctrl_pe_command_owner}} & ctrl_pe_acc_clear)
        | mem_pe_acc_clear | cdf_cmd_acc_clear_q;
    assign source_pe_acc_enable = ctrl_pe_issue
        | membrane_pe_issue | cdf_pe_issue;

    wire source_pe_command_active;
    wire [3:0] source_pe_owner;
    assign source_pe_command_active =
        |(source_pe_acc_clear | source_pe_acc_enable);
    assign source_pe_owner =
        (|(cdf_cmd_acc_clear_q | cdf_cmd_acc_enable_q)) ? OWNER_CDF
        : (|(mem_pe_acc_clear | membrane_pe_issue)) ? OWNER_MEMBRANE
        : (ctrl_pe_command_owner
           && (|(ctrl_pe_acc_clear | ctrl_pe_acc_enable)))
            ? owner_q : OWNER_NONE;

    always @(posedge clk) begin
        if (!rst_n) begin
            pe_cmd_acc_clear_q    <= 16'd0;
            pe_cmd_acc_enable_q   <= 16'd0;
            pe_cmd_mode_q         <= {16*2{1'b0}};
            pe_cmd_operand_a_q    <= {16*8{1'b0}};
            pe_cmd_operand_b_q    <= {16*8{1'b0}};
            pe_cmd_gate_u8_q      <= {16*8{1'b0}};
            pe_cmd_spike_enable_q <= 16'd0;
            pe_cmd_direct_value_q <= {16*32{1'b0}};
            pe_cmd_owner_q        <= OWNER_NONE;
            pe_cmd_mem_direct_valid_q <= 1'b0;
            pe_cmd_mem_direct_group_q <= 2'd0;
            mem_direct_commit_valid_q <= 1'b0;
            mem_direct_commit_group_q <= 2'd0;
            mem_final_acc_ready_q     <= 4'd0;
        end else begin
            // This is a continuously advancing command pipeline, not an
            // elastic buffer.  A source with no command writes an idle token,
            // so no command can replay under owner or downstream stalls.
            pe_cmd_acc_clear_q    <= source_pe_acc_clear;
            pe_cmd_acc_enable_q   <= source_pe_acc_enable;
            pe_cmd_mode_q         <= source_pe_mode;
            pe_cmd_operand_a_q    <= source_pe_operand_a;
            pe_cmd_operand_b_q    <= source_pe_operand_b;
            pe_cmd_gate_u8_q      <= source_pe_gate_u8;
            pe_cmd_spike_enable_q <= source_pe_spike_enable;
            pe_cmd_direct_value_q <= source_pe_direct_value;
            pe_cmd_owner_q        <= source_pe_command_active
                ? source_pe_owner : OWNER_NONE;
            // Both CX and CELL RQ responses use DIRECT mode, but only the
            // CELL component completes the final membrane sum.  Canonical
            // membrane TAG20 bit 18 is the component bit.
            pe_cmd_mem_direct_valid_q <= membrane_response_command_fast
                && phy_rq_tag_out[18];
            pe_cmd_mem_direct_group_q <= phy_rq_tag_out[17:16];

            // A DIRECT term captured by the Hybrid PE commits on the next
            // edge.  This two-bit metadata mirror marks the corresponding
            // group ready in that exact commit cycle; it carries no data and
            // is not a fixed-latency owner-release rule.
            mem_direct_commit_valid_q <= pe_cmd_mem_direct_valid_q;
            mem_direct_commit_group_q <= pe_cmd_mem_direct_group_q;
            if (membrane_start_fire)
                mem_final_acc_ready_q <= 4'd0;
            else if (mem_direct_commit_valid_q)
                mem_final_acc_ready_q[
                    mem_direct_commit_group_q] <= 1'b1;
        end
    end

    assign phy_pe_acc_clear    = pe_cmd_acc_clear_q;
    assign phy_pe_acc_enable   = pe_cmd_acc_enable_q;
    assign phy_pe_mode         = pe_cmd_mode_q;
    assign phy_pe_operand_a    = pe_cmd_operand_a_q;
    assign phy_pe_operand_b    = pe_cmd_operand_b_q;
    assign phy_pe_gate_u8      = pe_cmd_gate_u8_q;
    assign phy_pe_spike_enable = pe_cmd_spike_enable_q;
    assign phy_pe_direct_value = pe_cmd_direct_value_q;
    assign physical_command_pipe_empty =
        ((pe_cmd_acc_clear_q | pe_cmd_acc_enable_q) == 16'd0);

    assign pe_accumulator = phy_pe_accumulator;
    assign pe_overflow    = phy_pe_overflow;
    assign overflow_any   = |phy_pe_overflow;

    genvar pe_lane;
    generate
        for (pe_lane = 0; pe_lane < 16; pe_lane = pe_lane + 1) begin : gen_hybrid_pe
            assign source_pe_mode[pe_lane*2 +: 2] =
                cdf_cmd_issue_q ? 2'd0
                : (membrane_gate_command_fast
                   || membrane_response_command_fast)
                    ? membrane_pe_mode_fast
                : ctrl_pe_mode;
            assign source_pe_operand_a[pe_lane*8 +: 8] =
                cdf_cmd_issue_q
                ? cdf_cmd_operand_a_q[pe_lane*8 +: 8]
                : ctrl_pe_operand_a[pe_lane*8 +: 8];
            assign source_pe_operand_b[pe_lane*8 +: 8] =
                cdf_cmd_issue_q
                ? cdf_cmd_operand_b_q[pe_lane*8 +: 8]
                : membrane_gate_command_fast
                    ? membrane_operand_b_fast[pe_lane*8 +: 8]
                    : ctrl_pe_operand_b[pe_lane*8 +: 8];
            assign source_pe_gate_u8[pe_lane*8 +: 8] =
                membrane_gate_command_fast
                ? membrane_gate_u8_fast[pe_lane*8 +: 8]
                : ctrl_pe_gate_u8[pe_lane*8 +: 8];
            assign source_pe_spike_enable[pe_lane] =
                ctrl_pe_spike_enable[pe_lane];
            assign source_pe_direct_value[pe_lane*32 +: 32] =
                membrane_response_command_fast
                ? membrane_direct_value_fast[pe_lane*32 +: 32]
                : ctrl_pe_direct_value[pe_lane*32 +: 32];

            pe_hybrid_mac u_hybrid_mac (
                .clk(clk),
                .rst_n(rst_n),
                .acc_clear(phy_pe_acc_clear[pe_lane]),
                .acc_enable(phy_pe_acc_enable[pe_lane]),
                .mode(phy_pe_mode[pe_lane*2 +: 2]),
                .operand_a(phy_pe_operand_a[pe_lane*8 +: 8]),
                .operand_b(phy_pe_operand_b[pe_lane*8 +: 8]),
                .gate_u8(phy_pe_gate_u8[pe_lane*8 +: 8]),
                .spike_enable(phy_pe_spike_enable[pe_lane]),
                .direct_value(phy_pe_direct_value[pe_lane*32 +: 32]),
                .accumulator(phy_pe_accumulator[pe_lane*32 +: 32]),
                .overflow(phy_pe_overflow[pe_lane])
            );
        end
    endgenerate

    // Preserve the wrapper-owned pending mirror.  Without this attribute
    // Vivado can merge it into sixteen physically dispersed leaf
    // term_valid_pipe registers, recreating a long global idle/release cone.
    (* keep = "true" *) reg [15:0] pe_pending_q;
    wire hybrid_pipeline_empty;
    wire [15:0] phy_pe_busy_mask;
    reg  hybrid_drain_q;
    wire hybrid_quiescent;
    wire mem_rq_fire_fast;
    wire mem_source_command_active_fast;
    wire source_pe_command_active_fast;
    wire raw_pe_idle;
    wire gate_pe_idle;
    wire membrane_pe_idle;
    wire cdf_pe_idle;
    integer pending_lane;
    always @(posedge clk) begin
        if (!rst_n) begin
            pe_pending_q <= 16'd0;
        end else begin
            for (pending_lane = 0; pending_lane < 16;
                 pending_lane = pending_lane + 1) begin
                if (phy_pe_acc_clear[pending_lane])
                    pe_pending_q[pending_lane] <= 1'b0;
                else
                    pe_pending_q[pending_lane] <=
                        phy_pe_acc_enable[pending_lane];
            end
        end
    end

    assign hybrid_pipeline_empty = (pe_pending_q == 16'd0);
    assign phy_pe_busy_mask = pe_cmd_acc_clear_q
        | pe_cmd_acc_enable_q | pe_pending_q;

    // A shallow cycle-exact token clears the proof on the edge that captures
    // a new command.  It deliberately uses registered phase/fast-mirror facts
    // instead of the immutable membrane leaf's wide command cone.
    assign mem_rq_fire_fast = owner_membrane
        && ((membrane_phase == 4'd4) || (membrane_phase == 4'd5))
        && mem_rq_in_valid && mem_rq_in_ready;
    assign mem_source_command_active_fast = owner_membrane
        && ((membrane_phase == 4'd1)
            || (membrane_phase == 4'd2)
            || (membrane_phase == 4'd8)
            || (membrane_phase == 4'd9)
            || (membrane_phase == 4'd10)
            || membrane_response_command_fast
            || mem_rq_fire_fast);
    assign source_pe_command_active_fast =
        (ctrl_pe_command_owner
         && (|(ctrl_pe_acc_clear | ctrl_pe_acc_enable)))
        || mem_source_command_active_fast
        || !cdf_prepipe_empty;

    // Qualify a drain only after the source token, physical command boundary,
    // and Hybrid internal term stage have all been empty for a complete cycle.
    always @(posedge clk) begin
        if (!rst_n)
            hybrid_drain_q <= 1'b0;
        else
            hybrid_drain_q <= physical_command_pipe_empty
                && hybrid_pipeline_empty
                && !source_pe_command_active_fast;
    end
    assign hybrid_quiescent = hybrid_drain_q;

    assign raw_pe_idle = hybrid_quiescent
        && (ctrl_pe_acc_enable == 16'd0)
        && (ctrl_pe_acc_clear == 16'd0);
    assign gate_pe_idle = raw_pe_idle;
    assign membrane_pe_idle = hybrid_quiescent
        && (mem_pe_acc_enable == 16'd0)
        && (mem_pe_acc_clear == 16'd0);
    assign cdf_pe_idle = hybrid_quiescent
        && ((cdf_cmd_acc_clear_q | cdf_cmd_acc_enable_q) == 16'd0)
        && (cdf_pe_acc_enable == 16'd0)
        && (cdf_pe_acc_clear == 16'd0);
    // Reduce live commands in their owner domains before combining them with
    // the accepted-term tracker.  This preserves the exact derived-idle
    // contract without a sixteen-wide mux followed by another reduction.
    wire ctrl_pe_command_active;
    wire membrane_pe_command_active;
    wire membrane_pe_command_active_leaf;
    wire cdf_pe_command_active;
    assign ctrl_pe_command_active = ctrl_pe_command_owner
        && (|(ctrl_pe_acc_clear | ctrl_pe_acc_enable));
    assign membrane_pe_command_active_leaf =
        |(mem_pe_acc_clear | mem_pe_acc_enable);
    // This status path is not part of the physical command datapath.  A
    // conservative registered-phase decode may remain busy while a REQUEST
    // waits, but can never report idle before a membrane command drains.
    assign membrane_pe_command_active = owner_membrane
        && ((membrane_phase == 4'd1)
            || ((membrane_phase == 4'd2)
                && (gate_expected_mask_q != 16'd0))
            || (membrane_phase == 4'd8)
            || (membrane_phase == 4'd9)
            || (membrane_phase == 4'd10)
            || (membrane_phase == 4'd4)
            || (membrane_phase == 4'd5)
            || (membrane_response_command_fast
                && (phy_rq_out_lane_valid != 4'd0)));
    assign cdf_pe_command_active =
        |((cdf_pe_acc_clear | cdf_pe_acc_enable)
          | (cdf_cmd_acc_clear_q | cdf_cmd_acc_enable_q));
    assign hybrid_idle = hybrid_quiescent
        && !ctrl_pe_command_active
        && !(owner_membrane && membrane_owner_request)
        && !(owner_cdf && cdf_owner_request);

    // ---------------------------------------------------------------------
    // Gate context, strict request pairing, and canonical Local-RQ TAG20.
    // ---------------------------------------------------------------------
    reg                         gate_context_valid_q;
    reg [16*16-1:0]             gate_expected_tags_q;
    reg [2:0]                   gate_table_select_q;
    reg [15:0]                  gate_i_received_q;
    reg [15:0]                  gate_lambda_received_q;

    reg                         gate_pair_half_q;
    reg                         gate_pair_gate_q;
    reg [1:0]                   gate_pair_group_q;
    reg [3:0]                   gate_pair_mask_q;
    reg [4*16-1:0]              gate_pair_tags_q;

    wire gate_tile_fire;
    wire gate_pair_match;
    reg  gate_pair_tag_match;
    reg  gate_request_context_match;
    integer pair_lane;
    integer gate_context_check_lane;

    assign gate_tile_ready = rst_n && owner_gate
        && !gate_context_valid_q && !membrane_serializer_reserved_q
        && sigmoid_table_valid && !sig_cfg_busy_q
        && (gate_tile_lane_valid != 16'd0);
    assign gate_tile_fire = gate_tile_valid && gate_tile_ready;
    assign gate_collect_complete = gate_context_valid_q
        && ((gate_i_received_q & gate_expected_mask_q)
            == gate_expected_mask_q)
        && ((gate_lambda_received_q & gate_expected_mask_q)
            == gate_expected_mask_q);

    always @* begin
        gate_pair_tag_match = 1'b1;
        for (pair_lane = 0; pair_lane < 4; pair_lane = pair_lane + 1) begin
            if (gate_pair_mask_q[pair_lane]
                && (gate_rq_tags[pair_lane*16 +: 16]
                    != gate_pair_tags_q[pair_lane*16 +: 16])) begin
                gate_pair_tag_match = 1'b0;
            end
        end
    end

    always @* begin
        gate_request_context_match = gate_context_valid_q
            && (gate_rq_lane_valid
                == gate_expected_mask_q[gate_rq_group*4 +: 4]);
        for (gate_context_check_lane = 0; gate_context_check_lane < 4;
             gate_context_check_lane = gate_context_check_lane + 1) begin
            if (gate_rq_lane_valid[gate_context_check_lane]
                && gate_rq_tags[gate_context_check_lane*16 +: 16]
                   != gate_expected_tags_q[
                       (gate_rq_group*4+gate_context_check_lane)*16 +: 16]) begin
                gate_request_context_match = 1'b0;
            end
        end
    end

    assign gate_pair_match = gate_pair_half_q
        && gate_rq_component == COMPONENT_RECURRENT
        && gate_rq_gate == gate_pair_gate_q
        && gate_rq_group == gate_pair_group_q
        && gate_rq_lane_valid == gate_pair_mask_q
        && gate_pair_tag_match;

    wire gate_request_flow_legal;
    wire gate_group_pe_stable;
    assign gate_group_pe_stable =
        hybrid_quiescent
        && ((ctrl_pe_acc_clear | ctrl_pe_acc_enable) == 16'd0);
    // Only fields needed to enforce INPUT -> RECURRENT(same gate/group)
    // participate in admission.  Lane-mask/tag agreement remains a hard
    // protocol check, but not a high-fanout functional-ready dependency.
    assign gate_request_flow_legal = gate_context_valid_q
        && gate_group_pe_stable
        && ((!gate_pair_half_q
             && gate_rq_component == COMPONENT_INPUT)
            || (gate_pair_half_q
                && gate_rq_component == COMPONENT_RECURRENT
                && gate_rq_gate == gate_pair_gate_q
                && gate_rq_group == gate_pair_group_q));

    wire gate_request_legal;
    assign gate_request_legal = gate_request_context_match
        && gate_group_pe_stable
        && ((!gate_pair_half_q
             && gate_rq_component == COMPONENT_INPUT)
            || gate_pair_match);

    // ---------------------------------------------------------------------
    // Physical Local RQ mux and response demux.
    // ---------------------------------------------------------------------
    reg                         phy_rq_in_valid;
    wire                        phy_rq_in_ready;
    reg  [3:0]                  phy_rq_in_lane_valid;
    reg  [4*32-1:0]             phy_rq_value_in;
    reg  [4*32-1:0]             phy_rq_multiplier_in;
    reg  [4*6-1:0]              phy_rq_shift_in;
    reg  [4*20-1:0]             phy_rq_tag_in;
    wire [4*64-1:0]             phy_rq_value_out;
    wire [4*20-1:0]             phy_rq_tag_out;

    wire [3:0]                  mem_rq_in_lane_valid;
    wire [4*32-1:0]             mem_rq_value_in;
    wire [4*32-1:0]             mem_rq_multiplier_in;
    wire [4*6-1:0]              mem_rq_shift_in;
    wire [4*19-1:0]             mem_rq_tag_in;
    wire                        mem_rq_out_valid;
    wire                        mem_rq_out_ready;
    wire [3:0]                  mem_rq_out_lane_valid;
    wire [4*64-1:0]             mem_rq_value_out;
    wire [4*19-1:0]             mem_rq_tag_out;

    // Fixed one-stage timing cut from the membrane sequencer's sixteen-lane
    // parameter selection into the physical Local-RQ Bank.  The stage samples
    // rq_value together with the leaf handshake, before that same edge clears
    // the source Hybrid accumulator group.  The reserved Local-RQ pipeline is
    // continuously advancing, so this stage accepts/replaces every cycle.
    reg                         mem_rq_cmd_valid_q;
    reg  [3:0]                  mem_rq_cmd_lane_valid_q;
    reg  [4*32-1:0]             mem_rq_cmd_value_q;
    reg  [4*32-1:0]             mem_rq_cmd_multiplier_q;
    reg  [4*6-1:0]              mem_rq_cmd_shift_q;
    reg  [4*19-1:0]             mem_rq_cmd_tag_q;

    always @(posedge clk) begin
        if (!rst_n || (membrane_phase == 4'd0)) begin
            mem_rq_cmd_valid_q      <= 1'b0;
            mem_rq_cmd_lane_valid_q <= 4'd0;
            mem_rq_cmd_value_q      <= {4*32{1'b0}};
            mem_rq_cmd_multiplier_q <= {4*32{1'b0}};
            mem_rq_cmd_shift_q      <= {4*6{1'b0}};
            mem_rq_cmd_tag_q        <= {4*19{1'b0}};
        end else begin
            mem_rq_cmd_valid_q <= mem_rq_in_valid && mem_rq_in_ready;
            if (mem_rq_in_valid && mem_rq_in_ready) begin
                mem_rq_cmd_lane_valid_q <= mem_rq_in_lane_valid;
                mem_rq_cmd_value_q      <= mem_rq_value_in;
                mem_rq_cmd_multiplier_q <= mem_rq_multiplier_in;
                mem_rq_cmd_shift_q      <= mem_rq_shift_in;
                mem_rq_cmd_tag_q        <= mem_rq_tag_in;
            end
        end
    end

    integer membrane_fast_lane;
    integer membrane_fast_selected_lane;
    always @* begin
        membrane_gate_issue_fast = 16'd0;
        membrane_response_issue_fast = 16'd0;
        membrane_direct_value_fast = {16*32{1'b0}};

        if ((membrane_phase == 4'd2) || (membrane_phase == 4'd9))
            membrane_gate_issue_fast = gate_expected_mask_q;

        if (membrane_response_command_fast) begin
            membrane_response_issue_fast[
                phy_rq_tag_out[17:16]*4 +: 4] =
                phy_rq_out_lane_valid;
            for (membrane_fast_lane = 0; membrane_fast_lane < 4;
                 membrane_fast_lane = membrane_fast_lane + 1) begin
                membrane_fast_selected_lane =
                    phy_rq_tag_out[17:16] * 4 + membrane_fast_lane;
                membrane_direct_value_fast[
                    membrane_fast_selected_lane*32 +: 32] =
                    phy_rq_value_out[membrane_fast_lane*64 +: 32];
            end
        end
    end

    integer rq_lane;
    always @* begin
        phy_rq_in_valid      = 1'b0;
        phy_rq_in_lane_valid = 4'd0;
        phy_rq_value_in      = {4*32{1'b0}};
        phy_rq_multiplier_in = {4*32{1'b0}};
        phy_rq_shift_in      = {4*6{1'b0}};
        phy_rq_tag_in        = {4*20{1'b0}};

        if (owner_gate) begin
            // Wide user-tag comparisons are protocol checks, not part of
            // the ready chain.  The accepted schedule is still constrained
            // by context, lane mask, gate, component, and group.
            phy_rq_in_valid      = gate_rq_valid
                && !membrane_launch_window_q
                && gate_request_flow_legal;
            phy_rq_in_lane_valid = gate_rq_lane_valid;
            phy_rq_value_in      = gate_rq_value;
            phy_rq_multiplier_in = gate_rq_multiplier;
            phy_rq_shift_in      = gate_rq_shift;
            for (rq_lane = 0; rq_lane < 4; rq_lane = rq_lane + 1) begin
                phy_rq_tag_in[rq_lane*20 +: 20] = {
                    gate_rq_gate,
                    gate_rq_component,
                    gate_rq_group,
                    gate_rq_tags[rq_lane*16 +: 16]
                };
            end
        end else if (owner_membrane) begin
            phy_rq_in_valid      = mem_rq_cmd_valid_q;
            phy_rq_in_lane_valid = mem_rq_cmd_lane_valid_q;
            phy_rq_value_in      = mem_rq_cmd_value_q;
            phy_rq_multiplier_in = mem_rq_cmd_multiplier_q;
            phy_rq_shift_in      = mem_rq_cmd_shift_q;
            for (rq_lane = 0; rq_lane < 4; rq_lane = rq_lane + 1) begin
                phy_rq_tag_in[rq_lane*20 +: 20] = {
                    1'b0,
                    mem_rq_cmd_tag_q[rq_lane*19 +: 19]
                };
            end
        end
    end

    assign gate_rq_ready = owner_gate && !membrane_launch_window_q
        && gate_request_flow_legal
        && phy_rq_in_ready;
    // The membrane leaf requests its accumulator snapshot only after its
    // issue phase.  Use the registered all-PE drain proof rather than feeding
    // the leaf's live group/mask decode back into its own ready/state cone.
    // The clear generated by this handshake is captured on the same edge,
    // after the stable accumulator value has entered this command stage.
    assign mem_rq_in_ready = owner_membrane
        && hybrid_quiescent
        && (!mem_rq_cmd_valid_q || phy_rq_in_ready);

    pe_local_requant_bank_4lane #(
        .TAG_WIDTH(20)
    ) u_local_requant_bank (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(phy_rq_in_valid),
        .in_ready(phy_rq_in_ready),
        .in_lane_valid(phy_rq_in_lane_valid),
        .value_in(phy_rq_value_in),
        .multiplier_in(phy_rq_multiplier_in),
        .shift_in(phy_rq_shift_in),
        .tag_in(phy_rq_tag_in),
        .out_valid(phy_rq_out_valid),
        .out_ready(phy_rq_out_ready),
        .out_lane_valid(phy_rq_out_lane_valid),
        .value_out(phy_rq_value_out),
        .tag_out(phy_rq_tag_out)
    );

    assign mem_rq_out_valid = owner_membrane && phy_rq_out_valid;
    assign mem_rq_out_lane_valid = phy_rq_out_lane_valid;
    assign mem_rq_value_out = phy_rq_value_out;
    generate
        for (pe_lane = 0; pe_lane < 4; pe_lane = pe_lane + 1) begin : gen_mem_rq_tag_out
            assign mem_rq_tag_out[pe_lane*19 +: 19] =
                phy_rq_tag_out[pe_lane*20 +: 19];
        end
    endgenerate

    wire [19:0] gate_rq_head_tag;
    wire gate_rq_response_gate;
    wire gate_rq_response_component;
    wire [1:0] gate_rq_response_group;
    assign gate_rq_head_tag = phy_rq_tag_out[19:0];
    assign gate_rq_response_gate = gate_rq_head_tag[19];
    assign gate_rq_response_component = gate_rq_head_tag[18];
    assign gate_rq_response_group = gate_rq_head_tag[17:16];

    reg gate_bias_tag_match;
    integer bias_lane;
    always @* begin
        gate_bias_tag_match = 1'b1;
        for (bias_lane = 0; bias_lane < 4; bias_lane = bias_lane + 1) begin
            if (phy_rq_out_lane_valid[bias_lane]
                && gate_bias_tags[bias_lane*16 +: 16]
                   != phy_rq_tag_out[bias_lane*20 +: 16]) begin
                gate_bias_tag_match = 1'b0;
            end
        end
    end

    wire gate_bias_match;
    wire gate_bias_join_match;
    assign gate_bias_match = gate_bias_valid
        && gate_bias_gate == gate_rq_response_gate
        && gate_bias_group == gate_rq_response_group
        && gate_bias_lane_valid == phy_rq_out_lane_valid
        && gate_bias_tag_match;
    assign gate_bias_join_match = gate_bias_valid
        && gate_bias_gate == gate_rq_response_gate
        && gate_bias_group == gate_rq_response_group
        && gate_bias_lane_valid == phy_rq_out_lane_valid;

    // ---------------------------------------------------------------------
    // Physical Gate Postprocess mux.  Its opaque tag is {group,user_tag}.
    // ---------------------------------------------------------------------
    reg                         phy_post_in_valid;
    wire                        phy_post_in_ready;
    reg  [3:0]                  phy_post_in_lane_valid;
    reg  [4*64-1:0]             phy_post_value_in;
    reg                         phy_post_component_in;
    reg                         phy_post_gate_in;
    reg  [4*32-1:0]             phy_post_bias_in;
    reg  [4*18-1:0]             phy_post_tag_in;
    wire                        phy_post_out_valid;
    reg                         phy_post_out_ready;
    wire [3:0]                  phy_post_out_lane_valid;
    wire [4*8-1:0]              phy_post_value_out;
    wire                        phy_post_gate_out;
    wire [4*18-1:0]             phy_post_tag_out;

    wire                        mem_post_in_valid;
    wire                        mem_post_in_ready;
    wire [3:0]                  mem_post_in_lane_valid;
    wire [4*64-1:0]             mem_post_value_in;
    wire                        mem_post_component_in;
    wire                        mem_post_gate_in;
    wire [4*32-1:0]             mem_post_bias_in;
    wire [4*16-1:0]             mem_post_tag_in;
    reg                         mem_post_cmd_valid_q;
    reg [3:0]                   mem_post_cmd_lane_valid_q;
    reg [4*64-1:0]              mem_post_cmd_value_q;
    reg                         mem_post_cmd_component_q;
    reg                         mem_post_cmd_gate_q;
    reg [4*32-1:0]              mem_post_cmd_bias_q;
    reg [4*16-1:0]              mem_post_cmd_tag_q;
    reg [1:0]                   mem_post_cmd_group_q;
    wire                        mem_post_out_valid;
    wire                        mem_post_out_ready;
    wire [3:0]                  mem_post_out_lane_valid;
    wire [4*8-1:0]              mem_post_value_out;
    wire                        mem_post_gate_out;
    wire [4*16-1:0]             mem_post_tag_out;

    reg [1:0] mem_post_group_q;
    reg [1:0] mem_post_response_group_q;
    reg post_half_pending_q;
    wire mem_post_in_fire;
    wire mem_post_out_fire;
    wire mem_post_group_pe_stable;
    wire mem_post_accumulator_ready;

    assign mem_post_group_pe_stable =
        mem_final_acc_ready_q[mem_post_group_q];
    assign mem_post_accumulator_ready =
        (mem_post_component_in == COMPONENT_RECURRENT)
        || mem_post_group_pe_stable;

    // Fixed timing boundary between the immutable membrane control cone and
    // the 64-bit Postprocess adder.  Postprocess output is always drained in
    // this wrapper and the leaf emits the required INPUT/RECURRENT order, so
    // this register advances every cycle and is not an elastic FIFO.
    always @(posedge clk) begin
        if (!rst_n || !owner_membrane) begin
            mem_post_cmd_valid_q      <= 1'b0;
            mem_post_cmd_lane_valid_q <= 4'd0;
            mem_post_cmd_value_q      <= {4*64{1'b0}};
            mem_post_cmd_component_q  <= COMPONENT_INPUT;
            mem_post_cmd_gate_q       <= 1'b0;
            mem_post_cmd_bias_q       <= {4*32{1'b0}};
            mem_post_cmd_tag_q        <= {4*16{1'b0}};
            mem_post_cmd_group_q      <= 2'd0;
        end else begin
            mem_post_cmd_valid_q <= mem_post_in_fire;
            if (mem_post_in_fire) begin
                mem_post_cmd_lane_valid_q <= mem_post_in_lane_valid;
                mem_post_cmd_value_q      <= mem_post_value_in;
                mem_post_cmd_component_q  <= mem_post_component_in;
                mem_post_cmd_gate_q       <= mem_post_gate_in;
                mem_post_cmd_bias_q       <= mem_post_bias_in;
                mem_post_cmd_tag_q        <= mem_post_tag_in;
                mem_post_cmd_group_q      <= mem_post_group_q;
            end
        end
    end

    wire gate_response_needs_bias;
    wire gate_response_join_valid;
    // Strict in-order INPUT -> RECURRENT scheduling makes the accepted
    // Postprocess half-pair state the canonical expected response component.
    // Response metadata remains checked below, but does not enter the
    // elastic-ready path for legal traffic.
    assign gate_response_needs_bias = post_half_pending_q;
    assign gate_response_join_valid = phy_rq_out_valid
        && (!gate_response_needs_bias || gate_bias_valid);

    integer post_lane;
    always @* begin
        phy_post_in_valid      = 1'b0;
        phy_post_in_lane_valid = 4'd0;
        phy_post_value_in      = {4*64{1'b0}};
        phy_post_component_in  = COMPONENT_INPUT;
        phy_post_gate_in       = 1'b0;
        phy_post_bias_in       = {4*32{1'b0}};
        phy_post_tag_in        = {4*18{1'b0}};

        if (owner_gate) begin
            phy_post_in_valid      = gate_response_join_valid;
            phy_post_in_lane_valid = phy_rq_out_lane_valid;
            phy_post_value_in      = phy_rq_value_out;
            phy_post_component_in  = gate_response_needs_bias;
            phy_post_gate_in       = gate_rq_response_gate;
            if (gate_response_needs_bias)
                phy_post_bias_in = gate_bias_value;
            for (post_lane = 0; post_lane < 4; post_lane = post_lane + 1) begin
                phy_post_tag_in[post_lane*18 +: 18] =
                    phy_rq_tag_out[post_lane*20 +: 18];
            end
        end else if (owner_membrane) begin
            phy_post_in_valid      = mem_post_cmd_valid_q;
            phy_post_in_lane_valid = mem_post_cmd_lane_valid_q;
            phy_post_value_in      = mem_post_cmd_value_q;
            phy_post_component_in  = mem_post_cmd_component_q;
            phy_post_gate_in       = mem_post_cmd_gate_q;
            phy_post_bias_in       = mem_post_cmd_bias_q;
            for (post_lane = 0; post_lane < 4; post_lane = post_lane + 1) begin
                phy_post_tag_in[post_lane*18 +: 18] = {
                    mem_post_cmd_group_q,
                    mem_post_cmd_tag_q[post_lane*16 +: 16]
                };
            end
        end
    end

    // INPUT carries the live final Hybrid accumulator and must wait for the
    // delayed DIRECT command to commit.  The paired RECURRENT packet is a
    // literal zero and has no accumulator dependency.
    assign mem_post_in_ready = owner_membrane
        && mem_post_accumulator_ready;
    assign mem_post_in_fire = mem_post_in_valid && mem_post_in_ready;

    pe_gate_postprocess #(
        .TAG_WIDTH(18)
    ) u_gate_postprocess (
        .clk(clk),
        .rst_n(rst_n),
        .rq_in_valid(phy_post_in_valid),
        .rq_in_ready(phy_post_in_ready),
        .rq_lane_valid(phy_post_in_lane_valid),
        .rq_value_in(phy_post_value_in),
        .rq_component_in(phy_post_component_in),
        .rq_gate_in(phy_post_gate_in),
        .rq_bias_in(phy_post_bias_in),
        .rq_tag_in(phy_post_tag_in),
        .out_valid(phy_post_out_valid),
        .out_ready(phy_post_out_ready),
        .out_lane_valid(phy_post_out_lane_valid),
        .out_value(phy_post_value_out),
        .out_gate(phy_post_gate_out),
        .out_tag(phy_post_tag_out)
    );

    assign mem_post_out_valid = owner_membrane && phy_post_out_valid;
    assign mem_post_out_lane_valid = phy_post_out_lane_valid;
    assign mem_post_value_out = phy_post_value_out;
    assign mem_post_gate_out = phy_post_gate_out;
    generate
        for (pe_lane = 0; pe_lane < 4; pe_lane = pe_lane + 1) begin : gen_mem_post_tag_out
            assign mem_post_tag_out[pe_lane*16 +: 16] =
                phy_post_tag_out[pe_lane*18 +: 16];
        end
    endgenerate
    assign mem_post_out_fire = mem_post_out_valid && mem_post_out_ready;

    // ---------------------------------------------------------------------
    // Gate output routing, one physical sigmoid, and one-tile collectors.
    // ---------------------------------------------------------------------
    wire [1:0] gate_post_response_group;
    wire [1:0] gate_sig_response_group;
    assign gate_post_response_group = phy_post_tag_out[17:16];

    wire sig_in_valid;
    wire sig_in_ready;
    wire sig_out_valid;
    wire sig_out_ready;
    wire [3:0] sig_out_lane_valid;
    wire [31:0] sig_out_value;
    wire [4*18-1:0] sig_out_tag;
    wire sig_cfg_start_ready_leaf;
    wire sig_cfg_data_ready_leaf;
    wire sig_cfg_done_leaf;
    wire sig_table_valid_leaf;

    wire i_collector_ready;
    wire lambda_collector_ready;
    wire i_collector_fire;
    wire lambda_collector_fire;
    reg  i_packet_ok;
    reg  lambda_packet_ok;
    integer i_collector_lane;
    integer i_collector_index;
    integer lambda_collector_lane;
    integer lambda_collector_index;

    always @* begin
        i_packet_ok = gate_context_valid_q
            && (phy_post_out_lane_valid
                == gate_expected_mask_q[gate_post_response_group*4 +: 4]);
        for (i_collector_lane = 0; i_collector_lane < 4;
             i_collector_lane = i_collector_lane + 1) begin
            i_collector_index = gate_post_response_group * 4
                + i_collector_lane;
            if (phy_post_out_lane_valid[i_collector_lane]
                && (phy_post_tag_out[i_collector_lane*18 +: 16]
                    != gate_expected_tags_q[
                        i_collector_index*16 +: 16])) begin
                i_packet_ok = 1'b0;
            end
            if (phy_post_out_lane_valid[i_collector_lane]
                && gate_i_received_q[i_collector_index]) begin
                i_packet_ok = 1'b0;
            end
        end
    end

    assign i_collector_ready = gate_context_valid_q;
    wire i_collector_slot_ready;
    assign i_collector_slot_ready = gate_context_valid_q;
    // Controller gate 0 is the forget gate and must pass through Sigmoid to
    // become lambda.  Gate 1 is the signed cell candidate i_t and bypasses
    // Sigmoid into the direct collector.
    assign i_collector_fire = owner_gate && phy_post_out_valid
        && phy_post_gate_out && i_collector_slot_ready;

    assign sig_in_valid = owner_gate && phy_post_out_valid
        && !phy_post_gate_out && gate_context_valid_q;

    pe_sigmoid_lut_255 #(
        .TAG_WIDTH(18)
    ) u_sigmoid (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(sig_in_valid),
        .in_ready(sig_in_ready),
        .lane_valid_in(phy_post_out_lane_valid),
        .gate_in(phy_post_value_out),
        .tag_in(phy_post_tag_out),
        .table_select(gate_table_select_q),
        .out_valid(sig_out_valid),
        .out_ready(sig_out_ready),
        .lane_valid_out(sig_out_lane_valid),
        .lambda_out(sig_out_value),
        .tag_out(sig_out_tag),
        .cfg_start_valid(sigmoid_cfg_start_valid
                         && owner_q == OWNER_NONE
                         && owner_requests == OWNER_NONE
                         && !membrane_launch_window_q
                         && !sig_cfg_busy_q),
        .cfg_start_ready(sig_cfg_start_ready_leaf),
        .cfg_data_valid(sigmoid_cfg_data_valid && sig_cfg_busy_q),
        .cfg_data_ready(sig_cfg_data_ready_leaf),
        .cfg_data(sigmoid_cfg_data),
        .cfg_done(sig_cfg_done_leaf),
        .table_valid(sig_table_valid_leaf)
    );

    assign sigmoid_cfg_start_ready = (owner_q == OWNER_NONE)
        && (owner_requests == OWNER_NONE)
        && !membrane_launch_window_q
        && !sig_cfg_busy_q && sig_cfg_start_ready_leaf;
    assign sigmoid_cfg_data_ready = sig_cfg_busy_q
        && sig_cfg_data_ready_leaf;
    assign sigmoid_cfg_done = sig_cfg_done_leaf;
    assign sigmoid_table_valid = sig_table_valid_leaf;

    assign gate_sig_response_group = sig_out_tag[17:16];
    always @* begin
        lambda_packet_ok = gate_context_valid_q
            && (sig_out_lane_valid
                == gate_expected_mask_q[gate_sig_response_group*4 +: 4]);
        for (lambda_collector_lane = 0; lambda_collector_lane < 4;
             lambda_collector_lane = lambda_collector_lane + 1) begin
            lambda_collector_index = gate_sig_response_group * 4
                + lambda_collector_lane;
            if (sig_out_lane_valid[lambda_collector_lane]
                && (sig_out_tag[lambda_collector_lane*18 +: 16]
                    != gate_expected_tags_q[
                        lambda_collector_index*16 +: 16])) begin
                lambda_packet_ok = 1'b0;
            end
            if (sig_out_lane_valid[lambda_collector_lane]
                && gate_lambda_received_q[lambda_collector_index]) begin
                lambda_packet_ok = 1'b0;
            end
        end
    end

    assign lambda_collector_ready = gate_context_valid_q;
    wire lambda_collector_slot_ready;
    assign lambda_collector_slot_ready = gate_context_valid_q;
    // The lambda collector has one preallocated slot per lane/group and never
    // needs downstream backpressure.
    assign sig_out_ready = 1'b1;
    assign lambda_collector_fire = sig_out_valid && sig_out_ready;

    always @* begin
        // Gate outputs either enter an always-drained collector or a Sigmoid
        // whose output is also always drained.  Membrane likewise captures
        // exactly four responses in its private tile state.  Keeping this
        // physical output open removes a false cross-owner elastic-ready loop.
        phy_post_out_ready = 1'b1;
        phy_rq_out_ready = 1'b0;
        if (owner_gate) begin
            phy_rq_out_ready =
                !gate_response_needs_bias || gate_bias_valid;
        end else if (owner_membrane) begin
            // The membrane leaf holds a CX response until the matching CELL
            // raw accumulator has been snapshotted.  Honor that single-output
            // stall so a nonzero CX term cannot contaminate CELL requantization.
            phy_rq_out_ready = mem_rq_out_ready;
        end
    end

    assign gate_bias_ready = owner_gate && phy_rq_out_valid
        && gate_response_needs_bias;

    // ---------------------------------------------------------------------
    // Membrane sequencer and serializer reservation/context.
    // ---------------------------------------------------------------------
    wire membrane_owner_grant;
    wire membrane_start_ready_leaf;
    wire membrane_result_valid;
    wire membrane_result_ready;
    wire [15:0] membrane_result_lane_valid;
    wire [16*8-1:0] membrane_result_value;
    wire [16*16-1:0] membrane_result_tag;
    wire membrane_protocol_error;
    wire [7:0] membrane_rq_pending_mask;
    wire membrane_start_fire;


    wire gate_handoff_drained;
    wire serializer_storage_idle;
    wire membrane_launch_prerequisite;
    wire membrane_launch_hold_safe;
    wire membrane_launch_owner_ok;
    assign serializer_storage_idle = !serializer_context_valid_q
        && !serializer_busy && !serializer_out_valid;
    assign gate_handoff_drained = gate_pe_idle && local_rq_idle
        && postprocess_idle && sigmoid_idle
        && !gate_pair_half_q && !gate_rq_valid && !gate_bias_valid;

    assign membrane_launch_owner_ok = owner_gate
        || ((owner_q == OWNER_NONE) && (owner_requests == OWNER_NONE));
    assign membrane_launch_prerequisite = membrane_start_ready_leaf
        && gate_collect_complete
        && !membrane_serializer_reserved_q
        && serializer_storage_idle && (gate_expected_mask_q != 16'd0)
        && gate_handoff_drained
        && membrane_launch_owner_ok
        && !raw_owner_request && !cdf_owner_request
        && !sigmoid_cfg_start_valid;
    assign membrane_launch_hold_safe = gate_collect_complete
        && !membrane_serializer_reserved_q
        && serializer_storage_idle && (gate_expected_mask_q != 16'd0)
        && gate_handoff_drained && membrane_launch_owner_ok
        && !raw_owner_request && !cdf_owner_request
        && !sigmoid_cfg_start_valid;

    assign membrane_start_ready = membrane_start_ready_leaf
        && membrane_launch_window_q && membrane_launch_owner_ok
        && !raw_owner_request && !cdf_owner_request
        && !sigmoid_cfg_start_valid;
    assign membrane_start_fire = membrane_start_valid
        && membrane_start_ready;
    assign membrane_owner_grant = owner_membrane;

    always @(posedge clk) begin
        if (!rst_n) begin
            membrane_launch_window_q <= 1'b0;
        end else if (membrane_start_fire) begin
            membrane_launch_window_q <= 1'b0;
        end else if (!gate_context_valid_q) begin
            membrane_launch_window_q <= 1'b0;
        end else if (membrane_launch_window_q) begin
            if (!membrane_start_valid || !membrane_launch_hold_safe)
                membrane_launch_window_q <= 1'b0;
        end else if (membrane_start_valid
                     && membrane_launch_prerequisite) begin
            membrane_launch_window_q <= 1'b1;
        end
    end

    pe_membrane_sequencer #(
        .TAG_WIDTH(16)
    ) u_membrane_sequencer (
        .clk(clk),
        .rst_n(rst_n),
        .start_valid(membrane_start_fire),
        .start_ready(membrane_start_ready_leaf),
        .lane_valid_in(gate_expected_mask_q),
        .i_t_in(gate_i_values_q),
        .u_prev_in(membrane_u_prev),
        .lambda_in(gate_lambda_values_q),
        .cx_multiplier_in(membrane_cx_multiplier),
        .cx_shift_in(membrane_cx_shift),
        .cell_multiplier_in(membrane_cell_multiplier),
        .cell_shift_in(membrane_cell_shift),
        .tag_in(gate_expected_tags_q),
        .owner_request(membrane_owner_request),
        .owner_grant(membrane_owner_grant),
        .postprocess_idle(postprocess_idle),
        .pe_acc_clear(mem_pe_acc_clear),
        .pe_acc_enable(mem_pe_acc_enable),
        .pe_mode(mem_pe_mode),
        .pe_gate_u8(mem_pe_gate_u8),
        .pe_operand_b(mem_pe_operand_b),
        .pe_direct_value(mem_pe_direct_value),
        .pe_accumulator(phy_pe_accumulator),
        .rq_in_valid(mem_rq_in_valid),
        .rq_in_ready(mem_rq_in_ready),
        .rq_in_lane_valid(mem_rq_in_lane_valid),
        .rq_value_in(mem_rq_value_in),
        .rq_multiplier_in(mem_rq_multiplier_in),
        .rq_shift_in(mem_rq_shift_in),
        .rq_tag_in(mem_rq_tag_in),
        .rq_out_valid(mem_rq_out_valid),
        .rq_out_ready(mem_rq_out_ready),
        .rq_out_lane_valid(mem_rq_out_lane_valid),
        .rq_value_out(mem_rq_value_out),
        .rq_tag_out(mem_rq_tag_out),
        .post_in_valid(mem_post_in_valid),
        .post_in_ready(mem_post_in_ready),
        .post_in_lane_valid(mem_post_in_lane_valid),
        .post_value_in(mem_post_value_in),
        .post_component_in(mem_post_component_in),
        .post_gate_in(mem_post_gate_in),
        .post_bias_in(mem_post_bias_in),
        .post_tag_in(mem_post_tag_in),
        .post_out_valid(mem_post_out_valid),
        .post_out_ready(mem_post_out_ready),
        .post_out_lane_valid(mem_post_out_lane_valid),
        .post_value_out(mem_post_value_out),
        .post_gate_out(mem_post_gate_out),
        .post_tag_out(mem_post_tag_out),
        .result_valid(membrane_result_valid),
        .result_ready(membrane_result_ready),
        .result_lane_valid(membrane_result_lane_valid),
        .result_value(membrane_result_value),
        .result_tag(membrane_result_tag),
        .busy(membrane_busy),
        .done(membrane_done),
        .protocol_error(membrane_protocol_error),
        .phase(membrane_phase),
        .rq_pending_mask(membrane_rq_pending_mask)
    );

    // ---------------------------------------------------------------------
    // One physical 32-bit serializer, Membrane/Linear load selection.
    // ---------------------------------------------------------------------
    reg  [16*32-1:0] membrane_result_extended;
    integer extend_lane;
    always @* begin
        membrane_result_extended = {16*32{1'b0}};
        for (extend_lane = 0; extend_lane < 16;
             extend_lane = extend_lane + 1) begin
            membrane_result_extended[extend_lane*32 +: 32] = {
                {24{membrane_result_value[extend_lane*8 + 7]}},
                membrane_result_value[extend_lane*8 +: 8]
            };
        end
    end

    reg                         serializer_load_valid;
    wire                        serializer_load_ready;
    reg  [16*32-1:0]            serializer_values_in;
    reg  [15:0]                 serializer_lane_valid_in;
    reg  [INDEX_WIDTH-1:0]      serializer_base_index_in;
    reg  [16*16-1:0]            serializer_tags_in;
    reg                         serializer_last_in;
    reg                         serializer_load_op_kind;
    wire                        serializer_out_ready;
    wire signed [31:0]          serializer_value_out;
    wire [INDEX_WIDTH-1:0]      serializer_index_out;
    wire [15:0]                 serializer_tag_out;
    wire                        serializer_last_out;
    wire                        serializer_done;
    wire                        serializer_load_fire;
    wire                        linear_result_stable;

    assign linear_result_stable = physical_command_pipe_empty
        && (pe_pending_q == 16'd0)
        && ((ctrl_pe_acc_clear | ctrl_pe_acc_enable) == 16'd0);

    always @* begin
        serializer_load_valid    = 1'b0;
        serializer_values_in     = {16*32{1'b0}};
        serializer_lane_valid_in = 16'd0;
        serializer_base_index_in = {INDEX_WIDTH{1'b0}};
        serializer_tags_in       = {16*16{1'b0}};
        serializer_last_in       = 1'b0;
        serializer_load_op_kind  = OP_QBN;

        if (membrane_serializer_reserved_q) begin
            serializer_load_valid    = membrane_result_valid;
            serializer_values_in     = membrane_result_extended;
            serializer_lane_valid_in = membrane_result_lane_valid;
            serializer_base_index_in = membrane_base_index_q;
            serializer_tags_in       = membrane_result_tag;
            serializer_last_in       = membrane_logical_last_q;
            serializer_load_op_kind  = OP_QBN;
        end else if (owner_raw) begin
            serializer_load_valid    = linear_capture_window_q
                && linear_tile_valid
                && ((linear_tile_lane_valid != 16'd0)
                    || !linear_tile_logical_last);
            serializer_values_in     = phy_pe_accumulator;
            serializer_lane_valid_in = linear_tile_lane_valid;
            serializer_base_index_in = linear_tile_base_index;
            serializer_tags_in       = linear_tile_tags;
            serializer_last_in       = linear_tile_logical_last;
            serializer_load_op_kind  = OP_LINEAR;
        end
    end

    assign membrane_result_ready = membrane_serializer_reserved_q
        && serializer_load_ready;
    assign linear_tile_ready = owner_raw
        && !membrane_serializer_reserved_q
        && linear_capture_window_q
        && ((linear_tile_lane_valid != 16'd0)
            || !linear_tile_logical_last)
        && serializer_load_ready;
    assign serializer_load_fire = serializer_load_valid
        && serializer_load_ready;

    // Qualify a stable RAW result for one cycle before presenting it to the
    // serializer.  While the window is open the physical controller command
    // contribution is masked, so arbitrary downstream stalls cannot overwrite
    // the live accumulator tile.  This is a reservation bit, not data storage.
    always @(posedge clk) begin
        if (!rst_n || !owner_raw) begin
            linear_capture_window_q <= 1'b0;
        end else if (linear_tile_valid && linear_tile_ready) begin
            linear_capture_window_q <= 1'b0;
        end else if (!linear_capture_window_q
                     && linear_tile_valid && linear_result_stable
                     && ((linear_tile_lane_valid != 16'd0)
                         || !linear_tile_logical_last)) begin
            linear_capture_window_q <= 1'b1;
        end
    end

    pe_output_serializer #(
        .VALUE_WIDTH(32),
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(16)
    ) u_output_serializer (
        .clk(clk),
        .rst_n(rst_n),
        .load_valid(serializer_load_valid),
        .load_ready(serializer_load_ready),
        .values_in(serializer_values_in),
        .lane_valid_in(serializer_lane_valid_in),
        .base_index_in(serializer_base_index_in),
        .tags_in(serializer_tags_in),
        .load_last_in(serializer_last_in),
        .out_valid(serializer_out_valid),
        .out_ready(serializer_out_ready),
        .value_out(serializer_value_out),
        .index_out(serializer_index_out),
        .tag_out(serializer_tag_out),
        .last_out(serializer_last_out),
        .busy(serializer_busy),
        .done(serializer_done)
    );

    wire serializer_out_fire;
    assign serializer_out_fire = serializer_out_valid
        && serializer_out_ready;

    assign serializer_idle = !serializer_context_valid_q
        && !serializer_busy && !serializer_out_valid
        && !serializer_load_valid;

    // ---------------------------------------------------------------------
    // Atomic serializer/parameter/shared-RQ join.
    // ---------------------------------------------------------------------
    wire rq_param_match;
    wire shared_in_valid;
    wire shared_in_ready;
    wire shared_in_fire;
    wire shared_out_valid;
    reg  shared_out_ready;
    wire signed [7:0] shared_value_out;
    wire shared_op_kind_out;
    wire [INDEX_WIDTH-1:0] shared_index_out;
    wire [15:0] shared_tag_out;
    wire shared_last_out;
    wire shared_out_fire;

    assign rq_param_query_valid = serializer_out_valid
        && serializer_context_valid_q;
    assign rq_param_query_op_kind = serializer_op_kind_q;
    assign rq_param_query_index = serializer_index_out;
    assign rq_param_query_tag = serializer_tag_out;

    assign rq_param_match = rq_param_op_kind == serializer_op_kind_q
        && rq_param_index == serializer_index_out
        && rq_param_tag == serializer_tag_out;

    // Query-key equality is a provider protocol assertion.  Atomicity itself
    // depends only on both valids and the single shared-core ready: the
    // serializer scalar and its parameter are therefore accepted together,
    // without placing a wide tag/index comparator in the ready loop.
    assign shared_in_valid = serializer_out_valid
        && serializer_context_valid_q && rq_param_valid;
    assign serializer_out_ready = shared_in_ready
        && rq_param_valid;
    assign rq_param_ready = shared_in_ready
        && serializer_out_valid && serializer_context_valid_q;
    assign shared_in_fire = shared_in_valid && shared_in_ready;

    pe_shared_requant_engine #(
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(16)
    ) u_shared_requant_engine (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(shared_in_valid),
        .in_ready(shared_in_ready),
        .value_in(serializer_value_out),
        .op_kind_in(serializer_op_kind_q),
        .multiplier_in(rq_param_multiplier),
        .shift_in(rq_param_shift),
        .bias_in(rq_param_bias),
        .index_in(serializer_index_out),
        .tag_in(serializer_tag_out),
        .last_in(serializer_last_out),
        .out_valid(shared_out_valid),
        .out_ready(shared_out_ready),
        .value_out(shared_value_out),
        .op_kind_out(shared_op_kind_out),
        .index_out(shared_index_out),
        .tag_out(shared_tag_out),
        .last_out(shared_last_out)
    );

    // ---------------------------------------------------------------------
    // Linear output and registered exactly-once QBN two-way fork.
    // ---------------------------------------------------------------------
    reg                         qbn_hold_valid_q;
    reg                         qbn_state_pending_q;
    reg                         qbn_decision_pending_q;
    reg signed [7:0]            qbn_value_q;
    reg [INDEX_WIDTH-1:0]       qbn_index_q;
    reg [15:0]                  qbn_tag_q;
    reg                         qbn_last_q;

    wire qbn_state_fire;
    wire qbn_decision_valid;
    wire qbn_decision_ready;
    wire qbn_decision_fire;
    wire qbn_state_pending_after;
    wire qbn_decision_pending_after;
    wire qbn_retire_now;
    wire qbn_input_ready;
    wire qbn_input_fire;
    wire spike_event_valid;
    wire spike_event_ready;
    wire spike_event_spike;
    wire [INDEX_WIDTH-1:0] spike_event_index;
    wire [15:0] spike_event_tag;
    wire spike_event_last;

    assign state_write_valid = qbn_hold_valid_q && qbn_state_pending_q;
    assign state_write_value = qbn_value_q;
    assign state_write_index = qbn_index_q;
    assign state_write_tag   = qbn_tag_q;
    assign state_write_last  = qbn_last_q;
    assign qbn_state_fire = state_write_valid && state_write_ready;

    // A decision may not commit before its matching dense state write.
    assign qbn_decision_valid = qbn_hold_valid_q
        && qbn_decision_pending_q
        && (!qbn_state_pending_q || state_write_ready);
    assign qbn_decision_fire = qbn_decision_valid
        && qbn_decision_ready;

    assign qbn_state_pending_after = qbn_state_pending_q
        && !qbn_state_fire;
    assign qbn_decision_pending_after = qbn_decision_pending_q
        && !qbn_decision_fire;
    assign qbn_retire_now = qbn_hold_valid_q
        && !qbn_state_pending_after && !qbn_decision_pending_after;
    assign qbn_input_ready = !qbn_hold_valid_q || qbn_retire_now;
    assign qbn_input_fire = shared_out_valid && !shared_op_kind_out
        && qbn_input_ready;
    assign qbn_fork_idle = !qbn_hold_valid_q;

    pe_spike_decision #(
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(16)
    ) u_spike_decision (
        .in_valid(qbn_decision_valid),
        .in_ready(qbn_decision_ready),
        .state_q_in(qbn_value_q),
        .index_in(qbn_index_q),
        .tag_in(qbn_tag_q),
        .last_in(qbn_last_q),
        .out_valid(spike_event_valid),
        .out_ready(spike_event_ready),
        .spike_out(spike_event_spike),
        .index_out(spike_event_index),
        .tag_out(spike_event_tag),
        .last_out(spike_event_last)
    );

    pe_active_index_writer #(
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(16)
    ) u_active_index_writer (
        .event_valid(spike_event_valid),
        .event_ready(spike_event_ready),
        .spike_in(spike_event_spike),
        .index_in(spike_event_index),
        .tag_in(spike_event_tag),
        .last_in(spike_event_last),
        .mem_cmd_valid(active_cmd_valid),
        .mem_cmd_ready(active_cmd_ready),
        .mem_cmd_write(active_cmd_write),
        .mem_cmd_index(active_cmd_index),
        .mem_cmd_tag(active_cmd_tag),
        .mem_cmd_finalize(active_cmd_finalize)
    );

    assign coefficient_valid = shared_out_valid && shared_op_kind_out;
    assign coefficient_value = shared_value_out;
    assign coefficient_index = shared_index_out;
    assign coefficient_tag   = shared_tag_out;
    assign coefficient_last  = shared_last_out;

    always @* begin
        if (!shared_out_valid)
            shared_out_ready = 1'b1;
        else if (shared_op_kind_out == OP_LINEAR)
            shared_out_ready = coefficient_ready;
        else
            shared_out_ready = qbn_input_ready;
    end
    assign shared_out_fire = shared_out_valid && shared_out_ready;

    // ---------------------------------------------------------------------
    // CDF sequencer using the same physical Hybrid PEs.
    // ---------------------------------------------------------------------
    wire cdf_owner_grant;
    wire cdf_protocol_error;
    wire cdf_result_valid_leaf;
    wire cdf_result_ready_leaf;
    wire cdf_done_leaf;
    wire cdf_result_committed;
    assign cdf_owner_grant = owner_cdf;
    // The leaf may enter RESULT one cycle before the registered boundary
    // command has committed through the Hybrid PE's internal term pipeline.
    // Hold its result handshake until both stages are empty; payload remains
    // resident in the PE accumulators under any external backpressure.
    assign cdf_result_committed = cdf_prepipe_empty
        && hybrid_quiescent;
    assign cdf_result_valid = cdf_result_valid_leaf
        && cdf_result_committed;
    assign cdf_result_ready_leaf = cdf_result_ready
        && cdf_result_committed;
    assign cdf_done = cdf_done_leaf;

    pe_cdf_sequencer #(
        .BIN_INDEX_WIDTH(BIN_INDEX_WIDTH),
        .TAG_WIDTH(16)
    ) u_cdf_sequencer (
        .clk(clk),
        .rst_n(rst_n),
        .start_valid(cdf_start_valid),
        .start_ready(cdf_start_ready),
        .order_in(cdf_order),
        .bin_valid_in(cdf_bin_valid),
        .bin_base_in(cdf_bin_base),
        .band_in(cdf_band),
        .tag_in(cdf_tag),
        .owner_request(cdf_owner_request),
        .owner_grant(cdf_owner_grant),
        .tap_valid(cdf_tap_valid),
        .tap_ready(cdf_tap_ready),
        .tap_index_in(cdf_tap_index),
        .spectrum_real_in(cdf_spectrum_real),
        .spectrum_imag_in(cdf_spectrum_imag),
        .coefficient_real_in(cdf_coefficient_real),
        .coefficient_imag_in(cdf_coefficient_imag),
        .pe_acc_clear(cdf_pe_acc_clear),
        .pe_acc_enable(cdf_pe_acc_enable),
        .pe_mode(cdf_pe_mode),
        .pe_operand_a(cdf_pe_operand_a),
        .pe_operand_b(cdf_pe_operand_b),
        .pe_accumulator(phy_pe_accumulator),
        .pe_overflow(phy_pe_overflow),
        .result_valid(cdf_result_valid_leaf),
        .result_ready(cdf_result_ready_leaf),
        .result_real(cdf_result_real),
        .result_imag(cdf_result_imag),
        .result_bin_valid(cdf_result_bin_valid),
        .result_order(cdf_result_order),
        .result_bin_base(cdf_result_bin_base),
        .result_band(cdf_result_band),
        .result_tag(cdf_result_tag),
        .busy(cdf_busy),
        .done(cdf_done_leaf),
        .protocol_error(cdf_protocol_error),
        .phase(cdf_phase),
        .active_tap_index(cdf_active_tap_index)
    );

    // ---------------------------------------------------------------------
    // Handshake-derived outstanding accounting and shared-resource idles.
    // ---------------------------------------------------------------------
    wire phy_rq_in_fire;
    wire phy_rq_out_fire;
    wire phy_post_in_fire;
    wire phy_post_out_fire;
    wire sig_in_fire;
    wire sig_out_fire;

    reg [4:0] rq_count_q;
    reg [4:0] post_pair_count_q;
    reg [1:0] sigmoid_count_q;
    reg [4:0] shared_count_q;

    assign phy_rq_in_fire = phy_rq_in_valid && phy_rq_in_ready;
    assign phy_rq_out_fire = phy_rq_out_valid && phy_rq_out_ready;
    assign phy_post_in_fire = phy_post_in_valid && phy_post_in_ready;
    assign phy_post_out_fire = phy_post_out_valid && phy_post_out_ready;
    assign sig_in_fire = sig_in_valid && sig_in_ready;
    assign sig_out_fire = sig_out_valid && sig_out_ready;

    assign local_rq_outstanding = rq_count_q;
    assign postprocess_outstanding = post_pair_count_q;
    assign shared_rq_outstanding = shared_count_q;

    // Accepted-transaction counts are the canonical drain state.  Boundary
    // valids are qualified separately by each owner's release predicate;
    // excluding them here keeps the long elastic ready chain out of owner CE.
    assign local_rq_idle = (rq_count_q == 5'd0)
        && !mem_rq_cmd_valid_q;
    assign postprocess_idle = !mem_post_cmd_valid_q
        && !post_half_pending_q
        && (post_pair_count_q == 5'd0);
    assign sigmoid_idle = (sigmoid_count_q == 2'd0)
        && !sig_cfg_busy_q;
    assign shared_rq_idle = (shared_count_q == 5'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            rq_count_q <= 5'd0;
            post_pair_count_q <= 5'd0;
            post_half_pending_q <= 1'b0;
            sigmoid_count_q <= 2'd0;
            shared_count_q <= 5'd0;
        end else begin
            case ({phy_rq_in_fire, phy_rq_out_fire})
                2'b10: rq_count_q <= rq_count_q + 5'd1;
                2'b01: rq_count_q <= rq_count_q - 5'd1;
                default: rq_count_q <= rq_count_q;
            endcase

            if (phy_post_in_fire) begin
                if (phy_post_component_in == COMPONENT_INPUT)
                    post_half_pending_q <= 1'b1;
                else
                    post_half_pending_q <= 1'b0;
            end
            case ({phy_post_in_fire
                   && phy_post_component_in == COMPONENT_RECURRENT,
                   phy_post_out_fire})
                2'b10: post_pair_count_q <= post_pair_count_q + 5'd1;
                2'b01: post_pair_count_q <= post_pair_count_q - 5'd1;
                default: post_pair_count_q <= post_pair_count_q;
            endcase

            case ({sig_in_fire, sig_out_fire})
                2'b10: sigmoid_count_q <= sigmoid_count_q + 2'd1;
                2'b01: sigmoid_count_q <= sigmoid_count_q - 2'd1;
                default: sigmoid_count_q <= sigmoid_count_q;
            endcase

            case ({shared_in_fire, shared_out_fire})
                2'b10: shared_count_q <= shared_count_q + 5'd1;
                2'b01: shared_count_q <= shared_count_q - 5'd1;
                default: shared_count_q <= shared_count_q;
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // Context state updates.
    // ---------------------------------------------------------------------
    integer context_lane;
    integer context_index;
    always @(posedge clk) begin
        if (!rst_n) begin
            gate_context_valid_q <= 1'b0;
            gate_expected_mask_q <= 16'd0;
            gate_expected_tags_q <= {16*16{1'b0}};
            gate_table_select_q <= 3'd0;
            gate_i_received_q <= 16'd0;
            gate_lambda_received_q <= 16'd0;
            gate_i_values_q <= {16*8{1'b0}};
            gate_lambda_values_q <= {16*8{1'b0}};
            membrane_u_prev_fast_q <= {16*8{1'b0}};
            gate_pair_half_q <= 1'b0;
            gate_pair_gate_q <= 1'b0;
            gate_pair_group_q <= 2'd0;
            gate_pair_mask_q <= 4'd0;
            gate_pair_tags_q <= {4*16{1'b0}};
            mem_post_group_q <= 2'd0;
            mem_post_response_group_q <= 2'd0;
            membrane_serializer_reserved_q <= 1'b0;
            membrane_base_index_q <= {INDEX_WIDTH{1'b0}};
            membrane_logical_last_q <= 1'b0;
            serializer_context_valid_q <= 1'b0;
            serializer_op_kind_q <= OP_QBN;
            sig_cfg_busy_q <= 1'b0;
        end else begin
            if (gate_tile_fire) begin
                gate_context_valid_q <= 1'b1;
                gate_expected_mask_q <= gate_tile_lane_valid;
                gate_expected_tags_q <= gate_tile_tags;
                gate_table_select_q <= gate_tile_table_select;
                gate_i_received_q <= 16'd0;
                gate_lambda_received_q <= 16'd0;
                gate_i_values_q <= {16*8{1'b0}};
                gate_lambda_values_q <= {16*8{1'b0}};
            end

            if (gate_rq_valid && gate_rq_ready) begin
                if (gate_rq_component == COMPONENT_INPUT) begin
                    gate_pair_half_q <= 1'b1;
                    gate_pair_gate_q <= gate_rq_gate;
                    gate_pair_group_q <= gate_rq_group;
                    gate_pair_mask_q <= gate_rq_lane_valid;
                    gate_pair_tags_q <= gate_rq_tags;
                end else begin
                    gate_pair_half_q <= 1'b0;
                end
            end

            if (i_collector_fire) begin
                for (context_lane = 0; context_lane < 4;
                     context_lane = context_lane + 1) begin
                    context_index = gate_post_response_group * 4
                        + context_lane;
                    if (phy_post_out_lane_valid[context_lane]) begin
                        gate_i_values_q[context_index*8 +: 8] <=
                            phy_post_value_out[context_lane*8 +: 8];
                        gate_i_received_q[context_index] <= 1'b1;
                    end
                end
            end

            if (lambda_collector_fire) begin
                for (context_lane = 0; context_lane < 4;
                     context_lane = context_lane + 1) begin
                    context_index = gate_sig_response_group * 4
                        + context_lane;
                    if (sig_out_lane_valid[context_lane]) begin
                        gate_lambda_values_q[context_index*8 +: 8] <=
                            sig_out_value[context_lane*8 +: 8];
                        gate_lambda_received_q[context_index] <= 1'b1;
                    end
                end
            end

            if (membrane_start_fire) begin
                membrane_u_prev_fast_q <= membrane_u_prev;
                gate_context_valid_q <= 1'b0;
                gate_pair_half_q <= 1'b0;
                mem_post_group_q <= 2'd0;
                mem_post_response_group_q <= 2'd0;
                membrane_serializer_reserved_q <= 1'b1;
                membrane_base_index_q <= membrane_base_index;
                membrane_logical_last_q <= membrane_logical_last;
            end else begin
                if (mem_post_in_fire
                    && mem_post_component_in == COMPONENT_RECURRENT)
                    mem_post_group_q <= mem_post_group_q + 2'd1;
                if (mem_post_out_fire)
                    mem_post_response_group_q <=
                        mem_post_response_group_q + 2'd1;
            end

            if (serializer_load_fire) begin
                if (serializer_lane_valid_in != 16'd0) begin
                    serializer_context_valid_q <= 1'b1;
                    serializer_op_kind_q <= serializer_load_op_kind;
                end else begin
                    serializer_context_valid_q <= 1'b0;
                end
                if (membrane_serializer_reserved_q)
                    membrane_serializer_reserved_q <= 1'b0;
            end else if (serializer_done) begin
                serializer_context_valid_q <= 1'b0;
            end

            if (sigmoid_cfg_start_valid && sigmoid_cfg_start_ready)
                sig_cfg_busy_q <= 1'b1;
            if (sig_cfg_done_leaf)
                sig_cfg_busy_q <= 1'b0;
        end
    end

    // QBN fork state is kept separate so a retired token may be replaced on
    // the same edge, preserving no-stall steady-state II=1.
    always @(posedge clk) begin
        if (!rst_n) begin
            qbn_hold_valid_q <= 1'b0;
            qbn_state_pending_q <= 1'b0;
            qbn_decision_pending_q <= 1'b0;
            qbn_value_q <= 8'sd0;
            qbn_index_q <= {INDEX_WIDTH{1'b0}};
            qbn_tag_q <= 16'd0;
            qbn_last_q <= 1'b0;
        end else if (qbn_input_fire) begin
            qbn_hold_valid_q <= 1'b1;
            qbn_state_pending_q <= 1'b1;
            qbn_decision_pending_q <= 1'b1;
            qbn_value_q <= shared_value_out;
            qbn_index_q <= shared_index_out;
            qbn_tag_q <= shared_tag_out;
            qbn_last_q <= shared_last_out;
        end else if (qbn_hold_valid_q) begin
            qbn_state_pending_q <= qbn_state_pending_after;
            qbn_decision_pending_q <= qbn_decision_pending_after;
            if (qbn_retire_now)
                qbn_hold_valid_q <= 1'b0;
        end
    end

    // ---------------------------------------------------------------------
    // Registered all-or-none owner lock.  Every handoff passes through NONE.
    // ---------------------------------------------------------------------
    wire global_acquire_safe;
    wire raw_release_safe;
    wire gate_release_safe;
    wire membrane_release_safe;
    wire cdf_release_safe;

    assign owner_requests = {
        cdf_owner_request,
        membrane_owner_request,
        gate_owner_request,
        raw_owner_request
    };
    assign global_acquire_safe = hybrid_quiescent
        && ((cdf_cmd_acc_clear_q | cdf_cmd_acc_enable_q) == 16'd0)
        && local_rq_idle
        && postprocess_idle && sigmoid_idle
        && !sigmoid_cfg_start_valid && !membrane_launch_window_q;
    assign raw_release_safe = raw_pe_idle && !linear_tile_valid;

    wire gate_collection_handed_off;
    assign gate_collection_handed_off = gate_collect_complete
        || membrane_serializer_reserved_q || !gate_context_valid_q;

    assign gate_release_safe = gate_handoff_drained
        && gate_collection_handed_off;
    // Once a leaf drops owner_request it is back in IDLE, so its command
    // outputs are self-zero.  The accepted-term tracker is then the complete
    // Hybrid drain condition and avoids re-entering a leaf ready cone here.
    assign membrane_release_safe = hybrid_quiescent && local_rq_idle
        && postprocess_idle && !membrane_result_valid;
    assign cdf_release_safe = cdf_prepipe_empty
        && hybrid_quiescent && !cdf_result_valid;

    assign compute_idle = owner_q == OWNER_NONE
        && owner_requests == OWNER_NONE
        && global_acquire_safe && !membrane_start_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            owner_q <= OWNER_NONE;
        end else begin
            case (owner_q)
                OWNER_NONE: begin
                    case (owner_requests)
                        OWNER_RAW:
                            if (global_acquire_safe)
                                owner_q <= OWNER_RAW;
                        OWNER_GATE:
                            if (global_acquire_safe
                                && !gate_context_valid_q
                                && sig_table_valid_leaf)
                                owner_q <= OWNER_GATE;
                        OWNER_MEMBRANE:
                            if (global_acquire_safe
                                && membrane_serializer_reserved_q)
                                owner_q <= OWNER_MEMBRANE;
                        OWNER_CDF:
                            if (global_acquire_safe)
                                owner_q <= OWNER_CDF;
                        default: owner_q <= OWNER_NONE;
                    endcase
                end

                OWNER_RAW: begin
                    if (!raw_owner_request && raw_release_safe)
                        owner_q <= OWNER_NONE;
                end

                OWNER_GATE: begin
                    if (!gate_owner_request && gate_release_safe)
                        owner_q <= OWNER_NONE;
                end

                OWNER_MEMBRANE: begin
                    if (!membrane_owner_request
                        && membrane_release_safe)
                        owner_q <= OWNER_NONE;
                end

                OWNER_CDF: begin
                    if (!cdf_owner_request && cdf_release_safe)
                        owner_q <= OWNER_NONE;
                end

                default: owner_q <= OWNER_NONE;
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // Sticky protocol/error aggregation and simulation-only hard assertions.
    // ---------------------------------------------------------------------
    (* keep = "true" *) reg protocol_owner_error_q;
    (* keep = "true" *) reg protocol_gate_error_q;
    (* keep = "true" *) reg protocol_stream_error_q;
    (* keep = "true" *) reg protocol_compute_error_q;
    reg serializer_index_error_q;
    reg rq_header_mismatch;
    reg mem_post_tag_mismatch;
    integer rq_header_lane;
    integer mem_header_lane;

    always @* begin
        rq_header_mismatch = 1'b0;
        for (rq_header_lane = 1; rq_header_lane < 4;
             rq_header_lane = rq_header_lane + 1) begin
            if (phy_rq_out_valid
                && phy_rq_tag_out[rq_header_lane*20 + 16 +: 4]
                != phy_rq_tag_out[16 +: 4])
                rq_header_mismatch = 1'b1;
        end
    end

    always @* begin
        mem_post_tag_mismatch = 1'b0;
        for (mem_header_lane = 0; mem_header_lane < 4;
             mem_header_lane = mem_header_lane + 1) begin
            if (mem_post_out_valid
                && phy_post_out_lane_valid[mem_header_lane]
                && phy_post_tag_out[mem_header_lane*18 + 16 +: 2]
                   != mem_post_response_group_q)
                mem_post_tag_mismatch = 1'b1;
        end
    end

    wire owner_request_conflict;
    wire gate_request_error;
    wire gate_request_control_error;
    wire gate_bias_error;
    wire gate_bias_control_error;
    wire parameter_error;
    wire counter_error;
    wire serializer_error;
    wire serializer_index_error;
    wire gate_collector_error;
    wire post_order_error;
    wire gate_response_component_error;
    wire sigmoid_cfg_owner_conflict;
    wire membrane_launch_violation;
    wire linear_capture_violation;

    function [3:0] highest_lane16;
        input [15:0] mask;
        integer highest_lane_index;
        begin
            highest_lane16 = 4'd0;
            for (highest_lane_index = 0; highest_lane_index < 16;
                 highest_lane_index = highest_lane_index + 1) begin
                if (mask[highest_lane_index])
                    highest_lane16 = highest_lane_index[3:0];
            end
        end
    endfunction

    wire [INDEX_WIDTH:0] serializer_index_sum;
    assign serializer_index_sum = {1'b0, serializer_base_index_in}
        + {{(INDEX_WIDTH-3){1'b0}},
           highest_lane16(serializer_lane_valid_in)};

    assign owner_request_conflict = owner_q == OWNER_NONE
        && owner_requests != OWNER_NONE
        && owner_requests != OWNER_RAW
        && owner_requests != OWNER_GATE
        && owner_requests != OWNER_MEMBRANE
        && owner_requests != OWNER_CDF;
    assign sigmoid_cfg_owner_conflict = owner_q == OWNER_NONE
        && sigmoid_cfg_start_valid && owner_requests != OWNER_NONE;
    assign membrane_launch_violation = membrane_launch_window_q
        && (((ctrl_pe_acc_clear | ctrl_pe_acc_enable) != 16'd0)
            || gate_rq_valid || gate_bias_valid || gate_tile_valid
            || raw_owner_request || cdf_owner_request
            || sigmoid_cfg_start_valid);
    assign linear_capture_violation = linear_capture_window_q
        && ((ctrl_pe_acc_clear | ctrl_pe_acc_enable) != 16'd0);
    assign gate_request_error = owner_gate && gate_rq_valid
        && !gate_request_legal;
    assign gate_request_control_error = owner_gate && gate_rq_valid
        && !gate_request_flow_legal;
    assign gate_bias_error = owner_gate && phy_rq_out_valid
        && gate_response_needs_bias && gate_bias_valid
        && !gate_bias_match;
    assign gate_bias_control_error = owner_gate && phy_rq_out_valid
        && gate_response_needs_bias && gate_bias_valid
        && !gate_bias_join_match;
    assign parameter_error = rq_param_valid && serializer_out_valid
        && serializer_context_valid_q && !rq_param_match;
    assign counter_error = (phy_rq_out_valid && rq_count_q == 5'd0)
        || (phy_post_out_valid && post_pair_count_q == 5'd0)
        || (sig_out_valid && sigmoid_count_q == 2'd0)
        || (shared_out_valid && shared_count_q == 5'd0)
        || (rq_count_q > 5'd9)
        || (post_pair_count_q > 5'd4)
        || (sigmoid_count_q > 2'd1)
        || (shared_count_q > 5'd14);
    assign serializer_error = (gate_tile_valid
        && gate_tile_lane_valid == 16'd0)
        || (linear_tile_valid && linear_tile_logical_last
            && linear_tile_lane_valid == 16'd0)
        || (serializer_load_valid && serializer_last_in
            && serializer_lane_valid_in == 16'd0);
    assign serializer_index_error = serializer_load_valid
        && (serializer_lane_valid_in != 16'd0)
        && serializer_index_sum[INDEX_WIDTH];
    assign gate_collector_error =
        (owner_gate && phy_post_out_valid && phy_post_gate_out
         && !i_packet_ok)
        || (owner_gate && sig_out_valid && !lambda_packet_ok);
    assign gate_response_component_error = owner_gate
        && phy_rq_out_valid
        && (gate_rq_response_component != gate_response_needs_bias);
    assign post_order_error = phy_post_in_valid
        && ((phy_post_component_in == COMPONENT_INPUT
             && post_half_pending_q)
            || (phy_post_component_in == COMPONENT_RECURRENT
                && !post_half_pending_q));

    always @(posedge clk) begin
        if (!rst_n) begin
            protocol_owner_error_q <= 1'b0;
            protocol_gate_error_q <= 1'b0;
            protocol_stream_error_q <= 1'b0;
            protocol_compute_error_q <= 1'b0;
            serializer_index_error_q <= 1'b0;
        end else begin
            serializer_index_error_q <= serializer_index_error;
            if (owner_request_conflict || sigmoid_cfg_owner_conflict
                || membrane_launch_violation || linear_capture_violation)
                protocol_owner_error_q <= 1'b1;
            if (gate_request_control_error || gate_bias_control_error
                || post_order_error
                || gate_response_component_error
                || rq_header_mismatch || mem_post_tag_mismatch)
                protocol_gate_error_q <= 1'b1;
            if (counter_error || serializer_error
                || serializer_index_error_q)
                protocol_stream_error_q <= 1'b1;
            if (overflow_any)
                protocol_compute_error_q <= 1'b1;
        end
    end

    assign protocol_error = protocol_owner_error_q
        || protocol_gate_error_q || protocol_stream_error_q
        || protocol_compute_error_q
        || membrane_protocol_error || cdf_protocol_error;

`ifndef SYNTHESIS
    integer pe_source_check_lane;

    initial begin
        if (INDEX_WIDTH < 5)
            $fatal(1, "pe_array_datapath INDEX_WIDTH too small");
        if (BIN_INDEX_WIDTH < 8)
            $fatal(1, "pe_array_datapath BIN_INDEX_WIDTH too small");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if ((owner_q != OWNER_NONE) && (owner_q != OWNER_RAW)
                && (owner_q != OWNER_GATE)
                && (owner_q != OWNER_MEMBRANE)
                && (owner_q != OWNER_CDF))
                $fatal(1, "pe_array_datapath owner is not one-hot-or-zero");
            if ((phy_pe_acc_clear & phy_pe_acc_enable) != 16'd0)
                $fatal(1, "pe_array_datapath PE clear/enable collision");
            if ((source_pe_acc_clear & source_pe_acc_enable) != 16'd0)
                $fatal(1, "pe_array_datapath source PE clear/enable collision");
            if ((|(ctrl_pe_issue & membrane_pe_issue))
                || (|(ctrl_pe_issue & cdf_pe_issue))
                || (|(membrane_pe_issue & cdf_pe_issue)))
                $fatal(1, "pe_array_datapath multiple PE command sources");
            if (membrane_gate_command_fast
                && membrane_response_command_fast)
                $fatal(1, "pe_array_datapath overlapping membrane commands");
            if (!physical_command_pipe_empty
                && (pe_cmd_owner_q != owner_q))
                $fatal(1, "pe_array_datapath owner changed with PE command pending");
            if (owner_request_conflict)
                $fatal(1, "pe_array_datapath simultaneous owner requests");
            if (sigmoid_cfg_owner_conflict)
                $fatal(1, "pe_array_datapath sigmoid config/owner conflict");
            if (membrane_launch_violation)
                $fatal(1, "pe_array_datapath traffic during membrane launch window");
            if (linear_capture_violation)
                $fatal(1, "pe_array_datapath PE command during Linear capture window");
            if (gate_request_error)
                $fatal(1, "pe_array_datapath malformed gate RQ pair");
            if (gate_bias_error)
                $fatal(1, "pe_array_datapath gate bias key mismatch");
            if (parameter_error)
                $fatal(1, "pe_array_datapath shared-RQ parameter key mismatch");
            if (serializer_index_error)
                $fatal(1, "pe_array_datapath serializer index wraps");
            if (gate_collector_error)
                $fatal(1, "pe_array_datapath gate collector metadata mismatch");
            if (counter_error)
                $fatal(1, "pe_array_datapath outstanding counter violation");
            if (post_order_error)
                $fatal(1, "pe_array_datapath postprocess component ordering error");
            if (gate_response_component_error)
                $fatal(1, "pe_array_datapath Local-RQ component/order mismatch");
            if (rq_header_mismatch)
                $fatal(1, "pe_array_datapath Local-RQ lane header mismatch");
            if (mem_post_tag_mismatch)
                $fatal(1, "pe_array_datapath membrane post group mismatch");
            for (pe_source_check_lane = 0; pe_source_check_lane < 16;
                 pe_source_check_lane = pe_source_check_lane + 1) begin
                if (owner_membrane
                    && membrane_pe_issue[pe_source_check_lane]
                    && (source_pe_mode[pe_source_check_lane*2 +: 2]
                        != mem_pe_mode))
                    $fatal(1, "pe_array_datapath membrane fast mode mismatch");
                if (owner_membrane
                    && membrane_gate_issue_fast[pe_source_check_lane]
                    && ((membrane_gate_u8_fast[
                            pe_source_check_lane*8 +: 8]
                         != mem_pe_gate_u8[pe_source_check_lane*8 +: 8])
                        || (membrane_operand_b_fast[
                                pe_source_check_lane*8 +: 8]
                            != mem_pe_operand_b[
                                pe_source_check_lane*8 +: 8])))
                    $fatal(1, "pe_array_datapath membrane fast payload mismatch");
            end
            if (owner_membrane
                && (membrane_pe_issue != mem_pe_acc_enable))
                $fatal(1, "pe_array_datapath membrane fast enable mismatch");
            if (owner_membrane
                && (membrane_direct_value_fast != mem_pe_direct_value))
                $fatal(1, "pe_array_datapath membrane fast DIRECT mismatch");
            if (mem_post_out_valid && !mem_post_out_ready)
                $fatal(1, "pe_array_datapath membrane post sink was not ready");
            if (owner_membrane && mem_post_cmd_valid_q
                && !phy_post_in_ready)
                $fatal(1, "pe_array_datapath membrane post command stage stalled");
            if (owner_gate && phy_post_out_valid && !phy_post_gate_out
                && !sig_in_ready)
                $fatal(1, "pe_array_datapath Sigmoid sink was not ready");
            if (owner_gate && phy_rq_out_valid && !phy_post_in_ready)
                $fatal(1, "pe_array_datapath Gate Postprocess capacity invariant failed");
            if (overflow_any)
                $fatal(1, "pe_array_datapath Hybrid accumulator overflow");
            if (spike_event_valid
                && !(spike_event_spike || spike_event_last))
                $fatal(1, "pe_array_datapath invalid spike event");
            if (shared_out_valid && shared_op_kind_out == OP_LINEAR
                && qbn_input_fire)
                $fatal(1, "pe_array_datapath Linear entered QBN fork");
            if (membrane_serializer_reserved_q && linear_tile_ready)
                $fatal(1, "pe_array_datapath dual serializer producer grant");
        end
    end
`endif

endmodule
