`timescale 1ns/1ps

// Model-specific coordinator that moves the complete pre-inference LayerNorm
// path into PL.  The host sends one 256-bin signed-Q12 magnitude packet.  A
// shared LayerNorm engine produces the normalized fullband packet, then uses
// the fullband projection to assemble and normalize all nine subband vectors.
module realtime_layernorm_coordinator #(
    parameter integer FRAME_ID_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         abort,
    input  wire [FRAME_ID_WIDTH-1:0]    current_frame_id,
    input  wire                         frame_done,

    // 256 signed-Q12 bins, four little-endian int16 lanes per 64-bit beat.
    input  wire                         s_axis_magnitude_tvalid,
    output wire                         s_axis_magnitude_tready,
    input  wire [63:0]                  s_axis_magnitude_tdata,
    input  wire [7:0]                   s_axis_magnitude_tkeep,
    input  wire                         s_axis_magnitude_tlast,

    // 64 normalized INT8 fullband values for sequential_feature_dispatcher.
    output wire                         m_axis_fullband_tvalid,
    input  wire                         m_axis_fullband_tready,
    output wire [63:0]                  m_axis_fullband_tdata,
    output wire [7:0]                   m_axis_fullband_tkeep,
    output wire                         m_axis_fullband_tlast,

    // Fullband projection stream from stage 2 of the PE subsystem.
    input  wire                         fb_projection_start,
    input  wire                         fb_coefficient_valid,
    output wire                         fb_coefficient_ready,
    input  wire signed [7:0]            fb_coefficient_value,
    input  wire [8:0]                   fb_coefficient_index,
    input  wire                         fb_coefficient_last,

    // Replacement for the old PS-subband-ready mailbox event.
    output wire                         subbands_valid,
    input  wire                         subbands_ready,

    // Frame-safe local 782-byte subband buffer read interface.
    output wire                         sb_buffer_valid,
    input  wire                         sb_read_valid,
    output wire                         sb_read_ready,
    input  wire [9:0]                   sb_read_index,
    input  wire [FRAME_ID_WIDTH-1:0]    sb_read_frame_id,
    output wire                         sb_read_rsp_valid,
    input  wire                         sb_read_rsp_ready,
    output wire signed [7:0]            sb_read_rsp_data,
    output wire                         sb_read_rsp_error,

    output wire                         magnitude_buffer_valid,
    output wire [FRAME_ID_WIDTH-1:0]    magnitude_buffer_frame_id,
    output wire                         busy,
    output wire                         quiescent,
    output wire [3:0]                   state_debug,
    output reg  [31:0]                  last_frame_cycle_count,
    output reg                          error_valid,
    output reg  [7:0]                   error_code,
    output reg  [31:0]                  error_detail
);
    localparam [3:0] ST_INGRESS            = 4'd0;
    localparam [3:0] ST_ENGINE_CONFIG      = 4'd1;
    localparam [3:0] ST_PARAMETER_REQUEST  = 4'd2;
    localparam [3:0] ST_PARAMETER_WAIT     = 4'd3;
    localparam [3:0] ST_ENGINE_INPUT       = 4'd4;
    localparam [3:0] ST_ENGINE_OUTPUT      = 4'd5;
    localparam [3:0] ST_FULLBAND_STREAM    = 4'd6;
    localparam [3:0] ST_WAIT_PROJECTION    = 4'd7;
    localparam [3:0] ST_CAPTURE_PROJECTION = 4'd8;
    localparam [3:0] ST_SUBBANDS_VALID     = 4'd9;
    localparam [3:0] ST_SERVE              = 4'd10;
    localparam [3:0] ST_ERROR              = 4'd11;

    localparam [7:0] ERR_AXIS_KEEP         = 8'h80;
    localparam [7:0] ERR_AXIS_LAST         = 8'h81;
    localparam [7:0] ERR_FRAME_ID          = 8'h82;
    localparam [7:0] ERR_PROJECTION_START  = 8'h83;
    localparam [7:0] ERR_PROJECTION_INDEX  = 8'h84;
    localparam [7:0] ERR_PROJECTION_LAST   = 8'h85;
    localparam [7:0] ERR_PROJECTION_VALUE  = 8'h86;
    localparam [7:0] ERR_PARAMETER_ROM     = 8'h87;
    localparam [7:0] ERR_ENGINE            = 8'h88;
    localparam [7:0] ERR_SB_READ           = 8'h89;
    localparam [7:0] ERR_FRAME_DONE        = 8'h8a;

    reg [3:0] state_q;
    reg [5:0] magnitude_beat_q;
    reg [63:0] magnitude_memory [0:63];
    reg magnitude_buffer_valid_q;
    reg [FRAME_ID_WIDTH-1:0] magnitude_frame_q;

    reg signed [7:0] fullband_buffer [0:63];
    reg [2:0] fullband_beat_q;
    reg signed [15:0] projection_q12_buffer [0:63];
    reg [6:0] projection_count_q;

    (* rom_style = "distributed" *) reg signed [15:0]
        projection_dequant_memory [0:254];
    (* rom_style = "block" *) reg [8:0] source_index_memory [0:781];
    reg signed [7:0] subband_buffer [0:781];
    reg subband_buffer_valid_q;
    reg [FRAME_ID_WIDTH-1:0] subband_frame_q;

    reg [3:0] vector_id_q;
    reg [1:0] profile_q;
    reg [9:0] payload_base_q;
    reg [7:0] element_index_q;
    reg [8:0] source_index_q;
    reg signed [15:0] source_value_q;
    reg signed [15:0] parameter_weight_q;
    reg signed [15:0] parameter_bias_q;

    reg sb_rsp_valid_q;
    reg signed [7:0] sb_rsp_data_q;
    reg sb_rsp_error_q;
    reg sb_error_pending_q;
    reg [31:0] sb_error_detail_q;

    reg frame_cycle_active_q;
    reg [31:0] working_frame_cycle_count_q;

    wire [7:0] profile_length;
    wire [31:0] profile_reciprocal_q20;
    wire parameter_request_ready;
    wire parameter_response_valid;
    wire signed [15:0] parameter_response_weight_q12;
    wire signed [15:0] parameter_response_bias_q12;
    wire parameter_response_error;

    wire engine_config_ready;
    wire engine_input_ready;
    wire engine_output_valid;
    wire signed [7:0] engine_output_data;
    wire [7:0] engine_output_index;
    wire engine_output_last;
    wire engine_busy;
    wire engine_done;
    wire engine_error;
    wire [7:0] engine_error_code;
    wire [31:0] engine_cycle_count;

    wire magnitude_fire;
    wire parameter_request_fire;
    wire parameter_response_fire;
    wire engine_config_fire;
    wire engine_input_fire;
    wire engine_output_fire;
    wire fullband_fire;
    wire coefficient_fire;
    wire subbands_fire;
    wire sb_read_fire;
    wire sb_rsp_fire;
    wire sb_read_identity_ok;
    wire [7:0] projection_lut_index;

    integer lane;

    initial begin
        `include "projection_dequant_q12_init.vh"
        `include "subband_source_index_init.vh"
    end

    function [1:0] profile_for_vector;
        input [3:0] vector_id;
        begin
            if (vector_id < 4)
                profile_for_vector = 2'd1;
            else if (vector_id < 7)
                profile_for_vector = 2'd2;
            else
                profile_for_vector = 2'd3;
        end
    endfunction

    function [9:0] base_for_vector;
        input [3:0] vector_id;
        begin
            case (vector_id)
                4'd0: base_for_vector = 10'd0;
                4'd1: base_for_vector = 10'd46;
                4'd2: base_for_vector = 10'd92;
                4'd3: base_for_vector = 10'd138;
                4'd4: base_for_vector = 10'd184;
                4'd5: base_for_vector = 10'd278;
                4'd6: base_for_vector = 10'd372;
                4'd7: base_for_vector = 10'd466;
                default: base_for_vector = 10'd624;
            endcase
        end
    endfunction

    function signed [15:0] magnitude_value;
        input [7:0] index;
        reg [63:0] word_value;
        begin
            word_value = magnitude_memory[index[7:2]];
            case (index[1:0])
                2'd0: magnitude_value = word_value[15:0];
                2'd1: magnitude_value = word_value[31:16];
                2'd2: magnitude_value = word_value[47:32];
                default: magnitude_value = word_value[63:48];
            endcase
        end
    endfunction

    task latch_error;
        input [7:0] code;
        input [31:0] detail;
        begin
            if (!error_valid) begin
                error_valid <= 1'b1;
                error_code <= code;
                error_detail <= detail;
            end
            state_q <= ST_ERROR;
        end
    endtask

    assign s_axis_magnitude_tready = rst_n && !abort && !error_valid &&
        (state_q == ST_INGRESS) && !magnitude_buffer_valid_q;
    assign magnitude_fire = s_axis_magnitude_tvalid &&
                            s_axis_magnitude_tready;

    assign m_axis_fullband_tvalid = (state_q == ST_FULLBAND_STREAM) &&
                                    !abort && !error_valid;
    assign m_axis_fullband_tkeep = 8'hff;
    assign m_axis_fullband_tlast = (fullband_beat_q == 3'd7);
    assign m_axis_fullband_tdata = {
        fullband_buffer[fullband_beat_q*8 + 7],
        fullband_buffer[fullband_beat_q*8 + 6],
        fullband_buffer[fullband_beat_q*8 + 5],
        fullband_buffer[fullband_beat_q*8 + 4],
        fullband_buffer[fullband_beat_q*8 + 3],
        fullband_buffer[fullband_beat_q*8 + 2],
        fullband_buffer[fullband_beat_q*8 + 1],
        fullband_buffer[fullband_beat_q*8]
    };
    assign fullband_fire = m_axis_fullband_tvalid && m_axis_fullband_tready;

    assign fb_coefficient_ready = (state_q == ST_CAPTURE_PROJECTION) &&
                                  !abort && !error_valid;
    assign coefficient_fire = fb_coefficient_valid && fb_coefficient_ready;
    assign projection_lut_index = fb_coefficient_value + 8'sd127;

    assign subbands_valid = (state_q == ST_SUBBANDS_VALID) &&
                            !abort && !error_valid;
    assign subbands_fire = subbands_valid && subbands_ready;
    assign sb_buffer_valid = subband_buffer_valid_q;

    assign sb_read_identity_ok = subband_buffer_valid_q &&
        (sb_read_index < 10'd782) &&
        (sb_read_frame_id == subband_frame_q) &&
        (sb_read_frame_id == current_frame_id);
    assign sb_read_ready = rst_n && !abort && !error_valid &&
                           !sb_rsp_valid_q && subband_buffer_valid_q;
    assign sb_read_fire = sb_read_valid && sb_read_ready;
    assign sb_read_rsp_valid = sb_rsp_valid_q;
    assign sb_read_rsp_data = sb_rsp_data_q;
    assign sb_read_rsp_error = sb_rsp_error_q;
    assign sb_rsp_fire = sb_read_rsp_valid && sb_read_rsp_ready;

    assign magnitude_buffer_valid = magnitude_buffer_valid_q;
    assign magnitude_buffer_frame_id = magnitude_frame_q;
    assign busy = (state_q != ST_INGRESS) || (magnitude_beat_q != 0) ||
                  magnitude_buffer_valid_q || subband_buffer_valid_q ||
                  sb_rsp_valid_q || sb_error_pending_q || engine_busy;
    assign quiescent = rst_n && (state_q == ST_INGRESS) &&
        (magnitude_beat_q == 0) && !magnitude_buffer_valid_q &&
        !subband_buffer_valid_q && !sb_rsp_valid_q &&
        !sb_error_pending_q && !engine_busy;
    assign state_debug = state_q;

    assign engine_config_fire = (state_q == ST_ENGINE_CONFIG) &&
                                engine_config_ready;
    assign parameter_request_fire = (state_q == ST_PARAMETER_REQUEST) &&
                                    parameter_request_ready;
    assign parameter_response_fire = parameter_response_valid &&
                                     (state_q == ST_PARAMETER_WAIT);
    assign engine_input_fire = (state_q == ST_ENGINE_INPUT) &&
                               engine_input_ready;
    assign engine_output_fire = engine_output_valid &&
                                (state_q == ST_ENGINE_OUTPUT);

    layernorm_parameter_rom_q12 u_parameter_rom (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort || error_valid),
        .config_profile(profile_q),
        .config_length(profile_length),
        .config_output_reciprocal_q20(profile_reciprocal_q20),
        .request_valid(state_q == ST_PARAMETER_REQUEST),
        .request_ready(parameter_request_ready),
        .request_profile(profile_q),
        .request_index(element_index_q),
        .response_valid(parameter_response_valid),
        .response_ready(state_q == ST_PARAMETER_WAIT),
        .response_weight_q12(parameter_response_weight_q12),
        .response_bias_q12(parameter_response_bias_q12),
        .response_error(parameter_response_error)
    );

    layernorm_engine_q12 u_layernorm_engine (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort || error_valid),
        .config_valid(state_q == ST_ENGINE_CONFIG),
        .config_ready(engine_config_ready),
        .config_length(profile_length),
        .config_output_reciprocal_q20(profile_reciprocal_q20),
        .config_epsilon_q24(32'd168),
        .input_valid(state_q == ST_ENGINE_INPUT),
        .input_ready(engine_input_ready),
        .input_value_q12(source_value_q),
        .input_weight_q12(parameter_weight_q),
        .input_bias_q12(parameter_bias_q),
        .input_last(element_index_q == (profile_length - 1'b1)),
        .output_valid(engine_output_valid),
        .output_ready(state_q == ST_ENGINE_OUTPUT),
        .output_data(engine_output_data),
        .output_index(engine_output_index),
        .output_last(engine_output_last),
        .busy(engine_busy),
        .done(engine_done),
        .error(engine_error),
        .error_code(engine_error_code),
        .cycle_count(engine_cycle_count)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_INGRESS;
            magnitude_beat_q <= 6'd0;
            magnitude_buffer_valid_q <= 1'b0;
            magnitude_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            fullband_beat_q <= 3'd0;
            projection_count_q <= 7'd0;
            subband_buffer_valid_q <= 1'b0;
            subband_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            vector_id_q <= 4'd0;
            profile_q <= 2'd0;
            payload_base_q <= 10'd0;
            element_index_q <= 8'd0;
            source_index_q <= 9'd0;
            source_value_q <= 16'sd0;
            parameter_weight_q <= 16'sd0;
            parameter_bias_q <= 16'sd0;
            sb_rsp_valid_q <= 1'b0;
            sb_rsp_data_q <= 8'sd0;
            sb_rsp_error_q <= 1'b0;
            sb_error_pending_q <= 1'b0;
            sb_error_detail_q <= 32'd0;
            frame_cycle_active_q <= 1'b0;
            working_frame_cycle_count_q <= 32'd0;
            last_frame_cycle_count <= 32'd0;
            error_valid <= 1'b0;
            error_code <= 8'd0;
            error_detail <= 32'd0;
        end else begin
            if (frame_cycle_active_q)
                working_frame_cycle_count_q <=
                    working_frame_cycle_count_q + 1'b1;

            if (engine_error)
                latch_error(ERR_ENGINE, {24'd0, engine_error_code});

            if (sb_rsp_fire) begin
                sb_rsp_valid_q <= 1'b0;
                sb_rsp_error_q <= 1'b0;
            end
            if (sb_read_fire) begin
                sb_rsp_valid_q <= 1'b1;
                sb_rsp_error_q <= !sb_read_identity_ok;
                if (sb_read_identity_ok)
                    sb_rsp_data_q <= subband_buffer[sb_read_index];
                else begin
                    sb_rsp_data_q <= 8'sd0;
                    sb_error_pending_q <= 1'b1;
                    sb_error_detail_q <=
                        {6'd0, sb_read_index, sb_read_frame_id[15:0]};
                end
            end

            if (abort) begin
                state_q <= error_valid ? ST_ERROR : ST_INGRESS;
                magnitude_beat_q <= 6'd0;
                magnitude_buffer_valid_q <= 1'b0;
                subband_buffer_valid_q <= 1'b0;
                sb_rsp_valid_q <= 1'b0;
                sb_error_pending_q <= 1'b0;
                frame_cycle_active_q <= 1'b0;
            end else if (!engine_error && sb_error_pending_q) begin
                sb_error_pending_q <= 1'b0;
                latch_error(ERR_SB_READ, sb_error_detail_q);
            end else if (!error_valid && !engine_error) begin
                case (state_q)
                    ST_INGRESS: begin
                        if (magnitude_fire) begin
                            if (s_axis_magnitude_tkeep != 8'hff) begin
                                latch_error(ERR_AXIS_KEEP,
                                    {18'd0, magnitude_beat_q,
                                     s_axis_magnitude_tkeep});
                            end else if (s_axis_magnitude_tlast !=
                                         (magnitude_beat_q == 6'd63)) begin
                                latch_error(ERR_AXIS_LAST,
                                    {25'd0, s_axis_magnitude_tlast,
                                     magnitude_beat_q});
                            end else begin
                                magnitude_memory[magnitude_beat_q] <=
                                    s_axis_magnitude_tdata;
                                if (magnitude_beat_q == 0) begin
                                    magnitude_frame_q <= current_frame_id;
                                    frame_cycle_active_q <= 1'b1;
                                    working_frame_cycle_count_q <= 32'd1;
                                end
                                if ((magnitude_beat_q != 0) &&
                                    (magnitude_frame_q !=
                                     current_frame_id)) begin
                                    latch_error(ERR_FRAME_ID,
                                        {magnitude_frame_q[15:0],
                                         current_frame_id[15:0]});
                                end else if (magnitude_beat_q == 6'd63) begin
                                    magnitude_beat_q <= 6'd0;
                                    magnitude_buffer_valid_q <= 1'b1;
                                    vector_id_q <= 4'd0;
                                    profile_q <= 2'd0;
                                    payload_base_q <= 10'd0;
                                    element_index_q <= 8'd0;
                                    state_q <= ST_ENGINE_CONFIG;
                                end else begin
                                    magnitude_beat_q <= magnitude_beat_q + 1'b1;
                                end
                            end
                        end
                    end

                    ST_ENGINE_CONFIG: begin
                        if (engine_config_fire) begin
                            element_index_q <= 8'd0;
                            state_q <= ST_PARAMETER_REQUEST;
                        end
                    end

                    ST_PARAMETER_REQUEST: begin
                        if (parameter_request_fire) begin
                            if (profile_q != 0)
                                source_index_q <= source_index_memory[
                                    payload_base_q + element_index_q];
                            state_q <= ST_PARAMETER_WAIT;
                        end
                    end

                    ST_PARAMETER_WAIT: begin
                        if (parameter_response_fire) begin
                            if (parameter_response_error) begin
                                latch_error(ERR_PARAMETER_ROM,
                                    {22'd0, profile_q, element_index_q});
                            end else begin
                                parameter_weight_q <=
                                    parameter_response_weight_q12;
                                parameter_bias_q <=
                                    parameter_response_bias_q12;
                                if (profile_q == 0)
                                    source_value_q <=
                                        magnitude_value(element_index_q);
                                else if (source_index_q < 9'd256)
                                    source_value_q <=
                                        magnitude_value(source_index_q[7:0]);
                                else
                                    source_value_q <= projection_q12_buffer[
                                        source_index_q - 9'd256];
                                state_q <= ST_ENGINE_INPUT;
                            end
                        end
                    end

                    ST_ENGINE_INPUT: begin
                        if (engine_input_fire) begin
                            if (element_index_q == (profile_length - 1'b1))
                                state_q <= ST_ENGINE_OUTPUT;
                            else begin
                                element_index_q <= element_index_q + 1'b1;
                                state_q <= ST_PARAMETER_REQUEST;
                            end
                        end
                    end

                    ST_ENGINE_OUTPUT: begin
                        if (engine_output_fire) begin
                            if (profile_q == 0)
                                fullband_buffer[engine_output_index] <=
                                    engine_output_data;
                            else
                                subband_buffer[payload_base_q +
                                    engine_output_index] <= engine_output_data;
                            if (engine_output_last) begin
                                if (profile_q == 0) begin
                                    fullband_beat_q <= 3'd0;
                                    state_q <= ST_FULLBAND_STREAM;
                                end else if (vector_id_q != 4'd8) begin
                                    vector_id_q <= vector_id_q + 1'b1;
                                    profile_q <= profile_for_vector(
                                        vector_id_q + 1'b1);
                                    payload_base_q <= base_for_vector(
                                        vector_id_q + 1'b1);
                                    element_index_q <= 8'd0;
                                    state_q <= ST_ENGINE_CONFIG;
                                end else begin
                                    subband_buffer_valid_q <= 1'b1;
                                    subband_frame_q <= magnitude_frame_q;
                                    last_frame_cycle_count <=
                                        working_frame_cycle_count_q + 1'b1;
                                    frame_cycle_active_q <= 1'b0;
                                    state_q <= ST_SUBBANDS_VALID;
                                end
                            end
                        end
                    end

                    ST_FULLBAND_STREAM: begin
                        if (fullband_fire) begin
                            if (fullband_beat_q == 3'd7) begin
                                fullband_beat_q <= 3'd0;
                                state_q <= ST_WAIT_PROJECTION;
                            end else begin
                                fullband_beat_q <= fullband_beat_q + 1'b1;
                            end
                        end
                    end

                    ST_WAIT_PROJECTION: begin
                        if (fb_projection_start) begin
                            projection_count_q <= 7'd0;
                            state_q <= ST_CAPTURE_PROJECTION;
                        end
                    end

                    ST_CAPTURE_PROJECTION: begin
                        if (fb_projection_start)
                            latch_error(ERR_PROJECTION_START,
                                {25'd0, projection_count_q});
                        else if (coefficient_fire) begin
                            if (fb_coefficient_index != projection_count_q) begin
                                latch_error(ERR_PROJECTION_INDEX,
                                    {16'd0, fb_coefficient_index,
                                     projection_count_q});
                            end else if (fb_coefficient_last !=
                                         (projection_count_q == 7'd63)) begin
                                latch_error(ERR_PROJECTION_LAST,
                                    {24'd0, fb_coefficient_last,
                                     projection_count_q});
                            end else if (fb_coefficient_value == -8'sd128) begin
                                latch_error(ERR_PROJECTION_VALUE,
                                    {25'd0, projection_count_q});
                            end else begin
                                projection_q12_buffer[projection_count_q] <=
                                    projection_dequant_memory[
                                        projection_lut_index];
                                if (projection_count_q == 7'd63) begin
                                    vector_id_q <= 4'd0;
                                    profile_q <= 2'd1;
                                    payload_base_q <= 10'd0;
                                    element_index_q <= 8'd0;
                                    state_q <= ST_ENGINE_CONFIG;
                                end else begin
                                    projection_count_q <=
                                        projection_count_q + 1'b1;
                                end
                            end
                        end
                    end

                    ST_SUBBANDS_VALID: begin
                        if (subbands_fire)
                            state_q <= ST_SERVE;
                    end

                    ST_SERVE: begin
                        if (frame_done) begin
                            if (sb_rsp_valid_q)
                                latch_error(ERR_FRAME_DONE, 32'd1);
                            else begin
                                magnitude_buffer_valid_q <= 1'b0;
                                subband_buffer_valid_q <= 1'b0;
                                state_q <= ST_INGRESS;
                            end
                        end
                    end

                    default: state_q <= ST_ERROR;
                endcase
            end
        end
    end
endmodule
