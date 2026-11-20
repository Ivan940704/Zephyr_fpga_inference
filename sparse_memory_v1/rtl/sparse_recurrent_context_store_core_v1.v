`timescale 1ns/1ps

// Sequential-v4 recurrent state and active-index store, isolated sparse v1.
//
// Twenty logical contexts retain dense state and one persistent active list.
// A twenty-first list slot is the only producer.  Commit swaps one logical
// mapping with the producer slot; no payload copy, scrub, token, generation,
// reference count, or local recovery is required by this baseline.
module sparse_recurrent_context_store_core_v1 (
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
    output reg                          commit_done,

    output wire                         producer_busy,
    output wire [4:0]                   producer_logical_id,
    output wire [5:0]                   producer_row_tiles,
    output wire [8:0]                   producer_list_count,
    output reg                          error_valid,
    output reg  [7:0]                   error_code,
    output reg  [31:0]                  error_detail,
    output wire                         reset_required
);
    localparam [7:0] ERR_NONE        = 8'h00;
    localparam [7:0] ERR_OPEN        = 8'h01;
    localparam [7:0] ERR_LIST_DESC   = 8'h02;
    localparam [7:0] ERR_LIST_READ   = 8'h03;
    localparam [7:0] ERR_STATE_READ  = 8'h04;
    localparam [7:0] ERR_STATE_WRITE = 8'h05;
    localparam [7:0] ERR_ACTIVE_CMD  = 8'h06;
    localparam [7:0] ERR_COMMIT      = 8'h07;
    localparam [7:0] ERR_CLEAR       = 8'h08;

    // 21 * 320 = 6,720 entries.  Splitting the 13-bit linear address at 4096
    // gives two uniform 4096 x 9 memories and exactly two RAMB36E1.
    (* ram_style = "block" *) reg [8:0] active_mem0 [0:4095];
    (* ram_style = "block" *) reg [8:0] active_mem1 [0:4095];

    // 20 * 20 = 400 dense 128-bit tiles.  The two 512 x 64 planes support one
    // synchronous tile read and one independent byte write.
    (* ram_style = "block" *) reg [63:0] state_lo_mem [0:511];
    (* ram_style = "block" *) reg [63:0] state_hi_mem [0:511];

    reg [4:0] logical_to_slot_q [0:19];
    reg [8:0] active_count_q [0:20];
    reg [20:0] active_slot_valid_q;
    reg [19:0] state_valid_q;
    reg [4:0] producer_slot_q;

    reg producer_open_q;
    reg [4:0] producer_logical_id_q;
    reg [5:0] producer_row_tiles_q;
    reg [8:0] producer_neurons_q;
    reg [8:0] state_next_index_q;
    reg state_complete_q;
    reg [19:0] old_tile_read_q;
    reg [8:0] active_write_count_q;
    reg active_has_previous_q;
    reg [8:0] active_previous_index_q;
    reg active_finalized_q;

    reg list_desc_rsp_valid_q;
    reg [8:0] list_desc_rsp_count_q;
    reg [7:0] list_desc_rsp_tag_q;
    reg list_desc_rsp_error_q;

    reg list_read_pending_q;
    reg list_read_pending_bank_q;
    reg [7:0] list_read_pending_tag_q;
    // Request-edge decode/legality snapshot.  This pipeline cuts the mutable
    // logical-to-physical map and count lookup away from the sticky error and
    // BRAM-response control cone while preserving the exact request-edge view.
    reg list_read_issue_q;
    reg list_read_issue_legal_q;
    reg list_read_issue_bank_q;
    reg [11:0] list_read_issue_address_q;
    reg [4:0] list_read_issue_logical_id_q;
    reg [8:0] list_read_issue_ordinal_q;
    reg [7:0] list_read_issue_tag_q;
    reg [8:0] active_mem0_rdata_q;
    reg [8:0] active_mem1_rdata_q;
    reg list_read_rsp_valid_q;
    reg [8:0] list_read_rsp_index_q;
    reg [7:0] list_read_rsp_tag_q;
    reg list_read_rsp_error_q;

    reg state_read_pending_q;
    reg [4:0] state_read_pending_logical_id_q;
    reg [4:0] state_read_pending_row_tile_q;
    reg [7:0] state_read_pending_tag_q;
    reg [63:0] state_lo_rdata_q;
    reg [63:0] state_hi_rdata_q;
    reg state_read_rsp_valid_q;
    reg [127:0] state_read_rsp_data_q;
    reg [4:0] state_read_rsp_logical_id_q;
    reg [4:0] state_read_rsp_row_tile_q;
    reg [7:0] state_read_rsp_tag_q;
    reg state_read_rsp_error_q;

    function [8:0] state_address;
        input [4:0] logical_id;
        input [4:0] row_tile;
        reg [8:0] expanded_id;
        begin
            expanded_id = {4'd0, logical_id};
            state_address = (expanded_id << 4) + (expanded_id << 2) +
                            {4'd0, row_tile};
        end
    endfunction

    function [12:0] active_address;
        input [4:0] slot;
        input [8:0] ordinal;
        reg [12:0] expanded_slot;
        begin
            expanded_slot = {8'd0, slot};
            active_address = (expanded_slot << 8) +
                             (expanded_slot << 6) +
                             {4'd0, ordinal};
        end
    endfunction

    function [19:0] required_tile_mask;
        input [5:0] row_tiles;
        begin
            if (row_tiles == 0)
                required_tile_mask = 20'd0;
            else if (row_tiles >= 20)
                required_tile_mask = 20'hfffff;
            else
                required_tile_mask = 20'hfffff >> (20 - row_tiles);
        end
    endfunction

    wire producer_open_fire = producer_open_valid && producer_open_ready;
    wire list_desc_req_fire = list_desc_req_valid && list_desc_req_ready;
    wire list_read_req_fire = list_read_req_valid && list_read_req_ready;
    wire state_read_req_fire = state_read_req_valid && state_read_req_ready;
    wire state_write_fire = state_write_valid && state_write_ready;
    wire active_cmd_fire = active_cmd_valid && active_cmd_ready;
    wire commit_fire = commit_valid && commit_ready;

    wire [4:0] list_desc_slot =
        (list_desc_req_logical_id < 20)
        ? logical_to_slot_q[list_desc_req_logical_id] : 5'd0;
    wire [4:0] list_read_slot =
        (list_read_req_logical_id < 20)
        ? logical_to_slot_q[list_read_req_logical_id] : 5'd0;
    wire [12:0] list_read_linear_address =
        active_address(list_read_slot, list_read_req_ordinal);
    wire [8:0] state_read_linear_address =
        state_address(state_read_req_logical_id,
                      state_read_req_row_tile);
    wire [8:0] state_write_linear_address =
        state_address(producer_logical_id_q,
                      state_write_index[8:4]);
    wire [12:0] active_write_linear_address =
        active_address(producer_slot_q, active_write_count_q);

    wire state_tag_matches =
        (state_write_tag[15:14] == 2'b00) &&
        (state_write_tag[13:9] == producer_logical_id_q) &&
        (state_write_tag[8:0] == state_write_index);
    wire state_index_matches =
        (state_write_index == state_next_index_q) &&
        (state_write_index < producer_neurons_q);
    wire state_old_read_complete =
        old_tile_read_q[state_write_index[8:4]];
    wire state_last_matches =
        state_write_last ==
        (state_write_index == (producer_neurons_q - 1'b1));
    wire state_write_legal = producer_open_q && !state_complete_q &&
                             state_tag_matches && state_index_matches &&
                             state_old_read_complete && state_last_matches;

    wire active_tag_matches =
        (active_cmd_tag[15:14] == 2'b00) &&
        (active_cmd_tag[13:9] == producer_logical_id_q) &&
        (active_cmd_tag[8:0] == active_cmd_index);
    wire active_index_in_range = active_cmd_index < producer_neurons_q;
    wire active_write_ordered = !active_cmd_write ||
        ((!active_has_previous_q ||
          (active_cmd_index > active_previous_index_q)) &&
         (active_write_count_q < 9'd320));
    wire active_finalize_matches = !active_cmd_finalize ||
        (active_cmd_index == (producer_neurons_q - 1'b1));
    wire active_cmd_legal = producer_open_q && !active_finalized_q &&
                            (active_cmd_write || active_cmd_finalize) &&
                            active_tag_matches && active_index_in_range &&
                            active_write_ordered && active_finalize_matches;

    wire no_context_reads = !list_desc_rsp_valid_q &&
                            !list_read_issue_q &&
                            !list_read_pending_q &&
                            !list_read_rsp_valid_q &&
                            !state_read_pending_q &&
                            !state_read_rsp_valid_q;
    wire all_old_tiles_read =
        (old_tile_read_q & required_tile_mask(producer_row_tiles_q)) ==
        required_tile_mask(producer_row_tiles_q);
    wire commit_legal = producer_open_q &&
                        (commit_logical_id == producer_logical_id_q) &&
                        state_complete_q && active_finalized_q &&
                        all_old_tiles_read && no_context_reads &&
                        pe_barrier_idle;

    assign producer_open_ready = !error_valid && !producer_open_q &&
                                 no_context_reads;
    assign list_desc_req_ready = !error_valid &&
                                 !list_desc_rsp_valid_q;
    assign list_read_req_ready = !error_valid &&
                                 !list_read_issue_q &&
                                 !list_read_pending_q &&
                                 !list_read_rsp_valid_q;
    assign state_read_req_ready = !error_valid &&
                                  !state_read_pending_q &&
                                  !state_read_rsp_valid_q;
    assign state_write_ready = !error_valid && producer_open_q &&
                               !state_complete_q;
    assign active_cmd_ready = !error_valid && producer_open_q &&
                              !active_finalized_q;
    assign commit_ready = !error_valid && producer_open_q;

    assign list_desc_rsp_valid = list_desc_rsp_valid_q;
    assign list_desc_rsp_count = list_desc_rsp_count_q;
    assign list_desc_rsp_tag = list_desc_rsp_tag_q;
    assign list_desc_rsp_error = list_desc_rsp_error_q;
    assign list_read_rsp_valid = list_read_rsp_valid_q;
    assign list_read_rsp_index = list_read_rsp_index_q;
    assign list_read_rsp_tag = list_read_rsp_tag_q;
    assign list_read_rsp_error = list_read_rsp_error_q;
    assign state_read_rsp_valid = state_read_rsp_valid_q;
    assign state_read_rsp_data = state_read_rsp_data_q;
    assign state_read_rsp_tag = state_read_rsp_tag_q;
    assign state_read_rsp_error = state_read_rsp_error_q;

    assign producer_busy = producer_open_q;
    assign producer_logical_id = producer_logical_id_q;
    assign producer_row_tiles = producer_row_tiles_q;
    assign producer_list_count = active_write_count_q;
    assign reset_required = error_valid;

    task latch_fault;
        input [7:0] code;
        input [31:0] detail;
        begin
            if (!error_valid) begin
                error_valid <= 1'b1;
                error_code <= code;
                error_detail <= detail;
            end
        end
    endtask

    // Active list payload: one producer write and one independent consumer
    // read.  Producer and persistent slots are always distinct.
    always @(posedge clk) begin
        if (active_cmd_fire && active_cmd_legal && active_cmd_write) begin
            if (!active_write_linear_address[12])
                active_mem0[active_write_linear_address[11:0]] <=
                    active_cmd_index;
            else
                active_mem1[active_write_linear_address[11:0]] <=
                    active_cmd_index;
        end
        if (list_read_issue_q && list_read_issue_legal_q) begin
            if (!list_read_issue_bank_q)
                active_mem0_rdata_q <=
                    active_mem0[list_read_issue_address_q];
            else
                active_mem1_rdata_q <=
                    active_mem1[list_read_issue_address_q];
        end
    end

    // Dense state payload.  Fixed lane cases preserve byte-write-enable BRAM
    // inference in Vivado 2018.3.
    always @(posedge clk) begin
        if (state_write_fire && state_write_legal) begin
            if (!state_write_index[3]) begin
                case (state_write_index[2:0])
                    3'd0: state_lo_mem[state_write_linear_address][7:0]
                        <= state_write_value;
                    3'd1: state_lo_mem[state_write_linear_address][15:8]
                        <= state_write_value;
                    3'd2: state_lo_mem[state_write_linear_address][23:16]
                        <= state_write_value;
                    3'd3: state_lo_mem[state_write_linear_address][31:24]
                        <= state_write_value;
                    3'd4: state_lo_mem[state_write_linear_address][39:32]
                        <= state_write_value;
                    3'd5: state_lo_mem[state_write_linear_address][47:40]
                        <= state_write_value;
                    3'd6: state_lo_mem[state_write_linear_address][55:48]
                        <= state_write_value;
                    3'd7: state_lo_mem[state_write_linear_address][63:56]
                        <= state_write_value;
                endcase
            end else begin
                case (state_write_index[2:0])
                    3'd0: state_hi_mem[state_write_linear_address][7:0]
                        <= state_write_value;
                    3'd1: state_hi_mem[state_write_linear_address][15:8]
                        <= state_write_value;
                    3'd2: state_hi_mem[state_write_linear_address][23:16]
                        <= state_write_value;
                    3'd3: state_hi_mem[state_write_linear_address][31:24]
                        <= state_write_value;
                    3'd4: state_hi_mem[state_write_linear_address][39:32]
                        <= state_write_value;
                    3'd5: state_hi_mem[state_write_linear_address][47:40]
                        <= state_write_value;
                    3'd6: state_hi_mem[state_write_linear_address][55:48]
                        <= state_write_value;
                    3'd7: state_hi_mem[state_write_linear_address][63:56]
                        <= state_write_value;
                endcase
            end
        end
        if (state_read_req_fire &&
            (state_read_req_logical_id < 20) &&
            (state_read_req_row_tile < 20) &&
            state_valid_q[state_read_req_logical_id]) begin
            state_lo_rdata_q <= state_lo_mem[state_read_linear_address];
            state_hi_rdata_q <= state_hi_mem[state_read_linear_address];
        end
    end

    integer reset_index;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (reset_index = 0; reset_index < 20;
                 reset_index = reset_index + 1)
                logical_to_slot_q[reset_index] <= reset_index[4:0];
            for (reset_index = 0; reset_index < 21;
                 reset_index = reset_index + 1)
                active_count_q[reset_index] <= 9'd0;
            active_slot_valid_q <= 21'd0;
            state_valid_q <= 20'd0;
            producer_slot_q <= 5'd20;
            producer_open_q <= 1'b0;
            producer_logical_id_q <= 5'd0;
            producer_row_tiles_q <= 6'd0;
            producer_neurons_q <= 9'd0;
            state_next_index_q <= 9'd0;
            state_complete_q <= 1'b0;
            old_tile_read_q <= 20'd0;
            active_write_count_q <= 9'd0;
            active_has_previous_q <= 1'b0;
            active_previous_index_q <= 9'd0;
            active_finalized_q <= 1'b0;
            list_desc_rsp_valid_q <= 1'b0;
            list_desc_rsp_count_q <= 9'd0;
            list_desc_rsp_tag_q <= 8'd0;
            list_desc_rsp_error_q <= 1'b0;
            list_read_pending_q <= 1'b0;
            list_read_pending_bank_q <= 1'b0;
            list_read_pending_tag_q <= 8'd0;
            list_read_issue_q <= 1'b0;
            list_read_issue_legal_q <= 1'b0;
            list_read_issue_bank_q <= 1'b0;
            list_read_issue_address_q <= 12'd0;
            list_read_issue_logical_id_q <= 5'd0;
            list_read_issue_ordinal_q <= 9'd0;
            list_read_issue_tag_q <= 8'd0;
            list_read_rsp_valid_q <= 1'b0;
            list_read_rsp_index_q <= 9'd0;
            list_read_rsp_tag_q <= 8'd0;
            list_read_rsp_error_q <= 1'b0;
            state_read_pending_q <= 1'b0;
            state_read_pending_logical_id_q <= 5'd0;
            state_read_pending_row_tile_q <= 5'd0;
            state_read_pending_tag_q <= 8'd0;
            state_read_rsp_valid_q <= 1'b0;
            state_read_rsp_data_q <= 128'd0;
            state_read_rsp_logical_id_q <= 5'd0;
            state_read_rsp_row_tile_q <= 5'd0;
            state_read_rsp_tag_q <= 8'd0;
            state_read_rsp_error_q <= 1'b0;
            commit_done <= 1'b0;
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_detail <= 32'd0;
        end else begin
            commit_done <= 1'b0;
            if (list_read_issue_q)
                list_read_issue_q <= 1'b0;

            if (list_desc_rsp_valid_q && list_desc_rsp_ready)
                list_desc_rsp_valid_q <= 1'b0;
            if (list_read_rsp_valid_q && list_read_rsp_ready)
                list_read_rsp_valid_q <= 1'b0;
            if (state_read_rsp_valid_q && state_read_rsp_ready) begin
                state_read_rsp_valid_q <= 1'b0;
                if (producer_open_q && !state_read_rsp_error_q &&
                    (state_read_rsp_logical_id_q ==
                     producer_logical_id_q) &&
                    (state_read_rsp_row_tile_q <
                     producer_row_tiles_q)) begin
                    old_tile_read_q[state_read_rsp_row_tile_q] <= 1'b1;
                end
            end

            if (clear_state) begin
                if (producer_open_q || !no_context_reads) begin
                    latch_fault(ERR_CLEAR, 32'd1);
                end else begin
                    for (reset_index = 0; reset_index < 20;
                         reset_index = reset_index + 1)
                        logical_to_slot_q[reset_index] <= reset_index[4:0];
                    for (reset_index = 0; reset_index < 21;
                         reset_index = reset_index + 1)
                        active_count_q[reset_index] <= 9'd0;
                    active_slot_valid_q <= 21'd0;
                    state_valid_q <= 20'd0;
                    producer_slot_q <= 5'd20;
                end
            end

            if (producer_open_valid && producer_open_q)
                latch_fault(ERR_OPEN,
                            {21'd0, producer_open_logical_id,
                             producer_open_row_tiles});

            if (producer_open_fire) begin
                if ((producer_open_logical_id >= 20) ||
                    (producer_open_row_tiles == 0) ||
                    (producer_open_row_tiles > 20)) begin
                    latch_fault(ERR_OPEN,
                                {21'd0, producer_open_logical_id,
                                 producer_open_row_tiles});
                end else begin
                    producer_open_q <= 1'b1;
                    producer_logical_id_q <= producer_open_logical_id;
                    producer_row_tiles_q <= producer_open_row_tiles;
                    producer_neurons_q <=
                        {producer_open_row_tiles[4:0], 4'b0000};
                    state_next_index_q <= 9'd0;
                    state_complete_q <= 1'b0;
                    old_tile_read_q <= 20'd0;
                    active_write_count_q <= 9'd0;
                    active_has_previous_q <= 1'b0;
                    active_previous_index_q <= 9'd0;
                    active_finalized_q <= 1'b0;
                    active_count_q[producer_slot_q] <= 9'd0;
                    active_slot_valid_q[producer_slot_q] <= 1'b0;
                end
            end

            if (list_desc_req_fire) begin
                list_desc_rsp_valid_q <= 1'b1;
                list_desc_rsp_tag_q <= list_desc_req_tag;
                if (list_desc_req_logical_id >= 20) begin
                    list_desc_rsp_count_q <= 9'd0;
                    list_desc_rsp_error_q <= 1'b1;
                    latch_fault(ERR_LIST_DESC,
                                {19'd0, list_desc_req_logical_id,
                                 list_desc_req_tag});
                end else begin
                    list_desc_rsp_error_q <= 1'b0;
                    if (active_slot_valid_q[list_desc_slot])
                        list_desc_rsp_count_q <=
                            active_count_q[list_desc_slot];
                    else
                        list_desc_rsp_count_q <= 9'd0;
                end
            end

            if (list_read_req_fire) begin
                list_read_issue_q <= 1'b1;
                list_read_issue_legal_q <=
                    (list_read_req_logical_id < 20) &&
                    active_slot_valid_q[list_read_slot] &&
                    (list_read_req_ordinal <
                     active_count_q[list_read_slot]);
                list_read_issue_bank_q <= list_read_linear_address[12];
                list_read_issue_address_q <=
                    list_read_linear_address[11:0];
                list_read_issue_logical_id_q <=
                    list_read_req_logical_id;
                list_read_issue_ordinal_q <= list_read_req_ordinal;
                list_read_issue_tag_q <= list_read_req_tag;
            end

            if (list_read_issue_q) begin
                if (!list_read_issue_legal_q) begin
                    list_read_rsp_valid_q <= 1'b1;
                    list_read_rsp_index_q <= 9'd0;
                    list_read_rsp_tag_q <= list_read_issue_tag_q;
                    list_read_rsp_error_q <= 1'b1;
                    latch_fault(ERR_LIST_READ,
                                {10'd0, list_read_issue_logical_id_q,
                                 list_read_issue_ordinal_q,
                                 list_read_issue_tag_q});
                end else begin
                    list_read_pending_q <= 1'b1;
                    list_read_pending_bank_q <=
                        list_read_issue_bank_q;
                    list_read_pending_tag_q <= list_read_issue_tag_q;
                end
            end

            if (list_read_pending_q && !list_read_rsp_valid_q) begin
                list_read_pending_q <= 1'b0;
                list_read_rsp_valid_q <= 1'b1;
                list_read_rsp_index_q <= list_read_pending_bank_q
                    ? active_mem1_rdata_q : active_mem0_rdata_q;
                list_read_rsp_tag_q <= list_read_pending_tag_q;
                list_read_rsp_error_q <= 1'b0;
            end

            if (state_read_req_fire) begin
                state_read_rsp_logical_id_q <=
                    state_read_req_logical_id;
                state_read_rsp_row_tile_q <= state_read_req_row_tile;
                state_read_rsp_tag_q <= state_read_req_tag;
                if ((state_read_req_logical_id >= 20) ||
                    (state_read_req_row_tile >= 20)) begin
                    state_read_rsp_valid_q <= 1'b1;
                    state_read_rsp_data_q <= 128'd0;
                    state_read_rsp_error_q <= 1'b1;
                    latch_fault(ERR_STATE_READ,
                                {14'd0, state_read_req_logical_id,
                                 state_read_req_row_tile,
                                 state_read_req_tag});
                end else if (!state_valid_q[
                             state_read_req_logical_id]) begin
                    state_read_rsp_valid_q <= 1'b1;
                    state_read_rsp_data_q <= 128'd0;
                    state_read_rsp_error_q <= 1'b0;
                end else begin
                    state_read_pending_q <= 1'b1;
                    state_read_pending_logical_id_q <=
                        state_read_req_logical_id;
                    state_read_pending_row_tile_q <=
                        state_read_req_row_tile;
                    state_read_pending_tag_q <= state_read_req_tag;
                end
            end

            if (state_read_pending_q && !state_read_rsp_valid_q) begin
                state_read_pending_q <= 1'b0;
                state_read_rsp_valid_q <= 1'b1;
                state_read_rsp_data_q <=
                    {state_hi_rdata_q, state_lo_rdata_q};
                state_read_rsp_logical_id_q <=
                    state_read_pending_logical_id_q;
                state_read_rsp_row_tile_q <=
                    state_read_pending_row_tile_q;
                state_read_rsp_tag_q <= state_read_pending_tag_q;
                state_read_rsp_error_q <= 1'b0;
            end

            if (state_write_fire) begin
                if (!state_write_legal) begin
                    latch_fault(ERR_STATE_WRITE,
                                {6'd0, state_write_last,
                                 state_write_tag, state_write_index});
                end else begin
                    state_next_index_q <= state_next_index_q + 1'b1;
                    if (state_write_last)
                        state_complete_q <= 1'b1;
                end
            end

            if (active_cmd_fire) begin
                if (!active_cmd_legal) begin
                    latch_fault(ERR_ACTIVE_CMD,
                                {5'd0, active_cmd_write,
                                 active_cmd_finalize,
                                 active_cmd_tag, active_cmd_index});
                end else begin
                    if (active_cmd_write) begin
                        active_write_count_q <=
                            active_write_count_q + 1'b1;
                        active_has_previous_q <= 1'b1;
                        active_previous_index_q <= active_cmd_index;
                    end
                    if (active_cmd_finalize)
                        active_finalized_q <= 1'b1;
                end
            end

            if (commit_fire) begin
                if (!commit_legal) begin
                    latch_fault(ERR_COMMIT,
                                {6'd0, pe_barrier_idle,
                                 active_finalized_q, state_complete_q,
                                 commit_logical_id,
                                 producer_logical_id_q,
                                 active_write_count_q, 4'd0});
                end else begin
                    active_count_q[producer_slot_q] <=
                        active_write_count_q;
                    active_slot_valid_q[producer_slot_q] <= 1'b1;
                    producer_slot_q <=
                        logical_to_slot_q[producer_logical_id_q];
                    logical_to_slot_q[producer_logical_id_q] <=
                        producer_slot_q;
                    state_valid_q[producer_logical_id_q] <= 1'b1;
                    producer_open_q <= 1'b0;
                    commit_done <= 1'b1;
                end
            end
        end
    end
endmodule
