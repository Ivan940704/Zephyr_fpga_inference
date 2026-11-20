# Global FSM and subband parallelism baseline

- Date: 2026-09-01
- Status: accepted control baseline; parallel datapath remains provisional
- Scope: global `fsm.v`, future `top.v`, PE array, and memory service

## Decision

The global FSM supports two latched subband schedules:

- Default PYNQ-Z1 mode: one physical subband engine and bank time-multiplexed
  across logical branches 0/1/2 and their 4/3/2 contexts.
- Experimental mode: three physical engines and banks, one per branch, running
  concurrently within each GSU1, GSU2, and projection stage.

The stage order is stage-major: fullband IDs 0/1/2, then subband GSU1 IDs
3/6/9, GSU2 IDs 4/7/10, and projections 5/8/11. Parallel mode waits for all
three branches at every stage barrier. The PS-to-PL return event is atomic and
means all nine normalized subband vectors are buffered. In the production
transport revision, this event is generated only after the GP-mapped 4 KiB
mailbox commits the complete 782-byte slot with the expected frame ID; it is
not a DDR/DMA packet-completion pulse.

Future `top.v` must keep parallel mode disabled by default until complete
three-engine resource, memory-port, implementation-timing, and board-latency
evidence passes the PYNQ-Z1 feasibility gate.

## Basis

- Both schedules pass the self-checking XSim FSM test.
- The FSM itself passes `xc7z020clg400-1` 100 MHz OOC at 121 LUT, 67 FF,
  zero DSP/BRAM, and WNS +4.792 ns.
- Current raw stage-size mapping estimates about 102 of 140 BRAM36 for three
  GSU2 banks alone, and about 210 BRAM36 for all three complete branch stage
  sets. A single 64-bit memory port cannot serve three independent 128-bit
  consumers per cycle.
- Complete PE-array instance-scaled synthesis and board bandwidth are not yet
  available.

## Consequences

- `fsm.v` can be integrated before the final parallelism choice because both
  modes share stage, completion, and error contracts.
- The shared schedule is slower but avoids triplicating the main datapath and
  branch weight ports.
- The parallel control path is not evidence that the parallel accelerator fits
  or is faster on PYNQ-Z1.
- If a single engine misses the real-time target, evaluate two-way scheduling
  and active-source/tile caches before committing to three full engines.
