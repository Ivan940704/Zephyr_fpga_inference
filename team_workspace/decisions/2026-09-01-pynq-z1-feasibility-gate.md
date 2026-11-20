# Decision: 每個模塊必須通過 PYNQ-Z1 feasibility gate

- Date: 2026-09-01
- Participants: Ivan, Codex
- Status: accepted
- Context:
  - Target board is PYNQ-Z1 / `xc7z020clg400-1`, with limited LUT, FF, BRAM,
    DSP, DDR bandwidth, AXI ports, and PS CPU time.
  - A module can be functionally correct in XSim but still fail after scaling
    its lane/instance count or integrating memory and AXI infrastructure.
  - Existing single-module OOC evidence, such as `pe_requant_lane`, must not be
    mistaken for full accelerator feasibility.
- Decision:
  - Every new hardware or PS datapath change must complete Gate A in
    `docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md` before substantial implementation.
  - Every completed module must report intended instance-scaled resources,
    local memory/ports, DDR/AXI traffic, cycles/II, target clock, CDC, and a
    fallback architecture.
  - Multiplier-, BRAM-, multi-lane-, AXI-, or wide-datapath modules require a
    representative `xc7z020clg400-1` OOC synthesis when Vivado is available.
  - Integration decisions use the sum of modules plus AXI/DMA/FSM/FIFO/clock
    overhead and routing margin; a single-lane report is not sufficient.
  - Claims remain explicitly separated into analytical estimate, RTL/XSim,
    OOC synthesis, full implementation, and physical board measurement.
- Consequences:
  - A module may be functionally complete but remain feasibility `UNKNOWN` or
    `PASS WITH RISKS`; it cannot be called board-ready until the required
    evidence exists.
  - Exceeding 80% of a device resource is a high-risk review trigger and
    requires a lane/tiling/time-multiplex/PS fallback; it is not a hard promise
    that values below 80% will route.
  - Feasibility evidence must be preserved in Git. It may live in a design
    document, implementation report, or commit context; no task card or handoff
    is required.
- Supersedes: informal per-task resource discussion without a common gate
