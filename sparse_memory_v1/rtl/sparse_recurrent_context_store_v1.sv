`timescale 1ns/1ps

// Sparse-v1 adapter around the isolated Sequential-v4-derived context-store
// core.  It preserves the dense state/list ABI and adds explicit logical-list
// presence to descriptor responses.  The original source remains byte-for-
// byte immutable under imports/; timing changes live only in the renamed core.
module sparse_recurrent_context_store_v1 (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear_state,

    input  wire                         producer_open_valid,
    output wire                         producer_open_ready,
    input  wire [4:0]                   producer_open_logical_id,
    input  wire [5:0]                   producer_open_row_tiles,

    input  wire                         list_desc_req_valid,
    output wire                         list_desc_req_ready,
    input  wire [4:0]                   list_desc_req_logical_id,
    input  wire [7:0]                   list_desc_req_tag,
    output wire                         list_desc_rsp_valid,
    input  wire                         list_desc_rsp_ready,
    output wire                         list_desc_rsp_present,
    output wire [8:0]                   list_desc_rsp_count,
    output wire [7:0]                   list_desc_rsp_tag,
    output wire                         list_desc_rsp_error,

    input  wire                         list_read_req_valid,
    output wire                         list_read_req_ready,
    input  wire [4:0]                   list_read_req_logical_id,
    input  wire [8:0]                   list_read_req_ordinal,
    input  wire [7:0]                   list_read_req_tag,
    output wire                         list_read_rsp_valid,
    input  wire                         list_read_rsp_ready,
    output wire [8:0]                   list_read_rsp_index,
    output wire [7:0]                   list_read_rsp_tag,
    output wire                         list_read_rsp_error,

    input  wire                         state_read_req_valid,
    output wire                         state_read_req_ready,
    input  wire [4:0]                   state_read_req_logical_id,
    input  wire [4:0]                   state_read_req_row_tile,
    input  wire [7:0]                   state_read_req_tag,
    output wire                         state_read_rsp_valid,
    input  wire                         state_read_rsp_ready,
    output wire [127:0]                 state_read_rsp_data,
    output wire [7:0]                   state_read_rsp_tag,
    output wire                         state_read_rsp_error,

    input  wire                         state_write_valid,
    output wire                         state_write_ready,
    input  wire signed [7:0]            state_write_value,
    input  wire [8:0]                   state_write_index,
    input  wire [15:0]                  state_write_tag,
    input  wire                         state_write_last,

    input  wire                         active_cmd_valid,
    output wire                         active_cmd_ready,
    input  wire                         active_cmd_write,
    input  wire [8:0]                   active_cmd_index,
    input  wire [15:0]                  active_cmd_tag,
    input  wire                         active_cmd_finalize,

    input  wire                         commit_valid,
    output wire                         commit_ready,
    input  wire [4:0]                   commit_logical_id,
    input  wire                         pe_barrier_idle,
    output wire                         commit_done,

    output wire                         producer_busy,
    output wire [4:0]                   producer_logical_id,
    output wire [5:0]                   producer_row_tiles,
    output wire [8:0]                   producer_list_count,
    output wire                         error_valid,
    output wire [7:0]                   error_code,
    output wire [31:0]                  error_detail,
    output wire                         reset_required
);
    reg [19:0] logical_list_present_q;
    reg descriptor_present_q;
    reg [4:0] accepted_commit_id_q;
    wire inner_commit_done;

    wire descriptor_request_fire = list_desc_req_valid &&
                                   list_desc_req_ready;
    wire commit_request_fire = commit_valid && commit_ready;

    assign list_desc_rsp_present = descriptor_present_q &&
                                   !list_desc_rsp_error;
    assign commit_done = inner_commit_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            logical_list_present_q <= 20'd0;
            descriptor_present_q <= 1'b0;
            accepted_commit_id_q <= 5'd0;
        end else begin
            if (descriptor_request_fire) begin
                if (list_desc_req_logical_id < 20)
                    // The imported store publishes the new slot in the same
                    // cycle that commit_done rises.  Include that pulse so a
                    // descriptor accepted in the immediately following
                    // cycle observes the atomic commit, rather than a
                    // one-cycle-old presence bit.
                    descriptor_present_q <= !clear_state &&
                        (logical_list_present_q[
                            list_desc_req_logical_id] ||
                         (inner_commit_done &&
                          (accepted_commit_id_q ==
                           list_desc_req_logical_id)));
                else
                    descriptor_present_q <= 1'b0;
            end

            if (commit_request_fire)
                accepted_commit_id_q <= commit_logical_id;

            if (clear_state) begin
                logical_list_present_q <= 20'd0;
            end else if (inner_commit_done &&
                         (accepted_commit_id_q < 20)) begin
                logical_list_present_q[accepted_commit_id_q] <= 1'b1;
            end
        end
    end

    sparse_recurrent_context_store_core_v1 u_sparse_context_store_core (
        .clk(clk),
        .rst_n(rst_n),
        .clear_state(clear_state),
        .producer_open_valid(producer_open_valid),
        .producer_open_ready(producer_open_ready),
        .producer_open_logical_id(producer_open_logical_id),
        .producer_open_row_tiles(producer_open_row_tiles),
        .list_desc_req_valid(list_desc_req_valid),
        .list_desc_req_ready(list_desc_req_ready),
        .list_desc_req_logical_id(list_desc_req_logical_id),
        .list_desc_req_tag(list_desc_req_tag),
        .list_desc_rsp_valid(list_desc_rsp_valid),
        .list_desc_rsp_ready(list_desc_rsp_ready),
        .list_desc_rsp_count(list_desc_rsp_count),
        .list_desc_rsp_tag(list_desc_rsp_tag),
        .list_desc_rsp_error(list_desc_rsp_error),
        .list_read_req_valid(list_read_req_valid),
        .list_read_req_ready(list_read_req_ready),
        .list_read_req_logical_id(list_read_req_logical_id),
        .list_read_req_ordinal(list_read_req_ordinal),
        .list_read_req_tag(list_read_req_tag),
        .list_read_rsp_valid(list_read_rsp_valid),
        .list_read_rsp_ready(list_read_rsp_ready),
        .list_read_rsp_index(list_read_rsp_index),
        .list_read_rsp_tag(list_read_rsp_tag),
        .list_read_rsp_error(list_read_rsp_error),
        .state_read_req_valid(state_read_req_valid),
        .state_read_req_ready(state_read_req_ready),
        .state_read_req_logical_id(state_read_req_logical_id),
        .state_read_req_row_tile(state_read_req_row_tile),
        .state_read_req_tag(state_read_req_tag),
        .state_read_rsp_valid(state_read_rsp_valid),
        .state_read_rsp_ready(state_read_rsp_ready),
        .state_read_rsp_data(state_read_rsp_data),
        .state_read_rsp_tag(state_read_rsp_tag),
        .state_read_rsp_error(state_read_rsp_error),
        .state_write_valid(state_write_valid),
        .state_write_ready(state_write_ready),
        .state_write_value(state_write_value),
        .state_write_index(state_write_index),
        .state_write_tag(state_write_tag),
        .state_write_last(state_write_last),
        .active_cmd_valid(active_cmd_valid),
        .active_cmd_ready(active_cmd_ready),
        .active_cmd_write(active_cmd_write),
        .active_cmd_index(active_cmd_index),
        .active_cmd_tag(active_cmd_tag),
        .active_cmd_finalize(active_cmd_finalize),
        .commit_valid(commit_valid),
        .commit_ready(commit_ready),
        .commit_logical_id(commit_logical_id),
        .pe_barrier_idle(pe_barrier_idle),
        .commit_done(inner_commit_done),
        .producer_busy(producer_busy),
        .producer_logical_id(producer_logical_id),
        .producer_row_tiles(producer_row_tiles),
        .producer_list_count(producer_list_count),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_detail(error_detail),
        .reset_required(reset_required)
    );
endmodule
