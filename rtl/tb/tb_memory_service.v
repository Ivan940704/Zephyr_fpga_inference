`timescale 1ns/1ps
`include "memory/model_memory_v4_map.vh"

module tb_memory_service;
    localparam [31:0] PARAMETER_BASE = 32'h1000_0000;
    localparam integer IMAGE_BYTES = `MODEL_V4_IMAGE_BYTES;
    localparam integer TAG_WIDTH = 8;

    reg clk;
    reg rst_n;
    reg abort;
    reg clear_error;

    reg [31:0] parameter_base_addr;
    reg [31:0] image_version;
    reg stage_req_valid;
    wire stage_req_ready;
    reg [3:0] stage_req_id;
    wire stage_load_done;
    wire stage_load_error;
    wire stage_ready_for_compute;
    wire lut_ready;
    reg stage_release_valid;
    wire stage_release_ready;
    reg [3:0] stage_release_id;
    wire [2:0] cache_state;
    wire [3:0] active_stage_id;
    wire [31:0] active_image_version;
    wire active_stage_kind;
    wire [1:0] active_matrix_count;
    wire [9:0] active_matrix0_sources;
    wire [5:0] active_matrix0_row_tiles;
    wire [9:0] active_matrix1_sources;
    wire [5:0] active_matrix1_row_tiles;
    wire [5:0] active_param_tiles;
    wire active_uses_sigmoid_table;
    wire [2:0] active_sigmoid_table_select;
    wire error_valid;
    wire [7:0] error_code;
    wire [3:0] error_stage;
    wire [31:0] error_detail;
    wire raw_loader_busy;
    wire raw_loader_done;
    wire raw_loader_error;
    wire raw_loader_timeout;
    wire raw_loader_abort_drain;

    reg weight_req_valid;
    wire weight_req_ready;
    reg weight_req_matrix;
    reg [9:0] weight_req_source;
    reg [5:0] weight_req_row_tile;
    reg [TAG_WIDTH-1:0] weight_req_tag;
    wire weight_rsp_valid;
    reg weight_rsp_ready;
    wire [127:0] weight_rsp_data;
    wire [TAG_WIDTH-1:0] weight_rsp_tag;
    wire weight_rsp_error;

    reg param_req_valid;
    wire param_req_ready;
    reg [5:0] param_req_row_tile;
    reg [TAG_WIDTH-1:0] param_req_tag;
    wire param_rsp_valid;
    reg param_rsp_ready;
    wire [5791:0] param_rsp_data;
    wire param_rsp_kind;
    wire [12:0] param_rsp_bits;
    wire [TAG_WIDTH-1:0] param_rsp_tag;
    wire param_rsp_error;

    wire lut_cfg_valid;
    reg lut_cfg_ready;
    wire [3:0] lut_cfg_stage_id;
    wire [7:0] lut_cfg_addr;
    wire [7:0] lut_cfg_data;

    wire [31:0] m_axi_araddr;
    wire [0:0] m_axi_arid;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire [2:0] m_axi_arprot;
    wire [3:0] m_axi_arcache;
    wire [3:0] m_axi_arqos;
    wire m_axi_arlock;
    wire m_axi_arvalid;
    wire m_axi_arready;
    reg [63:0] m_axi_rdata;
    reg [0:0] m_axi_rid;
    reg [1:0] m_axi_rresp;
    reg m_axi_rlast;
    reg m_axi_rvalid;
    wire m_axi_rready;

    reg [3:0] reference_stage_id;
    wire ref_valid;
    wire ref_kind;
    wire [31:0] ref_dram_offset;
    wire [31:0] ref_transfer_bytes;
    wire [1:0] ref_matrix_count;
    wire [31:0] ref_matrix0_word_offset;
    wire [9:0] ref_matrix0_sources;
    wire [5:0] ref_matrix0_row_tiles;
    wire [31:0] ref_matrix1_word_offset;
    wire [9:0] ref_matrix1_sources;
    wire [5:0] ref_matrix1_row_tiles;
    wire [31:0] ref_param_word_offset;
    wire [7:0] ref_param_record_words;
    wire [12:0] ref_param_response_bits;
    wire [5:0] ref_param_tiles;
    wire ref_uses_sigmoid;
    wire [2:0] ref_sigmoid_select;

    model_memory_v4_table reference_table (
        .stage_id(reference_stage_id),
        .stage_valid(ref_valid),
        .stage_kind(ref_kind),
        .dram_byte_offset(ref_dram_offset),
        .transfer_bytes(ref_transfer_bytes),
        .matrix_count(ref_matrix_count),
        .matrix0_word_offset(ref_matrix0_word_offset),
        .matrix0_sources(ref_matrix0_sources),
        .matrix0_row_tiles(ref_matrix0_row_tiles),
        .matrix1_word_offset(ref_matrix1_word_offset),
        .matrix1_sources(ref_matrix1_sources),
        .matrix1_row_tiles(ref_matrix1_row_tiles),
        .param_word_offset(ref_param_word_offset),
        .param_record_words(ref_param_record_words),
        .param_response_bits(ref_param_response_bits),
        .param_tiles(ref_param_tiles),
        .uses_sigmoid_table(ref_uses_sigmoid),
        .sigmoid_table_select(ref_sigmoid_select)
    );

    memory_service #(
        .LOAD_TIMEOUT_CYCLES(64),
        .TAG_WIDTH(TAG_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .clear_error(clear_error),
        .parameter_base_addr(parameter_base_addr),
        .image_version(image_version),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready),
        .stage_req_id(stage_req_id),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .stage_ready_for_compute(stage_ready_for_compute),
        .lut_ready(lut_ready),
        .stage_release_valid(stage_release_valid),
        .stage_release_ready(stage_release_ready),
        .stage_release_id(stage_release_id),
        .cache_state(cache_state),
        .active_stage_id(active_stage_id),
        .active_image_version(active_image_version),
        .active_stage_kind(active_stage_kind),
        .active_matrix_count(active_matrix_count),
        .active_matrix0_sources(active_matrix0_sources),
        .active_matrix0_row_tiles(active_matrix0_row_tiles),
        .active_matrix1_sources(active_matrix1_sources),
        .active_matrix1_row_tiles(active_matrix1_row_tiles),
        .active_param_tiles(active_param_tiles),
        .active_uses_sigmoid_table(active_uses_sigmoid_table),
        .active_sigmoid_table_select(active_sigmoid_table_select),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_stage(error_stage),
        .error_detail(error_detail),
        .raw_loader_busy(raw_loader_busy),
        .raw_loader_done(raw_loader_done),
        .raw_loader_error(raw_loader_error),
        .raw_loader_timeout(raw_loader_timeout),
        .raw_loader_abort_drain(raw_loader_abort_drain),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready),
        .weight_req_matrix(weight_req_matrix),
        .weight_req_source(weight_req_source),
        .weight_req_row_tile(weight_req_row_tile),
        .weight_req_tag(weight_req_tag),
        .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready),
        .weight_rsp_data(weight_rsp_data),
        .weight_rsp_tag(weight_rsp_tag),
        .weight_rsp_error(weight_rsp_error),
        .param_req_valid(param_req_valid),
        .param_req_ready(param_req_ready),
        .param_req_row_tile(param_req_row_tile),
        .param_req_tag(param_req_tag),
        .param_rsp_valid(param_rsp_valid),
        .param_rsp_ready(param_rsp_ready),
        .param_rsp_data(param_rsp_data),
        .param_rsp_kind(param_rsp_kind),
        .param_rsp_bits(param_rsp_bits),
        .param_rsp_tag(param_rsp_tag),
        .param_rsp_error(param_rsp_error),
        .lut_cfg_valid(lut_cfg_valid),
        .lut_cfg_ready(lut_cfg_ready),
        .lut_cfg_stage_id(lut_cfg_stage_id),
        .lut_cfg_addr(lut_cfg_addr),
        .lut_cfg_data(lut_cfg_data),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arid(m_axi_arid),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rid(m_axi_rid),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    reg [7:0] dram [0:IMAGE_BYTES-1];
    reg dram_active;
    reg [31:0] dram_read_addr;
    reg [8:0] dram_beats_left;
    reg force_axi_stall;
    reg inject_axi_error;
    integer cycle_count;
    integer ar_count;
    integer axi_command_bytes;
    integer failures;
    integer checks;
    integer lut_count;
    reg lut_stall_active;
    reg [3:0] stalled_lut_table;
    reg [7:0] stalled_lut_addr;
    reg [7:0] stalled_lut_data;

    always #5 clk = ~clk;
    assign m_axi_arready = !dram_active && !force_axi_stall &&
                           (cycle_count[2:0] != 3'b101);

    task fail;
        input [8*180-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at time %0t", message, $time);
        end
    endtask

    task check;
        input condition;
        input [8*180-1:0] message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    function [63:0] image_word;
        input [31:0] byte_address;
        integer lane;
        integer image_index;
        begin
            image_word = 64'd0;
            image_index = byte_address - PARAMETER_BASE;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if ((image_index + lane >= 0) &&
                    (image_index + lane < IMAGE_BYTES))
                    image_word[lane*8 +: 8] = dram[image_index + lane];
                else
                    image_word[lane*8 +: 8] = 8'hxx;
            end
        end
    endfunction

    // One-outstanding-burst DDR model with deterministic command/data stalls.
    always @(posedge clk) begin
        if (!rst_n) begin
            dram_active <= 1'b0;
            dram_read_addr <= 32'd0;
            dram_beats_left <= 9'd0;
            m_axi_rdata <= 64'd0;
            m_axi_rid <= 1'b0;
            m_axi_rresp <= 2'b00;
            m_axi_rlast <= 1'b0;
            m_axi_rvalid <= 1'b0;
            ar_count <= 0;
            axi_command_bytes <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                dram_active <= 1'b1;
                dram_read_addr <= m_axi_araddr;
                dram_beats_left <= {1'b0, m_axi_arlen} + 1'b1;
                ar_count <= ar_count + 1;
                axi_command_bytes <= axi_command_bytes +
                                     ((m_axi_arlen + 1) * 8);
                check((m_axi_arid == 0) && (m_axi_arsize == 3'd3) &&
                      (m_axi_arburst == 2'b01) &&
                      (m_axi_arprot == 3'b000) &&
                      (m_axi_arcache == 4'b0011) &&
                      (m_axi_arqos == 0) && !m_axi_arlock,
                      "AXI command sideband mismatch");
                check(m_axi_araddr[2:0] == 0,
                      "AXI address is not 64-bit aligned");
                check((m_axi_araddr[11:0] +
                       ((m_axi_arlen + 1) << m_axi_arsize)) <= 4096,
                      "AXI burst crossed 4 KiB");
            end

            if (dram_active && !m_axi_rvalid && !force_axi_stall &&
                (cycle_count[2:0] != 3'b011)) begin
                m_axi_rdata <= image_word(dram_read_addr);
                m_axi_rid <= 1'b0;
                m_axi_rresp <= inject_axi_error ? 2'b10 : 2'b00;
                m_axi_rlast <= (dram_beats_left == 1);
                m_axi_rvalid <= 1'b1;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                if (m_axi_rlast) begin
                    dram_active <= 1'b0;
                end else begin
                    dram_read_addr <= dram_read_addr + 8;
                    dram_beats_left <= dram_beats_left - 1'b1;
                end
            end
        end
    end

    // Global LUT byte stream checker, including held-response stability.
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            lut_cfg_ready <= 1'b0;
            lut_count <= 0;
            lut_stall_active <= 1'b0;
            stalled_lut_table <= 4'd0;
            stalled_lut_addr <= 8'd0;
            stalled_lut_data <= 8'd0;
        end else begin
            cycle_count <= cycle_count + 1;
            lut_cfg_ready <= (cycle_count[2:0] != 3'b110);

            if (lut_cfg_valid && !lut_cfg_ready) begin
                if (lut_stall_active) begin
                    check((lut_cfg_stage_id === stalled_lut_table) &&
                          (lut_cfg_addr === stalled_lut_addr) &&
                          (lut_cfg_data === stalled_lut_data),
                          "LUT stream changed while stalled");
                end else begin
                    lut_stall_active <= 1'b1;
                    stalled_lut_table <= lut_cfg_stage_id;
                    stalled_lut_addr <= lut_cfg_addr;
                    stalled_lut_data <= lut_cfg_data;
                end
            end

            if (lut_cfg_valid && lut_cfg_ready) begin
                check(lut_count < 2040, "too many LUT bytes");
                check(lut_cfg_stage_id === (lut_count / 255),
                      "LUT table sequence mismatch");
                check(lut_cfg_addr === (lut_count % 255),
                      "LUT address sequence mismatch");
                check(lut_cfg_data ===
                      dram[`MODEL_V4_GLOBAL_SIGMOID_LUT_DRAM_OFFSET +
                           lut_count],
                      "LUT payload mismatch");
                lut_count <= lut_count + 1;
                lut_stall_active <= 1'b0;
            end
        end
    end

    task reset_dut;
        begin
            rst_n = 1'b0;
            abort = 1'b0;
            clear_error = 1'b0;
            force_axi_stall = 1'b0;
            inject_axi_error = 1'b0;
            stage_req_valid = 1'b0;
            stage_release_valid = 1'b0;
            weight_req_valid = 1'b0;
            weight_rsp_ready = 1'b0;
            param_req_valid = 1'b0;
            param_rsp_ready = 1'b0;
            repeat (5) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    task request_stage;
        input [3:0] requested_stage;
        input expected_error;
        integer timeout;
        begin
            @(negedge clk);
            stage_req_id = requested_stage;
            stage_req_valid = 1'b1;
            timeout = 0;
            while (!stage_req_ready && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 1000, "stage request was not accepted");
            @(posedge clk);
            @(negedge clk);
            stage_req_valid = 1'b0;

            timeout = 0;
            while (!stage_load_done && !stage_load_error &&
                   timeout < 1000000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 1000000, "stage completion timed out");
            if (expected_error) begin
                check(stage_load_error && !stage_load_done,
                      "invalid stage did not report load error");
            end else begin
                check(stage_load_done && !stage_load_error,
                      "legal stage load failed");
                check(stage_ready_for_compute && lut_ready,
                      "stage or LUT not ready after legal load");
                check((active_stage_id == requested_stage) &&
                      (active_image_version == `MODEL_V4_IMAGE_VERSION),
                      "active stage identity mismatch");
            end
            @(negedge clk);
        end
    endtask

    task check_descriptors;
        input [3:0] requested_stage;
        begin
            reference_stage_id = requested_stage;
            #1;
            check(ref_valid, "reference stage unexpectedly invalid");
            check(active_stage_kind === ref_kind,
                  "stage kind descriptor mismatch");
            check(active_matrix_count === ref_matrix_count,
                  "matrix count descriptor mismatch");
            check(active_matrix0_sources === ref_matrix0_sources,
                  "matrix0 sources descriptor mismatch");
            check(active_matrix0_row_tiles === ref_matrix0_row_tiles,
                  "matrix0 tiles descriptor mismatch");
            check(active_matrix1_sources === ref_matrix1_sources,
                  "matrix1 sources descriptor mismatch");
            check(active_matrix1_row_tiles === ref_matrix1_row_tiles,
                  "matrix1 tiles descriptor mismatch");
            check(active_param_tiles === ref_param_tiles,
                  "parameter tiles descriptor mismatch");
            check(active_uses_sigmoid_table === ref_uses_sigmoid,
                  "sigmoid-use descriptor mismatch");
            check(active_sigmoid_table_select === ref_sigmoid_select,
                  "sigmoid select descriptor mismatch");
        end
    endtask

    task check_weight;
        input matrix_id;
        input [9:0] source_id;
        input [5:0] tile_id;
        input [7:0] tag_value;
        input integer expected_image_byte;
        input expected_error;
        integer timeout;
        integer lane;
        reg [127:0] held_data;
        begin
            @(negedge clk);
            weight_req_matrix = matrix_id;
            weight_req_source = source_id;
            weight_req_row_tile = tile_id;
            weight_req_tag = tag_value;
            weight_req_valid = 1'b1;
            timeout = 0;
            while (!weight_req_ready && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 1000, "weight request was not accepted");
            @(posedge clk);
            @(negedge clk);
            weight_req_valid = 1'b0;

            timeout = 0;
            while (!weight_rsp_valid && timeout < 1000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 1000, "weight response timed out");
            if (timeout < 1000) begin
                check((weight_rsp_tag === tag_value) &&
                      (weight_rsp_error === expected_error),
                      "weight response metadata mismatch");
                if (expected_error) begin
                    check(weight_rsp_data === 128'd0,
                          "illegal weight returned data");
                end else begin
                    for (lane = 0; lane < 16; lane = lane + 1)
                        check(weight_rsp_data[lane*8 +: 8] ===
                              dram[expected_image_byte + lane],
                              "weight payload mismatch");
                end
                held_data = weight_rsp_data;
                repeat (3) begin
                    @(posedge clk);
                    #1;
                    check(weight_rsp_valid &&
                          (weight_rsp_data === held_data) &&
                          (weight_rsp_tag === tag_value),
                          "weight response changed while stalled");
                end
                @(negedge clk);
                weight_rsp_ready = 1'b1;
                @(posedge clk);
                @(negedge clk);
                weight_rsp_ready = 1'b0;
            end
        end
    endtask

    task check_parameter;
        input [5:0] tile_id;
        input [7:0] tag_value;
        input integer expected_image_byte;
        input integer expected_bytes;
        input expected_kind;
        input [12:0] expected_bits;
        integer timeout;
        integer byte_index;
        reg [5791:0] held_data;
        begin
            @(negedge clk);
            param_req_row_tile = tile_id;
            param_req_tag = tag_value;
            param_req_valid = 1'b1;
            timeout = 0;
            while (!param_req_ready && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 1000, "parameter request was not accepted");
            @(posedge clk);
            @(negedge clk);
            param_req_valid = 1'b0;

            timeout = 0;
            while (!param_rsp_valid && timeout < 2000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 2000, "parameter response timed out");
            if (timeout < 2000) begin
                check(!param_rsp_error && (param_rsp_tag === tag_value) &&
                      (param_rsp_kind === expected_kind) &&
                      (param_rsp_bits === expected_bits),
                      "parameter response metadata mismatch");
                for (byte_index = 0; byte_index < expected_bytes;
                     byte_index = byte_index + 1)
                    check(param_rsp_data[byte_index*8 +: 8] ===
                          dram[expected_image_byte + byte_index],
                          "parameter payload mismatch");
                held_data = param_rsp_data;
                repeat (3) begin
                    @(posedge clk);
                    #1;
                    check(param_rsp_valid &&
                          (param_rsp_data === held_data) &&
                          (param_rsp_tag === tag_value),
                          "parameter response changed while stalled");
                end
                @(negedge clk);
                param_rsp_ready = 1'b1;
                @(posedge clk);
                @(negedge clk);
                param_rsp_ready = 1'b0;
            end
        end
    endtask

    task release_stage;
        input [3:0] release_id;
        begin
            @(negedge clk);
            stage_release_id = release_id;
            stage_release_valid = 1'b1;
            check(stage_release_ready, "stage release was not ready");
            @(posedge clk);
            @(negedge clk);
            stage_release_valid = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    integer image_file;
    integer bytes_read;
    integer stage_index;
    integer bytes_before;
    integer lut_before;
    integer expected_local_byte;
    integer ar_before;
    integer timeout;
    reg [8*256-1:0] image_path;

    initial begin
        if (!$value$plusargs("IMAGE=%s", image_path))
            image_path = "parameters_v4.bin";
        image_file = $fopen(image_path, "rb");
        if (image_file == 0)
            $fatal(1, "FAIL tb_memory_service cannot open %0s", image_path);
        bytes_read = $fread(dram, image_file);
        $fclose(image_file);
        if (bytes_read != IMAGE_BYTES)
            $fatal(1, "FAIL image bytes=%0d expected=%0d",
                   bytes_read, IMAGE_BYTES);

        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        clear_error = 1'b0;
        parameter_base_addr = PARAMETER_BASE;
        image_version = `MODEL_V4_IMAGE_VERSION;
        stage_req_valid = 1'b0;
        stage_req_id = 4'd0;
        stage_release_valid = 1'b0;
        stage_release_id = 4'd0;
        weight_req_valid = 1'b0;
        weight_req_matrix = 1'b0;
        weight_req_source = 10'd0;
        weight_req_row_tile = 6'd0;
        weight_req_tag = 8'd0;
        weight_rsp_ready = 1'b0;
        param_req_valid = 1'b0;
        param_req_row_tile = 6'd0;
        param_req_tag = 8'd0;
        param_rsp_ready = 1'b0;
        force_axi_stall = 1'b0;
        inject_axi_error = 1'b0;
        reference_stage_id = 4'd0;
        failures = 0;
        checks = 0;

        reset_dut();

        // v3 is rejected before AXI and clear_error cannot recover.
        image_version = 32'd3;
        ar_before = ar_count;
        request_stage(4'd0, 1'b1);
        check(error_valid && (error_code == 8'h02),
              "v3 image did not raise ERR_IMAGE_VERSION");
        check(ar_count == ar_before, "bad image version reached AXI");
        @(negedge clk);
        clear_error = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear_error = 1'b0;
        repeat (2) @(posedge clk);
        check(error_valid && !stage_req_ready,
              "clear_error illegally recovered fatal service");

        image_version = `MODEL_V4_IMAGE_VERSION;
        reset_dut();

        // Load all true stages. First stage includes the global LUT; all later
        // stages transfer exactly their generated bytes and never resend LUT.
        for (stage_index = 0; stage_index < 12;
             stage_index = stage_index + 1) begin
            reference_stage_id = stage_index[3:0];
            #1;
            bytes_before = axi_command_bytes;
            lut_before = lut_count;
            request_stage(stage_index[3:0], 1'b0);
            check_descriptors(stage_index[3:0]);
            if (stage_index == 0) begin
                check((axi_command_bytes - bytes_before) ==
                      (ref_transfer_bytes + 2040),
                      "first stage AXI bytes exclude/include wrong data");
                check((lut_count - lut_before) == 2040,
                      "global LUT byte count mismatch");
            end else begin
                check((axi_command_bytes - bytes_before) ==
                      ref_transfer_bytes,
                      "stage AXI bytes differ from full transfer_bytes");
                check(lut_count == lut_before,
                      "global LUT was resent after release");
            end

            expected_local_byte = ref_dram_offset +
                                  (ref_matrix0_word_offset * 8);
            check_weight(1'b0, 10'd0, 6'd0,
                         8'h20 + stage_index[7:0],
                         expected_local_byte, 1'b0);
            expected_local_byte = ref_dram_offset +
                (ref_matrix0_word_offset * 8) +
                (((ref_matrix0_sources - 1) * ref_matrix0_row_tiles +
                  (ref_matrix0_row_tiles - 1)) * 16);
            check_weight(1'b0, ref_matrix0_sources - 1'b1,
                         ref_matrix0_row_tiles - 1'b1,
                         8'h40 + stage_index[7:0],
                         expected_local_byte, 1'b0);
            if (ref_matrix_count == 2) begin
                expected_local_byte = ref_dram_offset +
                    (ref_matrix1_word_offset * 8) +
                    (((ref_matrix1_sources - 1) * ref_matrix1_row_tiles +
                      (ref_matrix1_row_tiles - 1)) * 16);
                check_weight(1'b1, ref_matrix1_sources - 1'b1,
                             ref_matrix1_row_tiles - 1'b1,
                             8'h60 + stage_index[7:0],
                             expected_local_byte, 1'b0);
            end
            expected_local_byte = ref_dram_offset +
                (ref_param_word_offset * 8) +
                ((ref_param_tiles - 1) * ref_param_record_words * 8);
            check_parameter(ref_param_tiles - 1'b1,
                            8'h80 + stage_index[7:0],
                            expected_local_byte,
                            ref_param_response_bits / 8,
                            ref_kind,
                            ref_param_response_bits);
            release_stage(stage_index[3:0]);
            check(lut_ready, "normal release cleared global LUT ready");
            check(cache_state == 3'd0,
                  "matching release did not return cache to EMPTY");
        end

        check(lut_count == 2040,
              "normal 12-stage sequence did not stream LUT exactly once");

        // A mismatched release is fatal and does not permit clear recovery.
        request_stage(4'd2, 1'b0);
        @(negedge clk);
        stage_release_id = 4'd3;
        stage_release_valid = 1'b1;
        check(stage_release_ready, "wrong release was not accepted for check");
        @(posedge clk);
        @(negedge clk);
        stage_release_valid = 1'b0;
        check(error_valid && (error_code == 8'h08) &&
              !stage_ready_for_compute && !stage_req_ready,
              "wrong release did not close service fatally");
        clear_error = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear_error = 1'b0;
        check(error_valid && (cache_state == 3'd7),
              "clear_error recovered release fault");

        // Reset starts a fresh LUT epoch.
        reset_dut();
        bytes_before = axi_command_bytes;
        request_stage(4'd11, 1'b0);
        check(lut_count == 2040, "reset did not reinitialize global LUT");
        check((axi_command_bytes - bytes_before) ==
              (`MODEL_V4_GLOBAL_SIGMOID_LUT_TRANSFER_BYTES +
               `MODEL_V4_STAGE_11_TRANSFER_BYTES),
              "post-reset LUT+stage transfer size mismatch");
        release_stage(4'd11);

        // An illegal native request returns its tagged error and permanently
        // fences further admission.
        request_stage(4'd2, 1'b0);
        check_weight(1'b0, 10'd320, 6'd0, 8'hee, 0, 1'b1);
        check(error_valid && (error_code == 8'h09) && !stage_req_ready,
              "illegal weight request was not fatal");

        // AXI response errors fail the first (global-LUT) load.
        reset_dut();
        inject_axi_error = 1'b1;
        request_stage(4'd0, 1'b1);
        check(error_valid && (error_code == 8'h06),
              "AXI RRESP error did not produce ERR_AXI_LOAD");

        // A data-channel timeout is immediately fatal and advertises drain.
        reset_dut();
        ar_before = ar_count;
        @(negedge clk);
        stage_req_id = 4'd0;
        stage_req_valid = 1'b1;
        while (!stage_req_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        timeout = 0;
        while ((ar_count == ar_before) && (timeout < 1000)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 1000, "timeout test never accepted AXI burst");
        force_axi_stall = 1'b1;
        timeout = 0;
        while (!stage_load_error && (timeout < 1000)) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        check(timeout < 1000, "accepted AXI burst did not time out");
        check(error_valid && (error_code == 8'h07) && raw_loader_timeout,
              "AXI timeout did not produce ERR_AXI_TIMEOUT");
        check(raw_loader_abort_drain,
              "timed-out accepted burst did not expose abort drain");

        // Reset terminates the intentionally stalled model, then an explicit
        // abort of a live load also requires reset.
        reset_dut();
        ar_before = ar_count;
        @(negedge clk);
        stage_req_id = 4'd1;
        stage_req_valid = 1'b1;
        while (!stage_req_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        timeout = 0;
        while ((ar_count == ar_before) && (timeout < 1000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 1000, "abort test never issued AXI command");
        @(negedge clk);
        abort = 1'b1;
        @(posedge clk);
        @(negedge clk);
        abort = 1'b0;
        check(error_valid && (error_code == 8'h0b) && !stage_req_ready,
              "explicit abort did not enter reset-only fatal state");

        if (failures == 0)
            $display("PASS tb_memory_service checks=%0d", checks);
        else
            $fatal(1, "FAIL tb_memory_service errors=%0d checks=%0d",
                   failures, checks);

        #20;
        $finish;
    end
endmodule
