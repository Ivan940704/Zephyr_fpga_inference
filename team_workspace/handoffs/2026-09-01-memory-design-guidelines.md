# Handoff: production memory transport and twelve-gate guideline

- From: Codex
- To: v3 image, memory service, AXI block-design, and PS-driver owners
- Date: 2026-09-01 (Asia/Taipei)
- Branch: `codex/memory-design-guidelines`
- Task: `team_workspace/tasks/2026-09-01-memory-design-guidelines.md`

## Outcome

The production transport split is now explicit and has one canonical guideline:

```text
PL static parameters:
PS DDR -> memory.v custom AXI4 read -> parameter BRAM stage/tile cache
       -> memory_service -> native PE interfaces

Runtime feature/result:
PS DDR <-> Xilinx AXI DMA <-> 64-bit AXI4-Stream <-> PL
```

The earlier AXI decision remains valid as historical prototype evidence, but is
partially superseded for PL-consumed weight/parameter transport. AXI4-Lite
control, runtime AXI4-Stream, native ready/valid, and the independent prototype
test results are retained.

`docs/memory/MEMORY_DESIGN_GUIDELINES.md` now defines data ownership, v3 image
ABI, provisional 256 KiB single-stage cache, native response behavior,
feature/result packet rules, coherency, reset/CDC/error handling, PYNQ-Z1
feasibility, and twelve ordered implementation/acceptance gates.

## Changed files

- `docs/memory/MEMORY_DESIGN_GUIDELINES.md`
- `docs/memory/MEMORY_INTEGRATION_ANALYSIS.md`
- `docs/memory/MEMORY_RTL_GUIDE.md`
- `team_workspace/decisions/2026-09-01-parameter-and-runtime-data-transport-partition.md`
- `team_workspace/decisions/2026-09-01-axi-interface-partition.md`
- `PROJECT_STATUS.md`
- task/handoff records for this checkpoint

## Verification and evidence boundary

- Documentation consistency, relative links, and whitespace were checked.
- Existing source-major, FSM, PS preprocessing, GSU interface, and feasibility
  decisions were reviewed against the new split.
- No RTL, generator, Vivado project, driver, or `upstream/` file was changed.
- No new simulation, synthesis, implementation, bandwidth, RTF, or board result
  is claimed. The 256/512 KiB BRAM figures remain analytical estimates.

## Next action

Start at Gate 2: generate and golden-check the versioned v3 parameter image.
Then complete the intended-count PYNQ-Z1 Gate A before implementing
`memory_service`. Do not start from the Vivado block design or performance
optimizations while the image ABI and representative cache fit remain open.

Runtime packet details are intentionally still open until Gate 10: choose the
subband 1/3/9-packet grouping, freeze the final DeepFilter/output element format
and length, and select AXI DMA simple or scatter-gather mode. These do not block
the Gate 2--8 parameter/fullband memory work.
