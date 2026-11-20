`timescale 1ns/1ps

// Atomic active-index command adapter.
//
// pe_spike_decision guarantees that every valid input event has at least one
// action asserted: spike_in requests an index write and last_in requests
// logical-vector finalization.  A terminal spike asserts both actions in the
// same ready/valid transaction so the memory subsystem accepts them atomically.
//
// This module deliberately owns no count, capacity, write pointer, storage,
// buffering, or frame state.  All command payload fields remain stable under
// backpressure because the upstream ready/valid source holds the event until
// mem_cmd_ready is asserted.
module pe_active_index_writer #(
    parameter integer INDEX_WIDTH = 9,
    parameter integer TAG_WIDTH   = 16
) (
    input  wire                         event_valid,
    output wire                         event_ready,
    input  wire                         spike_in,
    input  wire [INDEX_WIDTH-1:0]       index_in,
    input  wire [TAG_WIDTH-1:0]         tag_in,
    input  wire                         last_in,

    output wire                         mem_cmd_valid,
    input  wire                         mem_cmd_ready,
    output wire                         mem_cmd_write,
    output wire [INDEX_WIDTH-1:0]       mem_cmd_index,
    output wire [TAG_WIDTH-1:0]         mem_cmd_tag,
    output wire                         mem_cmd_finalize
);

    assign event_ready      = mem_cmd_ready;
    assign mem_cmd_valid    = event_valid;
    assign mem_cmd_write    = spike_in;
    assign mem_cmd_index    = index_in;
    assign mem_cmd_tag      = tag_in;
    assign mem_cmd_finalize = last_in;

endmodule
