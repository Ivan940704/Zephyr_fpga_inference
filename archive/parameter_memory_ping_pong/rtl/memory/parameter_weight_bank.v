`timescale 1ns/1ps

// One AXI-independent 128 KiB physical weight bank.
//
// Storage geometry:
//   * 8192 entries x 128 bits.
//   * Two independently inferred 8192 x 64-bit planes.
//   * Loader beat 2*N writes low_mem[N]  -> response bits [63:0].
//   * Loader beat 2*N+1 writes high_mem[N] -> response bits [127:64].
//
// This primitive owns no AXI master, directory, matrix binding table,
// membership list, second bank, parameter RAM, LUT, scratch, or scheduler.
// force_error is the owner's final bank-close transaction, not raw abort.
module parameter_weight_bank (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         force_error_valid,
    output wire         force_error_ready,
    input  wire [7:0]   force_error_code,

    output wire [2:0]   bank_state,
    output wire [31:0]  bank_generation,
    output wire         bank_generation_initialized,
    output wire         bank_authority_valid,
    output wire         bank_lease_owner_valid,
    output wire [31:0]  bank_lease_owner_ticket,
    output wire         local_mgmt_busy,
    output wire [1:0]   read_outstanding,
    output wire [1:0]   write_outstanding,
    output wire         read_idle,
    output wire         write_idle,
    output wire         local_quiescent,
    output wire         drain_complete,
    output wire         local_retire_eligible,
    output wire         local_error_valid,
    output wire [7:0]   local_error_code,
    output wire [1:0]   local_error_source,
    output wire [31:0]  local_error_generation,
    output wire [31:0]  local_error_lease_owner_ticket,
    output wire [15:0]  local_error_tag,
    output wire [13:0]  local_error_address,
    output wire         reset_required,

    input  wire         mgmt_req_valid,
    output wire         mgmt_req_ready,
    input  wire [3:0]   mgmt_req_opcode,
    input  wire [1:0]   mgmt_req_drain_target,
    input  wire [31:0]  mgmt_req_generation,
    input  wire [31:0]  mgmt_req_lease_owner_ticket,
    input  wire         mgmt_req_external_safe,
    input  wire [15:0]  mgmt_req_tag,
    output wire         mgmt_rsp_valid,
    input  wire         mgmt_rsp_ready,
    output wire [3:0]   mgmt_rsp_opcode,
    output wire [2:0]   mgmt_rsp_state,
    output wire [31:0]  mgmt_rsp_generation,
    output wire [31:0]  mgmt_rsp_lease_owner_ticket,
    output wire [15:0]  mgmt_rsp_tag,
    output wire [7:0]   mgmt_rsp_status,

    input  wire         load_req_valid,
    output wire         load_req_ready,
    input  wire [13:0]  load_req_beat_addr,
    input  wire [63:0]  load_req_data,
    input  wire [31:0]  load_req_generation,
    input  wire [31:0]  load_req_lease_owner_ticket,
    input  wire [15:0]  load_req_tag,
    output wire         load_rsp_valid,
    input  wire         load_rsp_ready,
    output wire [13:0]  load_rsp_beat_addr,
    output wire [31:0]  load_rsp_generation,
    output wire [31:0]  load_rsp_lease_owner_ticket,
    output wire [15:0]  load_rsp_tag,
    output wire [7:0]   load_rsp_status,

    input  wire         rd_req_valid,
    output wire         rd_req_ready,
    input  wire [12:0]  rd_req_addr,
    input  wire [31:0]  rd_req_generation,
    input  wire [31:0]  rd_req_lease_owner_ticket,
    input  wire [15:0]  rd_req_tag,
    output wire         rd_rsp_valid,
    input  wire         rd_rsp_ready,
    output wire [127:0] rd_rsp_data,
    output wire [12:0]  rd_rsp_addr,
    output wire [31:0]  rd_rsp_generation,
    output wire [31:0]  rd_rsp_lease_owner_ticket,
    output wire [15:0]  rd_rsp_tag,
    output wire [7:0]   rd_rsp_status
);

    localparam [2:0] ST_INVALID  = 3'd0;
    localparam [2:0] ST_LOADING  = 3'd1;
    localparam [2:0] ST_READY    = 3'd2;
    localparam [2:0] ST_ACTIVE   = 3'd3;
    localparam [2:0] ST_DRAINING = 3'd4;
    localparam [2:0] ST_RETAINED = 3'd5;
    localparam [2:0] ST_ERROR    = 3'd6;

    localparam [3:0] MGMT_CLAIM          = 4'h0;
    localparam [3:0] MGMT_PUBLISH_READY  = 4'h1;
    localparam [3:0] MGMT_ACTIVATE       = 4'h2;
    localparam [3:0] MGMT_BEGIN_DRAIN    = 4'h3;
    localparam [3:0] MGMT_FINISH_DRAIN   = 4'h4;
    localparam [3:0] MGMT_EARLY_RETIRE   = 4'h5;
    localparam [3:0] MGMT_EVICT_RETAINED = 4'h6;
    localparam [3:0] MGMT_CLEAR_ERROR    = 4'h7;

    localparam [1:0] DRAIN_INVALID  = 2'b00;
    localparam [1:0] DRAIN_RETAINED = 2'b01;
    localparam [1:0] DRAIN_ERROR    = 2'b10;

    localparam [7:0] STATUS_OK                   = 8'h00;
    localparam [7:0] STATUS_ERR_BAD_OPCODE       = 8'h01;
    localparam [7:0] STATUS_ERR_WRONG_STATE      = 8'h02;
    localparam [7:0] STATUS_ERR_STALE_GENERATION = 8'h03;
    localparam [7:0] STATUS_ERR_OWNER_MISMATCH   = 8'h04;
    localparam [7:0] STATUS_ERR_NOT_QUIESCENT    = 8'h05;
    localparam [7:0] STATUS_ERR_EXTERNAL_UNSAFE  = 8'h06;
    localparam [7:0] STATUS_ERR_GENERATION_EXHAUSTED = 8'h07;
    localparam [7:0] STATUS_ERR_BAD_DRAIN_TARGET = 8'h08;
    localparam [7:0] STATUS_ERR_ABORTED          = 8'h09;
    localparam [7:0] STATUS_ERR_LOCAL_PROTOCOL   = 8'h0a;
    localparam [7:0] STATUS_ERR_INTERNAL_STATE   = 8'h0b;

    localparam [1:0] ERROR_SOURCE_LOADER   = 2'b00;
    localparam [1:0] ERROR_SOURCE_READ     = 2'b01;
    localparam [1:0] ERROR_SOURCE_INTERNAL = 2'b10;
    localparam [1:0] ERROR_SOURCE_FORCE    = 2'b11;

    reg [2:0]  bank_state_q;
    reg [1:0]  drain_target_q;
    reg [31:0] bank_generation_q;
    reg        bank_generation_initialized_q;
    reg        bank_authority_valid_q;
    reg        bank_lease_owner_valid_q;
    reg [31:0] bank_lease_owner_ticket_q;

    reg        local_error_valid_q;
    reg [7:0]  local_error_code_q;
    reg [1:0]  local_error_source_q;
    reg [31:0] local_error_generation_q;
    reg [31:0] local_error_lease_owner_ticket_q;
    reg [15:0] local_error_tag_q;
    reg [13:0] local_error_address_q;
    reg        reset_required_q;
    reg [7:0]  reset_reason_q;

    reg        mgmt_rsp_valid_q;
    reg [3:0]  mgmt_rsp_opcode_q;
    reg [2:0]  mgmt_rsp_state_q;
    reg [31:0] mgmt_rsp_generation_q;
    reg [31:0] mgmt_rsp_lease_owner_ticket_q;
    reg [15:0] mgmt_rsp_tag_q;
    reg [7:0]  mgmt_rsp_status_q;

    // The RAM arrays intentionally have no reset branch.
    reg [63:0] low_mem  [0:8191];
    reg [63:0] high_mem [0:8191];

    // Fixed synchronous BRAM output (newest response position).
    reg [63:0] rd_low_q;
    reg [63:0] rd_high_q;
    reg        rd_primary_valid_q;
    reg [12:0] rd_primary_addr_q;
    reg [31:0] rd_primary_generation_q;
    reg [31:0] rd_primary_lease_owner_ticket_q;
    reg [15:0] rd_primary_tag_q;
    reg [7:0]  rd_primary_status_q;

    // Older read response spilled from the fixed BRAM output.
    reg         rd_skid_valid_q;
    reg [127:0] rd_skid_data_q;
    reg [12:0]  rd_skid_addr_q;
    reg [31:0]  rd_skid_generation_q;
    reg [31:0]  rd_skid_lease_owner_ticket_q;
    reg [15:0]  rd_skid_tag_q;
    reg [7:0]   rd_skid_status_q;

    // Registered loader execution position.
    reg        wr_exec_valid_q;
    reg        wr_exec_committed_q;
    reg        wr_exec_authorized_q;
    reg [13:0] wr_exec_beat_addr_q;
    reg [63:0] wr_exec_data_q;
    reg [31:0] wr_exec_generation_q;
    reg [31:0] wr_exec_lease_owner_ticket_q;
    reg [15:0] wr_exec_tag_q;
    reg [7:0]  wr_exec_status_q;

    // Visible loader response position.
    reg        wr_rsp_valid_q;
    reg [13:0] wr_rsp_beat_addr_q;
    reg [31:0] wr_rsp_generation_q;
    reg [31:0] wr_rsp_lease_owner_ticket_q;
    reg [15:0] wr_rsp_tag_q;
    reg [7:0]  wr_rsp_status_q;

    reg        load_req_ready_q;
    reg        rd_req_ready_q;
    reg [7:0]  load_accept_status;
    reg        load_accept_authorized;
    reg [7:0]  rd_accept_status;
    reg        rd_accept_authorized;
    reg [7:0]  mgmt_status_d;
    reg [2:0]  mgmt_state_d;
    reg [31:0] mgmt_generation_d;

    wire force_error_fire;
    wire mgmt_req_fire;
    wire load_req_fire;
    wire rd_req_fire;
    wire load_rsp_fire;
    wire rd_rsp_fire;
    wire rd_primary_pop;
    wire rd_skid_pop;
    wire wr_rsp_can_take;
    wire load_slot_available;
    wire read_slot_available;
    wire data_base;
    wire internal_slot_fault;
    wire internal_state_fault;
    wire local_integrity_fault_pending;
    wire load_fault_fire;
    wire rd_fault_fire;
    wire data_fault_fire;
    wire [7:0] data_fault_code;
    wire [7:0] effective_force_code;
    wire wr_commit_pending;
    wire wr_commit_low;
    wire wr_commit_high;
    reg  [7:0] wr_commit_status;
    wire [127:0] rd_primary_data;
    wire current_identity_match;
    wire error_scope_matches_current;
    wire drain_identity_match;

    assign bank_state = bank_state_q;
    assign bank_generation = bank_generation_q;
    assign bank_generation_initialized = bank_generation_initialized_q;
    assign bank_authority_valid = bank_authority_valid_q;
    assign bank_lease_owner_valid = bank_lease_owner_valid_q;
    assign bank_lease_owner_ticket = bank_lease_owner_ticket_q;

    assign local_error_valid = local_error_valid_q;
    assign local_error_code = local_error_code_q;
    assign local_error_source = local_error_source_q;
    assign local_error_generation = local_error_generation_q;
    assign local_error_lease_owner_ticket =
        local_error_lease_owner_ticket_q;
    assign local_error_tag = local_error_tag_q;
    assign local_error_address = local_error_address_q;
    assign reset_required = reset_required_q;

    assign mgmt_rsp_valid = mgmt_rsp_valid_q;
    assign mgmt_rsp_opcode = mgmt_rsp_opcode_q;
    assign mgmt_rsp_state = mgmt_rsp_state_q;
    assign mgmt_rsp_generation = mgmt_rsp_generation_q;
    assign mgmt_rsp_lease_owner_ticket = mgmt_rsp_lease_owner_ticket_q;
    assign mgmt_rsp_tag = mgmt_rsp_tag_q;
    assign mgmt_rsp_status = mgmt_rsp_status_q;

    assign load_rsp_valid = wr_rsp_valid_q;
    assign load_rsp_beat_addr = wr_rsp_beat_addr_q;
    assign load_rsp_generation = wr_rsp_generation_q;
    assign load_rsp_lease_owner_ticket = wr_rsp_lease_owner_ticket_q;
    assign load_rsp_tag = wr_rsp_tag_q;
    assign load_rsp_status = wr_rsp_status_q;

    assign rd_primary_data = (rd_primary_status_q == STATUS_OK) ?
                             {rd_high_q, rd_low_q} : 128'd0;
    assign rd_rsp_valid = rd_skid_valid_q || rd_primary_valid_q;
    assign rd_rsp_data = rd_skid_valid_q ? rd_skid_data_q :
                         (rd_primary_valid_q ? rd_primary_data : 128'd0);
    assign rd_rsp_addr = rd_skid_valid_q ? rd_skid_addr_q :
                         (rd_primary_valid_q ? rd_primary_addr_q : 13'd0);
    assign rd_rsp_generation = rd_skid_valid_q ? rd_skid_generation_q :
        (rd_primary_valid_q ? rd_primary_generation_q : 32'd0);
    assign rd_rsp_lease_owner_ticket = rd_skid_valid_q ?
        rd_skid_lease_owner_ticket_q :
        (rd_primary_valid_q ? rd_primary_lease_owner_ticket_q : 32'd0);
    assign rd_rsp_tag = rd_skid_valid_q ? rd_skid_tag_q :
                        (rd_primary_valid_q ? rd_primary_tag_q : 16'd0);
    assign rd_rsp_status = rd_skid_valid_q ? rd_skid_status_q :
                           (rd_primary_valid_q ? rd_primary_status_q :
                            STATUS_OK);

    assign read_outstanding = {1'b0, rd_primary_valid_q} +
                              {1'b0, rd_skid_valid_q};
    assign write_outstanding = {1'b0, wr_exec_valid_q} +
                               {1'b0, wr_rsp_valid_q};
    assign read_idle = !rd_primary_valid_q && !rd_skid_valid_q;
    assign write_idle = !wr_exec_valid_q && !wr_rsp_valid_q;
    assign local_mgmt_busy = mgmt_rsp_valid_q;
    assign local_quiescent = read_idle && write_idle &&
                             !mgmt_rsp_valid_q &&
                             !local_integrity_fault_pending;
    assign drain_complete = (bank_state_q == ST_DRAINING) &&
                            local_quiescent;
    assign local_retire_eligible = (bank_state_q == ST_ACTIVE) &&
        bank_authority_valid_q && bank_lease_owner_valid_q &&
        local_quiescent && !local_error_valid_q && !reset_required_q;

    assign force_error_ready = rst_n;
    assign force_error_fire = force_error_valid && force_error_ready;
    assign effective_force_code =
        (force_error_code == STATUS_OK) ? STATUS_ERR_LOCAL_PROTOCOL :
                                          force_error_code;

    assign internal_state_fault = (bank_state_q == 3'd7);
    assign internal_slot_fault =
        (rd_skid_valid_q && !rd_primary_valid_q) ||
        (wr_exec_committed_q && !wr_exec_valid_q);
    assign local_integrity_fault_pending = internal_state_fault ||
                                           internal_slot_fault;

    assign mgmt_req_ready = rst_n && !local_integrity_fault_pending &&
                            !force_error_valid && !mgmt_rsp_valid_q;
    assign mgmt_req_fire = mgmt_req_valid && mgmt_req_ready;

    assign load_rsp_fire = wr_rsp_valid_q && load_rsp_ready;
    assign wr_rsp_can_take = !wr_rsp_valid_q || load_rsp_fire;
    assign load_slot_available = !wr_exec_valid_q || wr_rsp_can_take;

    assign rd_rsp_fire = rd_rsp_valid && rd_rsp_ready;
    assign rd_skid_pop = rd_skid_valid_q && rd_rsp_ready;
    assign rd_primary_pop = !rd_skid_valid_q && rd_primary_valid_q &&
                            rd_rsp_ready;
    assign read_slot_available = !rd_primary_valid_q || !rd_skid_valid_q ||
                                 rd_rsp_fire;

    assign data_base = rst_n && !local_integrity_fault_pending &&
                       !force_error_valid && !mgmt_req_valid &&
                       !mgmt_rsp_valid_q;

    always @* begin
        load_req_ready_q = 1'b0;
        rd_req_ready_q = 1'b0;
        if (data_base) begin
            case (bank_state_q)
                ST_LOADING: begin
                    load_req_ready_q = load_slot_available;
                    rd_req_ready_q = !load_req_valid &&
                                     read_slot_available;
                end
                ST_ACTIVE: begin
                    rd_req_ready_q = read_slot_available;
                    load_req_ready_q = !rd_req_valid &&
                                       load_slot_available;
                end
                ST_READY: begin
                    load_req_ready_q = load_slot_available;
                    rd_req_ready_q = !load_req_valid &&
                                     read_slot_available;
                end
                default: begin
                    load_req_ready_q = 1'b0;
                    rd_req_ready_q = 1'b0;
                end
            endcase
        end
    end

    assign load_req_ready = load_req_ready_q;
    assign rd_req_ready = rd_req_ready_q;
    assign load_req_fire = load_req_valid && load_req_ready_q;
    assign rd_req_fire = rd_req_valid && rd_req_ready_q;

    // Physical data request checks.  Wrong state takes priority over stale
    // generation, followed by owner mismatch.
    always @* begin
        load_accept_status = STATUS_OK;
        load_accept_authorized = 1'b0;
        if (bank_state_q != ST_LOADING) begin
            load_accept_status = STATUS_ERR_WRONG_STATE;
        end else if (!bank_authority_valid_q ||
                     (load_req_generation != bank_generation_q)) begin
            load_accept_status = STATUS_ERR_STALE_GENERATION;
        end else if (!bank_lease_owner_valid_q ||
                     (load_req_lease_owner_ticket !=
                      bank_lease_owner_ticket_q)) begin
            load_accept_status = STATUS_ERR_OWNER_MISMATCH;
        end else begin
            load_accept_status = STATUS_OK;
            load_accept_authorized = 1'b1;
        end
    end

    always @* begin
        rd_accept_status = STATUS_OK;
        rd_accept_authorized = 1'b0;
        if (bank_state_q != ST_ACTIVE) begin
            rd_accept_status = STATUS_ERR_WRONG_STATE;
        end else if (!bank_authority_valid_q ||
                     (rd_req_generation != bank_generation_q)) begin
            rd_accept_status = STATUS_ERR_STALE_GENERATION;
        end else if (!bank_lease_owner_valid_q ||
                     (rd_req_lease_owner_ticket !=
                      bank_lease_owner_ticket_q)) begin
            rd_accept_status = STATUS_ERR_OWNER_MISMATCH;
        end else begin
            rd_accept_status = STATUS_OK;
            rd_accept_authorized = 1'b1;
        end
    end

    assign load_fault_fire = load_req_fire &&
                             (load_accept_status != STATUS_OK);
    assign rd_fault_fire = rd_req_fire &&
                           (rd_accept_status != STATUS_OK);
    assign data_fault_fire = load_fault_fire || rd_fault_fire;
    assign data_fault_code = load_fault_fire ? load_accept_status :
                                             rd_accept_status;

    assign current_identity_match = bank_authority_valid_q &&
        bank_lease_owner_valid_q &&
        (mgmt_req_generation == bank_generation_q) &&
        (mgmt_req_lease_owner_ticket == bank_lease_owner_ticket_q);
    assign error_scope_matches_current = local_error_valid_q &&
        (local_error_generation_q == bank_generation_q) &&
        (local_error_lease_owner_ticket_q ==
         bank_lease_owner_ticket_q);
    assign drain_identity_match =
        (bank_authority_valid_q && bank_lease_owner_valid_q &&
         (mgmt_req_generation == bank_generation_q) &&
         (mgmt_req_lease_owner_ticket == bank_lease_owner_ticket_q)) ||
        ((!bank_authority_valid_q || !bank_lease_owner_valid_q) &&
         local_error_valid_q &&
         (mgmt_req_generation == local_error_generation_q) &&
         (mgmt_req_lease_owner_ticket ==
          local_error_lease_owner_ticket_q));

    // Management commands always receive one caller-local response.  Only a
    // command with STATUS_OK mutates lifecycle/authority state.
    always @* begin
        mgmt_status_d = STATUS_OK;
        mgmt_state_d = bank_state_q;
        // Rejections report the bank's scoped generation, not an offender's
        // stale request value.  A successful CLAIM overrides this with the
        // newly allocated generation below.
        mgmt_generation_d = bank_generation_q;

        if (mgmt_req_opcode > MGMT_CLEAR_ERROR) begin
            mgmt_status_d = STATUS_ERR_BAD_OPCODE;
        end else if (reset_required_q) begin
            mgmt_status_d = reset_reason_q;
        end else begin
            case (mgmt_req_opcode)
                MGMT_CLAIM: begin
                    if ((bank_state_q != ST_INVALID) &&
                        (bank_state_q != ST_RETAINED))
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (mgmt_req_generation != bank_generation_q)
                        mgmt_status_d = STATUS_ERR_STALE_GENERATION;
                    else if (mgmt_req_lease_owner_ticket == 32'd0)
                        mgmt_status_d = STATUS_ERR_OWNER_MISMATCH;
                    else if (!mgmt_req_external_safe)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!local_quiescent)
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else if (local_error_valid_q)
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    else if (bank_generation_q == 32'hffff_ffff)
                        mgmt_status_d =
                            STATUS_ERR_GENERATION_EXHAUSTED;
                    else begin
                        mgmt_state_d = ST_LOADING;
                        mgmt_generation_d = bank_generation_q + 1'b1;
                    end
                end

                MGMT_PUBLISH_READY: begin
                    if (bank_state_q != ST_LOADING)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!current_identity_match)
                        mgmt_status_d =
                            (mgmt_req_generation != bank_generation_q) ?
                            STATUS_ERR_STALE_GENERATION :
                            STATUS_ERR_OWNER_MISMATCH;
                    else if (!mgmt_req_external_safe)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!local_quiescent)
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else if (local_error_valid_q)
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    else
                        mgmt_state_d = ST_READY;
                end

                MGMT_ACTIVATE: begin
                    if (bank_state_q != ST_READY)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!current_identity_match)
                        mgmt_status_d =
                            (mgmt_req_generation != bank_generation_q) ?
                            STATUS_ERR_STALE_GENERATION :
                            STATUS_ERR_OWNER_MISMATCH;
                    else if (!mgmt_req_external_safe)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!local_quiescent)
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else if (local_error_valid_q)
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    else
                        mgmt_state_d = ST_ACTIVE;
                end

                MGMT_BEGIN_DRAIN: begin
                    if ((bank_state_q != ST_LOADING) &&
                        (bank_state_q != ST_READY) &&
                        (bank_state_q != ST_ACTIVE)) begin
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    end else if (!current_identity_match) begin
                        mgmt_status_d =
                            (mgmt_req_generation != bank_generation_q) ?
                            STATUS_ERR_STALE_GENERATION :
                            STATUS_ERR_OWNER_MISMATCH;
                    end else if (!mgmt_req_external_safe) begin
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    end else if (mgmt_req_drain_target == 2'b11) begin
                        mgmt_status_d = STATUS_ERR_BAD_DRAIN_TARGET;
                    end else if ((bank_state_q == ST_LOADING) ||
                                 (bank_state_q == ST_READY)) begin
                        if ((mgmt_req_drain_target != DRAIN_ERROR) ||
                            !error_scope_matches_current)
                            mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                        else
                            mgmt_state_d = ST_DRAINING;
                    end else if (mgmt_req_drain_target == DRAIN_ERROR) begin
                        if (!error_scope_matches_current)
                            mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                        else
                            mgmt_state_d = ST_DRAINING;
                    end else if (local_error_valid_q) begin
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    end else begin
                        mgmt_state_d = ST_DRAINING;
                    end
                end

                MGMT_FINISH_DRAIN: begin
                    if (bank_state_q != ST_DRAINING)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!drain_identity_match)
                        mgmt_status_d =
                            (mgmt_req_generation != bank_generation_q) ?
                            STATUS_ERR_STALE_GENERATION :
                            STATUS_ERR_OWNER_MISMATCH;
                    else if (!mgmt_req_external_safe)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!drain_complete)
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else if (drain_target_q == 2'b11)
                        mgmt_status_d = STATUS_ERR_BAD_DRAIN_TARGET;
                    else if ((drain_target_q == DRAIN_ERROR) &&
                             !local_error_valid_q)
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    else
                        case (drain_target_q)
                            DRAIN_INVALID:  mgmt_state_d = ST_INVALID;
                            DRAIN_RETAINED: mgmt_state_d = ST_RETAINED;
                            default:        mgmt_state_d = ST_ERROR;
                        endcase
                end

                MGMT_EARLY_RETIRE: begin
                    if (bank_state_q != ST_ACTIVE)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!current_identity_match)
                        mgmt_status_d =
                            (mgmt_req_generation != bank_generation_q) ?
                            STATUS_ERR_STALE_GENERATION :
                            STATUS_ERR_OWNER_MISMATCH;
                    else if (!mgmt_req_external_safe)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!local_retire_eligible)
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else
                        mgmt_state_d = ST_INVALID;
                end

                MGMT_EVICT_RETAINED: begin
                    if (bank_state_q != ST_RETAINED)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (mgmt_req_generation != bank_generation_q)
                        mgmt_status_d = STATUS_ERR_STALE_GENERATION;
                    else if (mgmt_req_lease_owner_ticket != 32'd0)
                        mgmt_status_d = STATUS_ERR_OWNER_MISMATCH;
                    else if (!mgmt_req_external_safe)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!local_quiescent)
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else
                        mgmt_state_d = ST_INVALID;
                end

                MGMT_CLEAR_ERROR: begin
                    if (bank_state_q != ST_ERROR)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!local_error_valid_q)
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    else if (mgmt_req_generation !=
                             local_error_generation_q)
                        mgmt_status_d = STATUS_ERR_STALE_GENERATION;
                    else if (mgmt_req_lease_owner_ticket !=
                             local_error_lease_owner_ticket_q)
                        mgmt_status_d = STATUS_ERR_OWNER_MISMATCH;
                    else if (!mgmt_req_external_safe)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!local_quiescent)
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else
                        mgmt_state_d = ST_INVALID;
                end

                default: mgmt_status_d = STATUS_ERR_BAD_OPCODE;
            endcase
        end
    end

    // A pending write always completes its acceptance-time write decision.
    // Only its not-yet-materialized response status can be changed by a
    // same-edge local fault or final close.
    assign wr_commit_pending = rst_n && wr_exec_valid_q &&
                               !wr_exec_committed_q;
    assign wr_commit_low = wr_commit_pending && wr_exec_authorized_q &&
                           !wr_exec_beat_addr_q[0];
    assign wr_commit_high = wr_commit_pending && wr_exec_authorized_q &&
                            wr_exec_beat_addr_q[0];

    always @* begin
        if (wr_exec_status_q != STATUS_OK)
            wr_commit_status = wr_exec_status_q;
        else if (local_integrity_fault_pending &&
                 (!force_error_fire ||
                  (force_error_code == STATUS_OK) ||
                  (force_error_code == STATUS_ERR_ABORTED)))
            wr_commit_status = STATUS_ERR_INTERNAL_STATE;
        else if (force_error_fire)
            wr_commit_status = effective_force_code;
        else if (data_fault_fire)
            wr_commit_status = data_fault_code;
        else
            wr_commit_status = STATUS_OK;
    end

    // Each plane is a registered-write/synchronous-read simple dual-port RAM.
    // The arrays and BRAM output registers are deliberately not reset.
    always @(posedge clk) begin
        if (wr_commit_low)
            low_mem[wr_exec_beat_addr_q[13:1]] <= wr_exec_data_q;
        if (rd_req_fire && rd_accept_authorized)
            rd_low_q <= low_mem[rd_req_addr];
    end

    always @(posedge clk) begin
        if (wr_commit_high)
            high_mem[wr_exec_beat_addr_q[13:1]] <= wr_exec_data_q;
        if (rd_req_fire && rd_accept_authorized)
            rd_high_q <= high_mem[rd_req_addr];
    end

    // Read elastic positions.  The primary metadata is paired with the fixed
    // BRAM output.  When a new read would overwrite a surviving primary item,
    // the old complete response moves into the older skid position first.
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_primary_valid_q <= 1'b0;
            rd_primary_addr_q <= 13'd0;
            rd_primary_generation_q <= 32'd0;
            rd_primary_lease_owner_ticket_q <= 32'd0;
            rd_primary_tag_q <= 16'd0;
            rd_primary_status_q <= STATUS_OK;
            rd_skid_valid_q <= 1'b0;
            rd_skid_data_q <= 128'd0;
            rd_skid_addr_q <= 13'd0;
            rd_skid_generation_q <= 32'd0;
            rd_skid_lease_owner_ticket_q <= 32'd0;
            rd_skid_tag_q <= 16'd0;
            rd_skid_status_q <= STATUS_OK;
        end else begin
            if (rd_skid_pop)
                rd_skid_valid_q <= 1'b0;
            else if (rd_primary_pop)
                rd_primary_valid_q <= 1'b0;

            if (rd_req_fire) begin
                if (rd_primary_valid_q && !rd_primary_pop) begin
                    rd_skid_valid_q <= 1'b1;
                    rd_skid_data_q <= rd_primary_data;
                    rd_skid_addr_q <= rd_primary_addr_q;
                    rd_skid_generation_q <= rd_primary_generation_q;
                    rd_skid_lease_owner_ticket_q <=
                        rd_primary_lease_owner_ticket_q;
                    rd_skid_tag_q <= rd_primary_tag_q;
                    rd_skid_status_q <= rd_primary_status_q;
                end

                rd_primary_valid_q <= 1'b1;
                rd_primary_addr_q <= rd_req_addr;
                rd_primary_generation_q <= rd_req_generation;
                rd_primary_lease_owner_ticket_q <=
                    rd_req_lease_owner_ticket;
                rd_primary_tag_q <= rd_req_tag;
                rd_primary_status_q <= rd_accept_status;
            end
        end
    end

    // Loader execution and response positions.  A write enable can pulse only
    // while wr_exec is pending; a committed item can never write again.
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_exec_valid_q <= 1'b0;
            wr_exec_committed_q <= 1'b0;
            wr_exec_authorized_q <= 1'b0;
            wr_exec_beat_addr_q <= 14'd0;
            wr_exec_data_q <= 64'd0;
            wr_exec_generation_q <= 32'd0;
            wr_exec_lease_owner_ticket_q <= 32'd0;
            wr_exec_tag_q <= 16'd0;
            wr_exec_status_q <= STATUS_OK;
            wr_rsp_valid_q <= 1'b0;
            wr_rsp_beat_addr_q <= 14'd0;
            wr_rsp_generation_q <= 32'd0;
            wr_rsp_lease_owner_ticket_q <= 32'd0;
            wr_rsp_tag_q <= 16'd0;
            wr_rsp_status_q <= STATUS_OK;
        end else begin
            if (load_rsp_fire)
                wr_rsp_valid_q <= 1'b0;

            if (wr_exec_valid_q && wr_rsp_can_take) begin
                wr_rsp_valid_q <= 1'b1;
                wr_rsp_beat_addr_q <= wr_exec_beat_addr_q;
                wr_rsp_generation_q <= wr_exec_generation_q;
                wr_rsp_lease_owner_ticket_q <=
                    wr_exec_lease_owner_ticket_q;
                wr_rsp_tag_q <= wr_exec_tag_q;
                wr_rsp_status_q <= wr_exec_committed_q ?
                                   wr_exec_status_q : wr_commit_status;
                wr_exec_valid_q <= 1'b0;
                wr_exec_committed_q <= 1'b0;
                wr_exec_authorized_q <= 1'b0;
            end else if (wr_exec_valid_q && !wr_exec_committed_q) begin
                wr_exec_committed_q <= 1'b1;
                wr_exec_status_q <= wr_commit_status;
            end

            if (load_req_fire) begin
                wr_exec_valid_q <= 1'b1;
                wr_exec_committed_q <= 1'b0;
                wr_exec_authorized_q <= load_accept_authorized;
                wr_exec_beat_addr_q <= load_req_beat_addr;
                wr_exec_data_q <= load_req_data;
                wr_exec_generation_q <= load_req_generation;
                wr_exec_lease_owner_ticket_q <=
                    load_req_lease_owner_ticket;
                wr_exec_tag_q <= load_req_tag;
                wr_exec_status_q <= load_accept_status;
            end
        end
    end

    // Lifecycle, owner authority, management response, and sticky errors.
    // Pipeline blocks above continue retiring independently during DRAINING.
    always @(posedge clk) begin
        if (!rst_n) begin
            bank_state_q <= ST_INVALID;
            drain_target_q <= DRAIN_INVALID;
            bank_generation_q <= 32'd0;
            bank_generation_initialized_q <= 1'b0;
            bank_authority_valid_q <= 1'b0;
            bank_lease_owner_valid_q <= 1'b0;
            bank_lease_owner_ticket_q <= 32'd0;

            local_error_valid_q <= 1'b0;
            local_error_code_q <= STATUS_OK;
            local_error_source_q <= 2'd0;
            local_error_generation_q <= 32'd0;
            local_error_lease_owner_ticket_q <= 32'd0;
            local_error_tag_q <= 16'd0;
            local_error_address_q <= 14'd0;
            reset_required_q <= 1'b0;
            reset_reason_q <= STATUS_OK;

            mgmt_rsp_valid_q <= 1'b0;
            mgmt_rsp_opcode_q <= 4'd0;
            mgmt_rsp_state_q <= ST_INVALID;
            mgmt_rsp_generation_q <= 32'd0;
            mgmt_rsp_lease_owner_ticket_q <= 32'd0;
            mgmt_rsp_tag_q <= 16'd0;
            mgmt_rsp_status_q <= STATUS_OK;
        end else begin
            if (mgmt_rsp_valid_q && mgmt_rsp_ready)
                mgmt_rsp_valid_q <= 1'b0;

            // An impossible local encoding/slot ownership state wins over an
            // external final-close accepted on the same edge.
            if (local_integrity_fault_pending) begin
                reset_required_q <= 1'b1;
                reset_reason_q <= STATUS_ERR_INTERNAL_STATE;
                drain_target_q <= DRAIN_ERROR;
                if (!local_error_valid_q) begin
                    local_error_valid_q <= 1'b1;
                    local_error_code_q <= STATUS_ERR_INTERNAL_STATE;
                    local_error_source_q <= ERROR_SOURCE_INTERNAL;
                    local_error_generation_q <= bank_generation_q;
                    local_error_lease_owner_ticket_q <=
                        bank_lease_owner_valid_q ?
                        bank_lease_owner_ticket_q : 32'd0;
                    local_error_tag_q <= 16'd0;
                    local_error_address_q <= 14'd0;
                end
                if (internal_state_fault ||
                    (bank_state_q == ST_INVALID) ||
                    (bank_state_q == ST_RETAINED) ||
                    (bank_state_q == ST_ERROR)) begin
                    bank_state_q <= ST_ERROR;
                    bank_authority_valid_q <= 1'b0;
                    bank_lease_owner_valid_q <= 1'b0;
                    bank_lease_owner_ticket_q <= 32'd0;
                end else begin
                    bank_state_q <= ST_DRAINING;
                end
            end else if (force_error_fire) begin
                // INVALID has no live/retained resource to close.  Even an
                // illegal zero code is a no-op here rather than an uncleareable
                // sticky error without an ERROR scope.
                if (bank_state_q == ST_INVALID) begin
                    bank_state_q <= ST_INVALID;
                end else if (bank_state_q == ST_ERROR) begin
                    bank_state_q <= ST_ERROR;
                end else begin
                    drain_target_q <= DRAIN_ERROR;
                    bank_state_q <= ST_DRAINING;
                    if (!local_error_valid_q) begin
                        local_error_valid_q <= 1'b1;
                        local_error_code_q <= effective_force_code;
                        local_error_source_q <= ERROR_SOURCE_FORCE;
                        local_error_generation_q <= bank_generation_q;
                        local_error_lease_owner_ticket_q <=
                            bank_lease_owner_valid_q ?
                            bank_lease_owner_ticket_q : 32'd0;
                        local_error_tag_q <= 16'd0;
                        local_error_address_q <= 14'd0;
                    end
                end
            end else if (mgmt_req_fire) begin
                mgmt_rsp_valid_q <= 1'b1;
                mgmt_rsp_opcode_q <= mgmt_req_opcode;
                mgmt_rsp_state_q <= mgmt_state_d;
                mgmt_rsp_generation_q <= mgmt_generation_d;
                mgmt_rsp_lease_owner_ticket_q <=
                    mgmt_req_lease_owner_ticket;
                mgmt_rsp_tag_q <= mgmt_req_tag;
                mgmt_rsp_status_q <= mgmt_status_d;

                if ((mgmt_req_opcode == MGMT_CLAIM) &&
                    (mgmt_status_d == STATUS_ERR_GENERATION_EXHAUSTED)) begin
                    reset_required_q <= 1'b1;
                    reset_reason_q <= STATUS_ERR_GENERATION_EXHAUSTED;
                end

                if (mgmt_status_d == STATUS_OK) begin
                    case (mgmt_req_opcode)
                        MGMT_CLAIM: begin
                            bank_state_q <= ST_LOADING;
                            bank_generation_q <= mgmt_generation_d;
                            bank_generation_initialized_q <= 1'b1;
                            bank_authority_valid_q <= 1'b1;
                            bank_lease_owner_valid_q <= 1'b1;
                            bank_lease_owner_ticket_q <=
                                mgmt_req_lease_owner_ticket;
                            drain_target_q <= DRAIN_INVALID;
                        end
                        MGMT_PUBLISH_READY:
                            bank_state_q <= ST_READY;
                        MGMT_ACTIVATE:
                            bank_state_q <= ST_ACTIVE;
                        MGMT_BEGIN_DRAIN: begin
                            bank_state_q <= ST_DRAINING;
                            drain_target_q <= mgmt_req_drain_target;
                        end
                        MGMT_FINISH_DRAIN: begin
                            bank_state_q <= mgmt_state_d;
                            drain_target_q <= DRAIN_INVALID;
                            bank_authority_valid_q <= 1'b0;
                            bank_lease_owner_valid_q <= 1'b0;
                            bank_lease_owner_ticket_q <= 32'd0;
                        end
                        MGMT_EARLY_RETIRE: begin
                            bank_state_q <= ST_INVALID;
                            bank_authority_valid_q <= 1'b0;
                            bank_lease_owner_valid_q <= 1'b0;
                            bank_lease_owner_ticket_q <= 32'd0;
                            drain_target_q <= DRAIN_INVALID;
                        end
                        MGMT_EVICT_RETAINED: begin
                            bank_state_q <= ST_INVALID;
                            bank_authority_valid_q <= 1'b0;
                            bank_lease_owner_valid_q <= 1'b0;
                            bank_lease_owner_ticket_q <= 32'd0;
                            drain_target_q <= DRAIN_INVALID;
                        end
                        MGMT_CLEAR_ERROR: begin
                            bank_state_q <= ST_INVALID;
                            drain_target_q <= DRAIN_INVALID;
                            bank_authority_valid_q <= 1'b0;
                            bank_lease_owner_valid_q <= 1'b0;
                            bank_lease_owner_ticket_q <= 32'd0;
                            local_error_valid_q <= 1'b0;
                            local_error_code_q <= STATUS_OK;
                            local_error_source_q <= 2'd0;
                            local_error_generation_q <= 32'd0;
                            local_error_lease_owner_ticket_q <= 32'd0;
                            local_error_tag_q <= 16'd0;
                            local_error_address_q <= 14'd0;
                        end
                        default: begin
                            bank_state_q <= bank_state_q;
                        end
                    endcase
                end
            end else if (data_fault_fire) begin
                bank_state_q <= ST_DRAINING;
                drain_target_q <= DRAIN_ERROR;
                if (!local_error_valid_q) begin
                    local_error_valid_q <= 1'b1;
                    local_error_code_q <= data_fault_code;
                    local_error_source_q <= load_fault_fire ?
                                            ERROR_SOURCE_LOADER :
                                            ERROR_SOURCE_READ;
                    local_error_generation_q <= bank_generation_q;
                    local_error_lease_owner_ticket_q <=
                        bank_lease_owner_ticket_q;
                    local_error_tag_q <= load_fault_fire ?
                                         load_req_tag : rd_req_tag;
                    local_error_address_q <= load_fault_fire ?
                                             load_req_beat_addr :
                                             {1'b0, rd_req_addr};
                end
            end
        end
    end

endmodule
