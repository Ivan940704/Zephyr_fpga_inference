`timescale 1ns/1ps

// Frame-owned store for the three subband projection streams.
//
// Projection bytes retain the model's flattened order
//   {component, local_bin, tap}
// inside each subband context.  The nine context packets are packed into one
// 1,152-byte address space:
//   stage 5  / order 5 / four contexts: bytes   0..319
//   stage 8  / order 3 / three contexts: bytes 320..895
//   stage 11 / order 1 / two contexts: bytes 896..1151
//
// The input tag is {kind[1:0], logical_context_id[4:0], index[8:0]}.
// Logical branch zero is fullband; the subband projection IDs are therefore
// 3/5/7/9, 11/13/15, and 17/19.  Every malformed identity, ordering, lifetime,
// or read is a sticky reset-required fault.
module sequential_df_coefficient_store #(
    parameter integer FRAME_ID_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         abort,
    input  wire [FRAME_ID_WIDTH-1:0]    current_frame_id,
    input  wire                         frame_start,
    input  wire                         frame_done,
    input  wire                         consume_start,

    input  wire                         coefficient_valid,
    output wire                         coefficient_ready,
    input  wire signed [7:0]            coefficient_value,
    input  wire [8:0]                   coefficient_index,
    input  wire [15:0]                  coefficient_tag,
    input  wire                         coefficient_last,
    input  wire [3:0]                   coefficient_stage_id,

    input  wire                         read_req_valid,
    output wire                         read_req_ready,
    input  wire [10:0]                  read_req_address,
    output wire                         read_rsp_valid,
    input  wire                         read_rsp_ready,
    output wire signed [7:0]            read_rsp_value,
    output wire                         read_rsp_error,

    output wire [8:0]                   context_valid,
    output wire                         all_coefficients_valid,
    output wire                         frame_active,
    output wire [FRAME_ID_WIDTH-1:0]    stored_frame_id,
    output wire                         stream_active,
    output reg                          error_valid,
    output reg  [7:0]                   error_code,
    output reg  [31:0]                  error_detail
);
    localparam integer STORE_BYTES = 1152;

    localparam [7:0] ERR_NONE        = 8'h00;
    localparam [7:0] ERR_FRAME_START = 8'h60;
    localparam [7:0] ERR_FRAME_DONE  = 8'h61;
    localparam [7:0] ERR_FRAME_ID    = 8'h62;
    localparam [7:0] ERR_IDENTITY    = 8'h63;
    localparam [7:0] ERR_ORDER       = 8'h64;
    localparam [7:0] ERR_LAST        = 8'h65;
    localparam [7:0] ERR_READ        = 8'h66;
    localparam [7:0] ERR_CONSUME     = 8'h67;

    (* ram_style = "block" *) reg [7:0] coefficient_mem [0:STORE_BYTES-1];

    reg frame_active_q;
    reg [FRAME_ID_WIDTH-1:0] stored_frame_q;
    reg [8:0] context_valid_q;
    reg stream_active_q;
    reg [3:0] stream_stage_q;
    reg [4:0] stream_logical_id_q;
    reg [8:0] expected_index_q;

    reg read_rsp_valid_q;
    reg signed [7:0] read_rsp_value_q;
    reg read_rsp_error_q;

    wire [4:0] coefficient_logical_id = coefficient_tag[13:9];
    wire coefficient_fire = coefficient_valid && coefficient_ready;
    wire read_req_fire = read_req_valid && read_req_ready;
    wire read_rsp_fire = read_rsp_valid && read_rsp_ready;

    reg identity_valid;
    reg [1:0] decoded_context;
    reg [3:0] decoded_context_bit;
    reg [8:0] decoded_last_index;
    reg [10:0] decoded_write_address;
    reg decoded_context_complete;

    task latch_error;
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

    always @* begin
        identity_valid = 1'b0;
        decoded_context = 2'd0;
        decoded_context_bit = 4'd0;
        decoded_last_index = 9'd0;
        decoded_write_address = 11'd0;

        case (coefficient_stage_id)
            4'd5: begin
                if ((coefficient_logical_id >= 5'd3) &&
                    (coefficient_logical_id <= 5'd9) &&
                    coefficient_logical_id[0]) begin
                    decoded_context =
                        (coefficient_logical_id - 5'd3) >> 1;
                    decoded_context_bit = {2'd0, decoded_context};
                    decoded_last_index = 9'd79;
                    decoded_write_address =
                        decoded_context * 11'd80 + coefficient_index;
                    identity_valid = coefficient_index < 9'd80;
                end
            end
            4'd8: begin
                if ((coefficient_logical_id >= 5'd11) &&
                    (coefficient_logical_id <= 5'd15) &&
                    coefficient_logical_id[0]) begin
                    decoded_context =
                        (coefficient_logical_id - 5'd11) >> 1;
                    decoded_context_bit = 4'd4 +
                        {2'd0, decoded_context};
                    decoded_last_index = 9'd191;
                    decoded_write_address = 11'd320 +
                        decoded_context * 11'd192 + coefficient_index;
                    identity_valid = coefficient_index < 9'd192;
                end
            end
            4'd11: begin
                if ((coefficient_logical_id >= 5'd17) &&
                    (coefficient_logical_id <= 5'd19) &&
                    coefficient_logical_id[0]) begin
                    decoded_context =
                        (coefficient_logical_id - 5'd17) >> 1;
                    decoded_context_bit = 4'd7 +
                        {2'd0, decoded_context};
                    decoded_last_index = 9'd127;
                    decoded_write_address = 11'd896 +
                        decoded_context * 11'd128 + coefficient_index;
                    identity_valid = coefficient_index < 9'd128;
                end
            end
            default: begin
                identity_valid = 1'b0;
            end
        endcase

        decoded_context_complete =
            context_valid_q[decoded_context_bit];
    end

    assign coefficient_ready = rst_n && frame_active_q && !abort &&
                               !error_valid;

    // A read request may replace a response in the same cycle that the old
    // response is consumed.  Invalid requests are accepted and faulted so an
    // internal scheduler cannot deadlock on its own bad address/lifetime.
    assign read_req_ready = rst_n && !abort && !error_valid &&
                            (!read_rsp_valid_q || read_rsp_ready);
    assign read_rsp_valid = read_rsp_valid_q && !abort && !error_valid;
    assign read_rsp_value = read_rsp_value_q;
    assign read_rsp_error = read_rsp_error_q;

    assign context_valid = context_valid_q;
    assign all_coefficients_valid = &context_valid_q;
    assign frame_active = frame_active_q;
    assign stored_frame_id = stored_frame_q;
    assign stream_active = stream_active_q;

    initial begin
        if (FRAME_ID_WIDTH != 16) begin
            $display("Production coefficient store requires FRAME_ID_WIDTH=16");
            $finish;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            frame_active_q <= 1'b0;
            stored_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            context_valid_q <= 9'd0;
            stream_active_q <= 1'b0;
            stream_stage_q <= 4'd0;
            stream_logical_id_q <= 5'd0;
            expected_index_q <= 9'd0;
            read_rsp_valid_q <= 1'b0;
            read_rsp_value_q <= 8'sd0;
            read_rsp_error_q <= 1'b0;
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_detail <= 32'd0;
        end else if (abort) begin
            frame_active_q <= 1'b0;
            context_valid_q <= 9'd0;
            stream_active_q <= 1'b0;
            expected_index_q <= 9'd0;
            read_rsp_valid_q <= 1'b0;
            read_rsp_error_q <= 1'b0;
        end else begin
            if (frame_active_q &&
                (stored_frame_q != current_frame_id) && !frame_done) begin
                latch_error(ERR_FRAME_ID,
                    {stored_frame_q[15:0], current_frame_id[15:0]});
            end

            if (frame_start) begin
                if (frame_active_q || stream_active_q || read_rsp_valid_q) begin
                    latch_error(ERR_FRAME_START,
                        {15'd0, frame_active_q, stored_frame_q[15:0]});
                end else begin
                    frame_active_q <= 1'b1;
                    stored_frame_q <= current_frame_id;
                    context_valid_q <= 9'd0;
                end
            end

            if (coefficient_fire) begin
                if (!identity_valid ||
                    (coefficient_tag[15:14] != 2'b01) ||
                    (coefficient_tag[8:0] != coefficient_index) ||
                    decoded_context_complete) begin
                    latch_error(ERR_IDENTITY,
                        {coefficient_stage_id, coefficient_tag,
                         3'd0, coefficient_index});
                end else if ((!stream_active_q &&
                              (coefficient_index != 9'd0)) ||
                             (stream_active_q &&
                              ((coefficient_stage_id != stream_stage_q) ||
                               (coefficient_logical_id !=
                                stream_logical_id_q) ||
                               (coefficient_index != expected_index_q)))) begin
                    latch_error(ERR_ORDER,
                        {coefficient_stage_id, coefficient_logical_id,
                         expected_index_q, coefficient_index, 5'd0});
                end else if (coefficient_last !=
                             (coefficient_index == decoded_last_index)) begin
                    latch_error(ERR_LAST,
                        {coefficient_stage_id, coefficient_logical_id,
                         decoded_last_index, coefficient_index, 5'd0});
                end else begin
                    coefficient_mem[decoded_write_address] <=
                        coefficient_value;
                    if (!stream_active_q) begin
                        stream_stage_q <= coefficient_stage_id;
                        stream_logical_id_q <= coefficient_logical_id;
                    end
                    if (coefficient_last) begin
                        context_valid_q[decoded_context_bit] <= 1'b1;
                        stream_active_q <= 1'b0;
                        expected_index_q <= 9'd0;
                    end else begin
                        stream_active_q <= 1'b1;
                        expected_index_q <= coefficient_index + 1'b1;
                    end
                end
            end

            if (consume_start &&
                (!frame_active_q || stream_active_q ||
                 !(&context_valid_q))) begin
                latch_error(ERR_CONSUME,
                    {5'd0, context_valid_q, stream_active_q,
                     frame_active_q, stored_frame_q[15:0]});
            end

            if (read_req_fire) begin
                read_rsp_valid_q <= 1'b1;
                if (!frame_active_q || !(&context_valid_q) ||
                    (read_req_address >= STORE_BYTES)) begin
                    read_rsp_value_q <= 8'sd0;
                    read_rsp_error_q <= 1'b1;
                    latch_error(ERR_READ,
                        {4'd0, frame_active_q, context_valid_q,
                         read_req_address, 7'd0});
                end else begin
                    read_rsp_value_q <=
                        coefficient_mem[read_req_address];
                    read_rsp_error_q <= 1'b0;
                end
            end else if (read_rsp_fire) begin
                read_rsp_valid_q <= 1'b0;
                read_rsp_error_q <= 1'b0;
            end

            if (frame_done) begin
                if (!frame_active_q || stream_active_q ||
                    read_rsp_valid_q || !(&context_valid_q)) begin
                    latch_error(ERR_FRAME_DONE,
                        {5'd0, context_valid_q, stream_active_q,
                         read_rsp_valid_q, stored_frame_q[15:0]});
                end else begin
                    frame_active_q <= 1'b0;
                    context_valid_q <= 9'd0;
                end
            end
        end
    end
endmodule
