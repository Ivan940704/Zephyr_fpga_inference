# Task: Define the production memory design guidelines

- Owner: Codex
- Status: done
- Branch: `codex/memory-design-guidelines`
- Scope:
  - Turn the accepted parameter/runtime-data transport split into one canonical
    memory design guideline.
  - Convert the twelve outstanding integration steps into ordered gates with
    prerequisites, required artifacts, acceptance checks, and stop conditions.
  - Resolve the parameter-path conflict with the earlier AXI interface
    prototype without rewriting its historical verification evidence.
  - Keep repository facts, analytical estimates, RTL/XSim evidence, Vivado
    evidence, and board evidence explicitly separated.
- Files expected to change:
  - `docs/memory/MEMORY_DESIGN_GUIDELINES.md`
  - `docs/memory/MEMORY_INTEGRATION_ANALYSIS.md`
  - `docs/memory/MEMORY_RTL_GUIDE.md`
  - `team_workspace/decisions/2026-09-01-parameter-and-runtime-data-transport-partition.md`
  - `team_workspace/decisions/2026-09-01-axi-interface-partition.md`
  - `PROJECT_STATUS.md`
  - `team_workspace/handoffs/2026-09-01-memory-design-guidelines.md`
- Out of scope:
  - RTL, testbench, image-generator, Vivado block-design, PS-driver, or
    `upstream/` changes.
  - Claiming that the 256 KiB cache, custom AXI master, AXI DMA, CDC, timing,
    bandwidth, or board real-time target has already passed implementation.
- Acceptance checks:
  - [x] Parameter and feature/result paths have disjoint responsibilities and
    an explicit ownership contract.
  - [x] The v3 image, cache/service, AXI4-Stream packet, reset/CDC, error, and
    feasibility rules are specified without contradicting accepted decisions.
  - [x] All twelve steps are ordered and each has prerequisites, artifacts,
    acceptance evidence, and a blocking rule.
  - [x] Existing documents point to one canonical guideline and clearly mark
    the partial supersession of the prototype parameter transport.
  - [x] Documentation links and whitespace checks pass; no `upstream/` file is
    changed by this task.

## PYNQ-Z1 feasibility relevance

This is a documentation/architecture checkpoint, not module implementation.
The guideline must nevertheless require Gate A before implementation and Gate
B/C evidence at the appropriate later stages. Current 256/512 KiB BRAM figures
remain analytical estimates until representative synthesis is run for
`xc7z020clg400-1`.
