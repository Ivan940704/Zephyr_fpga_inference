`timescale 1ns/1ps

// Production AXI4-Lite control/status plane for accelerator_system_top.
//
// The register file keeps configuration writes separate from the active
// accelerator epoch.  PARAM_BASE and CONFIG are shadow registers; writing a
// START command atomically copies both into the active registers and holds a
// start request until accelerator_start_ready is observed.
//
// Mailbox ownership commands are also held until the mailbox accepts them, so
// PS software cannot lose a release/claim/commit event to one-cycle timing.
module accelerator_control_axil #(
    parameter integer AXI_ADDR_WIDTH = 12,
    parameter integer FRAME_ID_WIDTH = 16,
    parameter integer USE_PL_LAYERNORM = 1,
    parameter [31:0] IMAGE_VERSION = 32'h0005_0003
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [2:0]                   s_axi_awprot,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [31:0]                  s_axi_wdata,
    input  wire [3:0]                   s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,
    output reg  [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [2:0]                   s_axi_arprot,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,
    output reg  [31:0]                  s_axi_rdata,
    output reg  [1:0]                   s_axi_rresp,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    input  wire                         accelerator_reset_active,
    input  wire                         accelerator_soft_reset_safe,
    input  wire                         accelerator_start_ready,
    input  wire                         accelerator_busy,
    input  wire                         accelerator_done,
    input  wire                         accelerator_error,
    input  wire                         accelerator_reset_required,
    input  wire [3:0]                   accelerator_error_code,
    input  wire [3:0]                   accelerator_state,
    input  wire [31:0]                  accelerator_state_cycles,
    input  wire                         accelerator_sparse_mode,
    input  wire [FRAME_ID_WIDTH-1:0]    accelerator_frame_id,

    input  wire [3:0]                   fb_slot_states,
    input  wire [3:0]                   sb_slot_states,
    input  wire [FRAME_ID_WIDTH-1:0]    expected_fb_frame_id,
    input  wire [FRAME_ID_WIDTH-1:0]    expected_sb_frame_id,
    input  wire [FRAME_ID_WIDTH-1:0]    expected_consume_frame_id,
    input  wire                         fb_published_valid,
    input  wire                         fb_published_slot,
    input  wire [FRAME_ID_WIDTH-1:0]    fb_published_frame_id,
    input  wire                         sb_committed_valid,
    input  wire                         sb_committed_slot,
    input  wire [FRAME_ID_WIDTH-1:0]    sb_committed_frame_id,
    input  wire                         sb_released_valid,
    input  wire                         sb_released_slot,
    input  wire [FRAME_ID_WIDTH-1:0]    sb_released_frame_id,
    input  wire                         mailbox_error_valid,
    input  wire [7:0]                   mailbox_error_code,
    input  wire                         mailbox_error_slot,
    input  wire [FRAME_ID_WIDTH-1:0]    mailbox_error_frame_id,
    input  wire                         mailbox_irq,

    input  wire                         fb_input_buffer_valid,
    input  wire [FRAME_ID_WIDTH-1:0]    fb_input_buffer_frame_id,
    input  wire                         spectrum_input_buffer_valid,
    input  wire [FRAME_ID_WIDTH-1:0]    spectrum_input_buffer_frame_id,
    input  wire [3:0]                   active_stage_id,
    input  wire [2:0]                   cache_state,
    input  wire [3:0]                   compute_owner,
    input  wire [5:0]                   controller_state,
    input  wire [31:0]                  weight_request_count,
    input  wire [31:0]                  dense_weight_request_count,
    input  wire [31:0]                  sparse_weight_request_count,
    input  wire                         sparse_stage_diag_valid,
    input  wire                         sparse_stage_diag_success,
    input  wire [3:0]                   sparse_stage_diag_stage_id,
    input  wire                         sparse_stage_diag_enabled,
    input  wire                         sparse_stage_diag_fallback_full,
    input  wire [31:0]                  sparse_stage_actual_bytes,
    input  wire [31:0]                  sparse_stage_saved_bytes,
    input  wire [31:0]                  sparse_stage_ar_burst_count,
    input  wire [31:0]                  sparse_stage_load_cycles,

    input  wire [31:0]                  profiling_read_data,
    input  wire                         profiling_snapshot_valid,
    input  wire                         profiling_frame_active,
    input  wire                         profiling_snapshot_busy,

    input  wire                         fault_valid,
    input  wire [7:0]                   fault_source,
    input  wire [7:0]                   fault_code,
    input  wire [31:0]                  fault_detail,

    output wire                         start_valid,
    output reg                          abort_pulse,
    output reg                          clear_error_pulse,
    output reg                          soft_reset_pulse,
    output wire                         reset_quiesce_request,
    output wire                         clear_state_on_start,
    output wire                         sparse_load_enable,
    output wire [31:0]                  parameter_base_addr,
    output wire [7:0]                   profiling_read_index,
    output wire                         profiling_enable,
    output reg                          profiling_clear_pulse,
    output reg                          profiling_snapshot_pulse,

    output wire                         ps_fb_release_valid,
    input  wire                         ps_fb_release_ready,
    output wire                         ps_fb_release_slot,
    output wire [FRAME_ID_WIDTH-1:0]    ps_fb_release_frame_id,
    output wire                         ps_sb_claim_valid,
    input  wire                         ps_sb_claim_ready,
    output wire                         ps_sb_claim_slot,
    output wire [FRAME_ID_WIDTH-1:0]    ps_sb_claim_frame_id,
    output wire                         ps_sb_commit_valid,
    input  wire                         ps_sb_commit_ready,
    output wire                         ps_sb_commit_slot,
    output wire [FRAME_ID_WIDTH-1:0]    ps_sb_commit_frame_id,

    output wire                         irq,
    output wire [31:0]                  debug_status
);
    localparam [11:0] REG_COMMAND            = 12'h000;
    localparam [11:0] REG_CONFIG_SHADOW      = 12'h004;
    localparam [11:0] REG_PARAM_BASE_SHADOW  = 12'h008;
    localparam [11:0] REG_CONFIG_ACTIVE      = 12'h00c;
    localparam [11:0] REG_PARAM_BASE_ACTIVE  = 12'h010;
    localparam [11:0] REG_STATUS             = 12'h014;
    localparam [11:0] REG_EXECUTION          = 12'h018;
    localparam [11:0] REG_FRAME_ID           = 12'h01c;
    localparam [11:0] REG_STATE_CYCLES       = 12'h020;
    localparam [11:0] REG_IRQ_ENABLE         = 12'h024;
    localparam [11:0] REG_IRQ_STATUS         = 12'h028;
    localparam [11:0] REG_FIRST_FAULT        = 12'h02c;
    localparam [11:0] REG_FIRST_FAULT_DETAIL = 12'h030;
    localparam [11:0] REG_FIRST_FAULT_FRAME  = 12'h034;
    localparam [11:0] REG_PACKET_BYTES_0     = 12'h038;
    localparam [11:0] REG_PACKET_BYTES_1     = 12'h03c;
    localparam [11:0] REG_FB_RELEASE          = 12'h040;
    localparam [11:0] REG_SB_CLAIM            = 12'h044;
    localparam [11:0] REG_SB_COMMIT           = 12'h048;
    localparam [11:0] REG_MAILBOX_STATES      = 12'h04c;
    localparam [11:0] REG_EXPECTED_FRAMES_0   = 12'h050;
    localparam [11:0] REG_EXPECTED_FRAMES_1   = 12'h054;
    localparam [11:0] REG_FB_EVENT            = 12'h058;
    localparam [11:0] REG_SB_COMMIT_EVENT     = 12'h05c;
    localparam [11:0] REG_SB_RELEASE_EVENT    = 12'h060;
    localparam [11:0] REG_MAILBOX_ERROR_0     = 12'h064;
    localparam [11:0] REG_MAILBOX_ERROR_1     = 12'h068;
    localparam [11:0] REG_MAILBOX_HANDSHAKE   = 12'h06c;
    localparam [11:0] REG_INPUT_BUFFER_STATUS = 12'h070;
    localparam [11:0] REG_INPUT_FRAME_IDS     = 12'h074;
    localparam [11:0] REG_WEIGHT_REQUESTS     = 12'h080;
    localparam [11:0] REG_DENSE_REQUESTS      = 12'h084;
    localparam [11:0] REG_SPARSE_REQUESTS     = 12'h088;
    localparam [11:0] REG_STAGE_ACTUAL_BYTES  = 12'h08c;
    localparam [11:0] REG_STAGE_SAVED_BYTES   = 12'h090;
    localparam [11:0] REG_STAGE_BURSTS        = 12'h094;
    localparam [11:0] REG_STAGE_LOAD_CYCLES   = 12'h098;
    localparam [11:0] REG_STAGE_DIAG          = 12'h09c;
    localparam [11:0] REG_CONTROL_ERROR       = 12'h0a0;
    localparam [11:0] REG_IMAGE_VERSION       = 12'h0a4;
    localparam [11:0] REG_RESET_STATUS        = 12'h0a8;
    localparam [11:0] REG_PROFILE_CONTROL     = 12'h0ac;
    localparam [11:0] REG_PROFILE_STATUS      = 12'h0b0;
    localparam [11:0] REG_PROFILE_BASE        = 12'h100;
    localparam [11:0] REG_PROFILE_LAST        = 12'h3fc;

    localparam [7:0] CTRL_ERR_NONE             = 8'h00;
    localparam [7:0] CTRL_ERR_ILLEGAL_COMMAND  = 8'h01;
    localparam [7:0] CTRL_ERR_START_PENDING    = 8'h02;
    localparam [7:0] CTRL_ERR_EVENT_ENCODING   = 8'h03;
    localparam [7:0] CTRL_ERR_EVENT_PENDING    = 8'h04;
    localparam [7:0] CTRL_ERR_WRITE_ADDRESS    = 8'h05;
    localparam [7:0] CTRL_ERR_UNALIGNED_ACCESS = 8'h06;
    localparam [7:0] CTRL_ERR_RESET_UNSAFE     = 8'h07;
    localparam [7:0] CTRL_ERR_RESET_PENDING    = 8'h08;

    reg [AXI_ADDR_WIDTH-1:0] awaddr_hold_q;
    reg                      aw_hold_valid_q;
    reg [31:0]               wdata_hold_q;
    reg [3:0]                wstrb_hold_q;
    reg                      w_hold_valid_q;

    reg [31:0] config_shadow_q;
    reg [31:0] config_active_q;
    reg [31:0] parameter_base_shadow_q;
    reg [31:0] parameter_base_active_q;
    reg        start_pending_q;
    reg        soft_reset_pending_q;
    reg        reset_quiesce_q;
    reg        accelerator_reset_active_q;
    reg [15:0] reset_epoch_q;
    reg        profiling_enable_q;
    reg        profiling_read_pending_q;
    reg [7:0]  profiling_read_index_q;

    reg        fb_release_pending_q;
    reg        fb_release_slot_q;
    reg [FRAME_ID_WIDTH-1:0] fb_release_frame_q;
    reg        sb_claim_pending_q;
    reg        sb_claim_slot_q;
    reg [FRAME_ID_WIDTH-1:0] sb_claim_frame_q;
    reg        sb_commit_pending_q;
    reg        sb_commit_slot_q;
    reg [FRAME_ID_WIDTH-1:0] sb_commit_frame_q;

    reg [31:0] irq_enable_q;
    reg [31:0] irq_status_q;
    reg        first_fault_valid_q;
    reg [7:0]  first_fault_source_q;
    reg [7:0]  first_fault_code_q;
    reg [31:0] first_fault_detail_q;
    reg [FRAME_ID_WIDTH-1:0] first_fault_frame_q;
    reg        control_error_sticky_q;
    reg [7:0]  control_error_code_q;

    integer byte_index;

    assign s_axi_awready = !aw_hold_valid_q && !s_axi_bvalid;
    assign s_axi_wready  = !w_hold_valid_q && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid && !profiling_read_pending_q;

    wire write_fire = !s_axi_bvalid && aw_hold_valid_q && w_hold_valid_q;
    wire [11:0] write_address = awaddr_hold_q[11:0];
    wire write_aligned = (write_address[1:0] == 2'b00);
    wire [31:0] write_data_masked = wdata_hold_q & {
        {8{wstrb_hold_q[3]}}, {8{wstrb_hold_q[2]}},
        {8{wstrb_hold_q[1]}}, {8{wstrb_hold_q[0]}}
    };
    wire [2:0] lifecycle_command = write_data_masked[2:0];
    wire lifecycle_command_legal =
        (lifecycle_command == 3'b000) ||
        (lifecycle_command == 3'b001) ||
        (lifecycle_command == 3'b010) ||
        (lifecycle_command == 3'b100);
    wire event_encoding_valid = (&wstrb_hold_q) && wdata_hold_q[31];
    wire software_reset_safe = reset_quiesce_q &&
        accelerator_soft_reset_safe &&
        !start_pending_q && !fb_release_pending_q &&
        !sb_claim_pending_q && !sb_commit_pending_q;

    reg write_supported;
    reg write_rejected;
    reg [7:0] write_error_code;
    always @* begin
        write_supported = 1'b1;
        write_rejected = 1'b0;
        write_error_code = CTRL_ERR_NONE;
        if (!write_aligned) begin
            write_rejected = 1'b1;
            write_error_code = CTRL_ERR_UNALIGNED_ACCESS;
        end else begin
            case (write_address)
                REG_COMMAND: begin
                    if (!lifecycle_command_legal ||
                        (|(write_data_masked[31:6]))) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_ILLEGAL_COMMAND;
                    end else if (write_data_masked[0] &&
                                 (reset_quiesce_q ||
                                  soft_reset_pending_q)) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_RESET_PENDING;
                    end else if (write_data_masked[0] && start_pending_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_START_PENDING;
                    end else if (write_data_masked[2] &&
                                 soft_reset_pending_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_RESET_PENDING;
                    end else if (write_data_masked[2] &&
                                 (accelerator_reset_active ||
                                  !software_reset_safe)) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_RESET_UNSAFE;
                    end
                end
                REG_CONFIG_SHADOW,
                REG_PARAM_BASE_SHADOW,
                REG_IRQ_ENABLE,
                REG_IRQ_STATUS: begin
                end
                REG_PROFILE_CONTROL: begin
                    if (!(&wstrb_hold_q) || (|write_data_masked[31:3])) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_ILLEGAL_COMMAND;
                    end
                end
                REG_FB_RELEASE: begin
                    if (!event_encoding_valid) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_EVENT_ENCODING;
                    end else if (reset_quiesce_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_RESET_PENDING;
                    end else if (fb_release_pending_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_EVENT_PENDING;
                    end
                end
                REG_SB_CLAIM: begin
                    if (!event_encoding_valid) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_EVENT_ENCODING;
                    end else if (reset_quiesce_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_RESET_PENDING;
                    end else if (sb_claim_pending_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_EVENT_PENDING;
                    end
                end
                REG_SB_COMMIT: begin
                    if (!event_encoding_valid) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_EVENT_ENCODING;
                    end else if (reset_quiesce_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_RESET_PENDING;
                    end else if (sb_commit_pending_q) begin
                        write_rejected = 1'b1;
                        write_error_code = CTRL_ERR_EVENT_PENDING;
                    end
                end
                default: begin
                    write_supported = 1'b0;
                    write_rejected = 1'b1;
                    write_error_code = CTRL_ERR_WRITE_ADDRESS;
                end
            endcase
        end
    end

    wire write_accepted = write_fire && write_supported && !write_rejected;
    wire command_write = write_accepted && (write_address == REG_COMMAND);
    wire command_start = command_write && write_data_masked[0];
    wire command_abort = command_write && write_data_masked[1];
    wire command_soft_reset = command_write && write_data_masked[2];
    wire command_clear_error = command_write && write_data_masked[3];
    wire command_clear_irq = command_write && write_data_masked[4];
    wire command_reset_quiesce = command_write && write_data_masked[5];
    wire irq_ack_write = write_accepted && (write_address == REG_IRQ_STATUS);
    wire [31:0] irq_ack_mask =
        (command_clear_irq || command_soft_reset) ? 32'hffff_ffff :
        (irq_ack_write ? write_data_masked : 32'd0);

    wire start_fire = start_pending_q && accelerator_start_ready &&
                      !accelerator_reset_active;
    wire [31:0] irq_sources = {
        26'd0,
        control_error_sticky_q,
        start_fire,
        (mailbox_irq && !accelerator_reset_active),
        (accelerator_error || accelerator_reset_required),
        accelerator_done,
        1'b0
    };

    assign start_valid = start_pending_q && !accelerator_reset_active &&
                         !reset_quiesce_q;
    assign clear_state_on_start = config_active_q[1];
    assign sparse_load_enable = config_active_q[0];
    assign parameter_base_addr = parameter_base_active_q;
    assign profiling_read_index = profiling_read_index_q;
    assign profiling_enable = profiling_enable_q;

    assign ps_fb_release_valid = fb_release_pending_q &&
                                 !accelerator_reset_active && !reset_quiesce_q;
    assign ps_fb_release_slot = fb_release_slot_q;
    assign ps_fb_release_frame_id = fb_release_frame_q;
    assign ps_sb_claim_valid = sb_claim_pending_q &&
                               !accelerator_reset_active && !reset_quiesce_q;
    assign ps_sb_claim_slot = sb_claim_slot_q;
    assign ps_sb_claim_frame_id = sb_claim_frame_q;
    assign ps_sb_commit_valid = sb_commit_pending_q &&
                                !accelerator_reset_active && !reset_quiesce_q;
    assign ps_sb_commit_slot = sb_commit_slot_q;
    assign ps_sb_commit_frame_id = sb_commit_frame_q;

    assign irq = |(irq_status_q & irq_enable_q);
    assign reset_quiesce_request = reset_quiesce_q;
    assign debug_status = {
        control_error_code_q,
        irq_status_q[5:0],
        sb_commit_pending_q,
        sb_claim_pending_q,
        fb_release_pending_q,
        accelerator_reset_active,
        accelerator_reset_required,
        accelerator_error,
        accelerator_done,
        accelerator_busy,
        accelerator_start_ready,
        start_pending_q,
        irq
    };

    initial begin
        if (AXI_ADDR_WIDTH < 12)
            $error("AXI_ADDR_WIDTH must cover the 4 KiB control aperture");
        if ((FRAME_ID_WIDTH < 1) || (FRAME_ID_WIDTH > 16))
            $error("FRAME_ID_WIDTH must be in the range 1..16");
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            awaddr_hold_q <= {AXI_ADDR_WIDTH{1'b0}};
            aw_hold_valid_q <= 1'b0;
            wdata_hold_q <= 32'd0;
            wstrb_hold_q <= 4'd0;
            w_hold_valid_q <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            config_shadow_q <= 32'h0000_0003;
            config_active_q <= 32'h0000_0003;
            parameter_base_shadow_q <= 32'd0;
            parameter_base_active_q <= 32'd0;
            start_pending_q <= 1'b0;
            soft_reset_pending_q <= 1'b0;
            reset_quiesce_q <= 1'b0;
            accelerator_reset_active_q <= 1'b0;
            reset_epoch_q <= 16'd0;
            abort_pulse <= 1'b0;
            clear_error_pulse <= 1'b0;
            soft_reset_pulse <= 1'b0;
            profiling_clear_pulse <= 1'b0;
            profiling_snapshot_pulse <= 1'b0;
            profiling_enable_q <= 1'b0;
            profiling_read_pending_q <= 1'b0;
            profiling_read_index_q <= 8'd0;
            fb_release_pending_q <= 1'b0;
            fb_release_slot_q <= 1'b0;
            fb_release_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            sb_claim_pending_q <= 1'b0;
            sb_claim_slot_q <= 1'b0;
            sb_claim_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            sb_commit_pending_q <= 1'b0;
            sb_commit_slot_q <= 1'b0;
            sb_commit_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            irq_enable_q <= 32'd0;
            irq_status_q <= 32'd0;
            first_fault_valid_q <= 1'b0;
            first_fault_source_q <= 8'd0;
            first_fault_code_q <= 8'd0;
            first_fault_detail_q <= 32'd0;
            first_fault_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            control_error_sticky_q <= 1'b0;
            control_error_code_q <= CTRL_ERR_NONE;
        end else begin
            abort_pulse <= 1'b0;
            clear_error_pulse <= 1'b0;
            // proc_sys_reset synchronizes aux_reset_in and can miss a
            // one-cycle request. Hold it until reset_active acknowledges the
            // request; the live AXI-Lite control domain is not reset by it.
            soft_reset_pulse <= soft_reset_pending_q && !accelerator_reset_active;
            profiling_clear_pulse <= 1'b0;
            profiling_snapshot_pulse <= 1'b0;
            accelerator_reset_active_q <= accelerator_reset_active;

            // The live control plane observes completion of the data-plane
            // reset.  Software polls the monotonic epoch instead of trying to
            // sample the short proc_sys_reset active interval.
            if (accelerator_reset_active && !accelerator_reset_active_q) begin
                soft_reset_pending_q <= 1'b0;
                reset_quiesce_q <= 1'b0;
                reset_epoch_q <= reset_epoch_q + 1'b1;
                first_fault_valid_q <= 1'b0;
                first_fault_source_q <= 8'd0;
                first_fault_code_q <= 8'd0;
                first_fault_detail_q <= 32'd0;
                first_fault_frame_q <= {FRAME_ID_WIDTH{1'b0}};
                control_error_sticky_q <= 1'b0;
                control_error_code_q <= CTRL_ERR_NONE;
            end

            irq_status_q <= (irq_status_q | irq_sources) & ~irq_ack_mask;

            if (fault_valid && !first_fault_valid_q) begin
                first_fault_valid_q <= 1'b1;
                first_fault_source_q <= fault_source;
                first_fault_code_q <= fault_code;
                first_fault_detail_q <= fault_detail;
                first_fault_frame_q <= accelerator_frame_id;
            end

            if (start_fire)
                start_pending_q <= 1'b0;
            if (fb_release_pending_q && ps_fb_release_ready)
                fb_release_pending_q <= 1'b0;
            if (sb_claim_pending_q && ps_sb_claim_ready)
                sb_claim_pending_q <= 1'b0;
            if (sb_commit_pending_q && ps_sb_commit_ready)
                sb_commit_pending_q <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_hold_q <= s_axi_awaddr;
                aw_hold_valid_q <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_hold_q <= s_axi_wdata;
                wstrb_hold_q <= s_axi_wstrb;
                w_hold_valid_q <= 1'b1;
            end

            if (write_fire) begin
                aw_hold_valid_q <= 1'b0;
                w_hold_valid_q <= 1'b0;
                s_axi_bresp <= write_rejected ? 2'b10 : 2'b00;
                s_axi_bvalid <= 1'b1;

                if (write_rejected) begin
                    control_error_sticky_q <= 1'b1;
                    control_error_code_q <= write_error_code;
                end else begin
                    case (write_address)
                        REG_COMMAND: begin
                            if (command_start) begin
                                config_active_q <= config_shadow_q;
                                parameter_base_active_q <= parameter_base_shadow_q;
                                start_pending_q <= 1'b1;
                            end
                            if (command_abort) begin
                                abort_pulse <= 1'b1;
                                start_pending_q <= 1'b0;
                                fb_release_pending_q <= 1'b0;
                                sb_claim_pending_q <= 1'b0;
                                sb_commit_pending_q <= 1'b0;
                            end
                            if (command_soft_reset) begin
                                soft_reset_pulse <= 1'b1;
                                soft_reset_pending_q <= 1'b1;
                                start_pending_q <= 1'b0;
                                fb_release_pending_q <= 1'b0;
                                sb_claim_pending_q <= 1'b0;
                                sb_commit_pending_q <= 1'b0;
                            end
                            if (command_reset_quiesce) begin
                                reset_quiesce_q <= 1'b1;
                                start_pending_q <= 1'b0;
                                fb_release_pending_q <= 1'b0;
                                sb_claim_pending_q <= 1'b0;
                                sb_commit_pending_q <= 1'b0;
                            end
                            if (command_clear_error) begin
                                clear_error_pulse <= 1'b1;
                                first_fault_valid_q <= 1'b0;
                                first_fault_source_q <= 8'd0;
                                first_fault_code_q <= 8'd0;
                                first_fault_detail_q <= 32'd0;
                                first_fault_frame_q <= {FRAME_ID_WIDTH{1'b0}};
                                control_error_sticky_q <= 1'b0;
                                control_error_code_q <= CTRL_ERR_NONE;
                            end
                        end
                        REG_CONFIG_SHADOW: begin
                            for (byte_index = 0; byte_index < 4;
                                 byte_index = byte_index + 1)
                                if (wstrb_hold_q[byte_index])
                                    config_shadow_q[byte_index*8 +: 8] <=
                                        wdata_hold_q[byte_index*8 +: 8];
                        end
                        REG_PARAM_BASE_SHADOW: begin
                            for (byte_index = 0; byte_index < 4;
                                 byte_index = byte_index + 1)
                                if (wstrb_hold_q[byte_index])
                                    parameter_base_shadow_q[byte_index*8 +: 8] <=
                                        wdata_hold_q[byte_index*8 +: 8];
                        end
                        REG_IRQ_ENABLE: begin
                            for (byte_index = 0; byte_index < 4;
                                 byte_index = byte_index + 1)
                                if (wstrb_hold_q[byte_index])
                                    irq_enable_q[byte_index*8 +: 8] <=
                                        wdata_hold_q[byte_index*8 +: 8];
                        end
                        REG_PROFILE_CONTROL: begin
                            profiling_enable_q <= write_data_masked[0];
                            profiling_clear_pulse <= write_data_masked[1];
                            profiling_snapshot_pulse <= write_data_masked[2];
                        end
                        REG_FB_RELEASE: begin
                            fb_release_pending_q <= 1'b1;
                            fb_release_slot_q <= wdata_hold_q[0];
                            fb_release_frame_q <= wdata_hold_q[FRAME_ID_WIDTH:1];
                        end
                        REG_SB_CLAIM: begin
                            sb_claim_pending_q <= 1'b1;
                            sb_claim_slot_q <= wdata_hold_q[0];
                            sb_claim_frame_q <= wdata_hold_q[FRAME_ID_WIDTH:1];
                        end
                        REG_SB_COMMIT: begin
                            sb_commit_pending_q <= 1'b1;
                            sb_commit_slot_q <= wdata_hold_q[0];
                            sb_commit_frame_q <= wdata_hold_q[FRAME_ID_WIDTH:1];
                        end
                        default: begin
                        end
                    endcase
                end
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (profiling_read_pending_q) begin
                // The profiling window is intentionally returned one cycle
                // after the address handshake.  This isolates the large,
                // read-only counter bank from the PS AXI interconnect path.
                s_axi_rdata <= profiling_read_data;
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
                profiling_read_pending_q <= 1'b0;
            end else if (s_axi_arvalid && s_axi_arready) begin
                if (s_axi_araddr[1:0] != 2'b00) begin
                    s_axi_rdata <= 32'd0;
                    s_axi_rresp <= 2'b10;
                    s_axi_rvalid <= 1'b1;
                end else if ((s_axi_araddr[11:0] >= REG_PROFILE_BASE) &&
                             (s_axi_araddr[11:0] <= REG_PROFILE_LAST)) begin
                    profiling_read_index_q <=
                        (s_axi_araddr[11:0] - REG_PROFILE_BASE) >> 2;
                    profiling_read_pending_q <= 1'b1;
                end else begin
                    s_axi_rresp <= 2'b00;
                    case (s_axi_araddr[11:0])
                        REG_COMMAND:
                            s_axi_rdata <= {26'd0, reset_quiesce_q, 3'd0,
                                            start_pending_q, 1'b0};
                        REG_CONFIG_SHADOW:
                            s_axi_rdata <= config_shadow_q;
                        REG_PARAM_BASE_SHADOW:
                            s_axi_rdata <= parameter_base_shadow_q;
                        REG_CONFIG_ACTIVE:
                            s_axi_rdata <= config_active_q;
                        REG_PARAM_BASE_ACTIVE:
                            s_axi_rdata <= parameter_base_active_q;
                        REG_STATUS:
                            s_axi_rdata <= {
                                19'd0,
                                control_error_sticky_q,
                                mailbox_irq,
                                spectrum_input_buffer_valid,
                                fb_input_buffer_valid,
                                accelerator_reset_active,
                                irq,
                                accelerator_sparse_mode,
                                accelerator_reset_required,
                                accelerator_error,
                                accelerator_done,
                                accelerator_busy,
                                start_pending_q,
                                accelerator_start_ready
                            };
                        REG_EXECUTION:
                            s_axi_rdata <= {
                                7'd0, controller_state, compute_owner,
                                cache_state, active_stage_id,
                                accelerator_state, accelerator_error_code
                            };
                        REG_FRAME_ID:
                            s_axi_rdata <= {{(32-FRAME_ID_WIDTH){1'b0}},
                                           accelerator_frame_id};
                        REG_STATE_CYCLES:
                            s_axi_rdata <= accelerator_state_cycles;
                        REG_IRQ_ENABLE:
                            s_axi_rdata <= irq_enable_q;
                        REG_IRQ_STATUS:
                            s_axi_rdata <= irq_status_q;
                        REG_FIRST_FAULT:
                            s_axi_rdata <= {7'd0, first_fault_valid_q,
                                           first_fault_source_q,
                                           first_fault_code_q, 8'd0};
                        REG_FIRST_FAULT_DETAIL:
                            s_axi_rdata <= first_fault_detail_q;
                        REG_FIRST_FAULT_FRAME:
                            s_axi_rdata <= {{(32-FRAME_ID_WIDTH){1'b0}},
                                           first_fault_frame_q};
                        REG_PACKET_BYTES_0:
                            s_axi_rdata <= USE_PL_LAYERNORM ?
                                {16'd512, 16'd512} :
                                {16'd512, 16'd64};
                        REG_PACKET_BYTES_1:
                            s_axi_rdata <= 32'd2048;
                        REG_IMAGE_VERSION:
                            s_axi_rdata <= IMAGE_VERSION;
                        REG_RESET_STATUS:
                            s_axi_rdata <= {reset_epoch_q, 12'd0,
                                           reset_quiesce_q,
                                           soft_reset_pending_q,
                                           accelerator_reset_active,
                                           software_reset_safe};
                        REG_PROFILE_CONTROL:
                            s_axi_rdata <= {31'd0, profiling_enable_q};
                        REG_PROFILE_STATUS:
                            s_axi_rdata <= {28'd0, profiling_snapshot_busy,
                                           profiling_frame_active,
                                           profiling_snapshot_valid,
                                           profiling_enable_q};
                        REG_FB_RELEASE:
                            s_axi_rdata <= {fb_release_pending_q, 14'd0,
                                           fb_release_frame_q,
                                           fb_release_slot_q};
                        REG_SB_CLAIM:
                            s_axi_rdata <= {sb_claim_pending_q, 14'd0,
                                           sb_claim_frame_q,
                                           sb_claim_slot_q};
                        REG_SB_COMMIT:
                            s_axi_rdata <= {sb_commit_pending_q, 14'd0,
                                           sb_commit_frame_q,
                                           sb_commit_slot_q};
                        REG_MAILBOX_STATES:
                            s_axi_rdata <= {24'd0, sb_slot_states,
                                           fb_slot_states};
                        REG_EXPECTED_FRAMES_0:
                            s_axi_rdata <= {expected_sb_frame_id,
                                           expected_fb_frame_id};
                        REG_EXPECTED_FRAMES_1:
                            s_axi_rdata <= {accelerator_frame_id,
                                           expected_consume_frame_id};
                        REG_FB_EVENT:
                            s_axi_rdata <= {fb_published_valid, 14'd0,
                                           fb_published_frame_id,
                                           fb_published_slot};
                        REG_SB_COMMIT_EVENT:
                            s_axi_rdata <= {sb_committed_valid, 14'd0,
                                           sb_committed_frame_id,
                                           sb_committed_slot};
                        REG_SB_RELEASE_EVENT:
                            s_axi_rdata <= {sb_released_valid, 14'd0,
                                           sb_released_frame_id,
                                           sb_released_slot};
                        REG_MAILBOX_ERROR_0:
                            s_axi_rdata <= {22'd0, mailbox_error_valid,
                                           mailbox_error_slot,
                                           mailbox_error_code};
                        REG_MAILBOX_ERROR_1:
                            s_axi_rdata <= {{(32-FRAME_ID_WIDTH){1'b0}},
                                           mailbox_error_frame_id};
                        REG_MAILBOX_HANDSHAKE:
                            s_axi_rdata <= {
                                24'd0,
                                ps_sb_commit_ready,
                                sb_commit_pending_q,
                                ps_sb_claim_ready,
                                sb_claim_pending_q,
                                ps_fb_release_ready,
                                fb_release_pending_q,
                                mailbox_irq,
                                accelerator_reset_active
                            };
                        REG_INPUT_BUFFER_STATUS:
                            s_axi_rdata <= {30'd0,
                                           spectrum_input_buffer_valid,
                                           fb_input_buffer_valid};
                        REG_INPUT_FRAME_IDS:
                            s_axi_rdata <= {spectrum_input_buffer_frame_id,
                                           fb_input_buffer_frame_id};
                        REG_WEIGHT_REQUESTS:
                            s_axi_rdata <= weight_request_count;
                        REG_DENSE_REQUESTS:
                            s_axi_rdata <= dense_weight_request_count;
                        REG_SPARSE_REQUESTS:
                            s_axi_rdata <= sparse_weight_request_count;
                        REG_STAGE_ACTUAL_BYTES:
                            s_axi_rdata <= sparse_stage_actual_bytes;
                        REG_STAGE_SAVED_BYTES:
                            s_axi_rdata <= sparse_stage_saved_bytes;
                        REG_STAGE_BURSTS:
                            s_axi_rdata <= sparse_stage_ar_burst_count;
                        REG_STAGE_LOAD_CYCLES:
                            s_axi_rdata <= sparse_stage_load_cycles;
                        REG_STAGE_DIAG:
                            s_axi_rdata <= {24'd0,
                                           sparse_stage_diag_fallback_full,
                                           sparse_stage_diag_enabled,
                                           sparse_stage_diag_stage_id,
                                           sparse_stage_diag_success,
                                           sparse_stage_diag_valid};
                        REG_CONTROL_ERROR:
                            s_axi_rdata <= {23'd0,
                                           control_error_sticky_q,
                                           control_error_code_q};
                        default: begin
                            s_axi_rdata <= 32'd0;
                            s_axi_rresp <= 2'b11;
                        end
                    endcase
                    s_axi_rvalid <= 1'b1;
                end
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
