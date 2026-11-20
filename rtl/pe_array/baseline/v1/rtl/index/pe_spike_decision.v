`timescale 1ns/1ps

// QBN-only signed INT8 spike decision and active-index event filter.
//
// The upstream QBN postprocess guarantees state_q_in in the symmetric signed
// range -127..127.  The fixed inference predicate is inclusive of zero:
//
//   spike = (signed(state_q_in) >= 0)
//
// Ordinary non-spikes are consumed without creating a downstream transaction.
// A logical-last input is still emitted when it is a non-spike so the
// downstream active-index writer can finalize an empty or negative-ending
// vector.  The writer writes index_out only when spike_out is asserted and
// finalizes the vector whenever last_out is asserted.
//
// Linear results must be demultiplexed around this QBN-only leaf by the parent
// integration logic.  This module contains no threshold storage, pipeline,
// FIFO, spike vector, requantizer, multiplier, or other arithmetic datapath.
module pe_spike_decision #(
    parameter integer INDEX_WIDTH = 9,
    parameter integer TAG_WIDTH   = 16
) (
    input  wire                          in_valid,
    output wire                          in_ready,
    input  wire signed [7:0]             state_q_in,
    input  wire        [INDEX_WIDTH-1:0] index_in,
    input  wire        [TAG_WIDTH-1:0]   tag_in,
    input  wire                          last_in,

    output wire                          out_valid,
    input  wire                          out_ready,
    output wire                          spike_out,
    output wire        [INDEX_WIDTH-1:0] index_out,
    output wire        [TAG_WIDTH-1:0]   tag_out,
    output wire                          last_out
);

    wire emit_event;

    assign spike_out = ($signed(state_q_in) >= 0);
    assign emit_event = spike_out | last_in;

    assign out_valid = in_valid & emit_event;
    assign in_ready  = emit_event ? out_ready : 1'b1;

    assign index_out = index_in;
    assign tag_out   = tag_in;
    assign last_out  = last_in;

endmodule
