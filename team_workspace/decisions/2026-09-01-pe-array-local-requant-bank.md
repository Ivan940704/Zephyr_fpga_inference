# PE Array Local Requant Bank baseline

- Date: 2026-09-01
- Status: accepted baseline
- Scope: independent PE Array under `rtl/pe_array/`

## Decision

The first PE Array implementation uses one four-lane Local Requant Bank:

- four physical `pe_requant_lane` instances;
- exact lane latency 9 cycles and no-stall II=1;
- one common ready/valid packet carrying four lane slots and a lane-valid mask;
- parameters supplied with requests; no local parameter RAM;
- common backpressure across all four lanes.

The architecture does not require zero Local-RQ stall in the 90%-sparsity
worst case. Actual model layers have different sparsity, so small RQ-related
stalls at extremely high sparsity are accepted for the first version.

An eight-lane bank is retained only as a profiling-driven future optimization
and is not implemented in the current baseline.

## Consequences

- Measured bank OOC utilization is 2,167 LUT, 1,732 FF, 16 DSP48E1, and zero
  BRAM on `xc7z020clg400-1`.
- The bank maintains 9-cycle no-stall latency, bank packet II=1, and up to four
  active results per cycle.
- Later gate/membrane scheduling should operate at four-neuron-group granularity
  where dependencies allow; it need not wait for a complete 16-neuron batch.
- The control-only `pe_membrane_sequencer` must schedule this bank and the
  reused Hybrid PEs. It must not add a dedicated multiplier or membrane
  arithmetic lane.
- Profiling must compare real per-layer sparsity, RQ stalls, PE idle cycles, and
  frame RTF before reconsidering eight lanes.
