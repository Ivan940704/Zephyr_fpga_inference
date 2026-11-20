# Task: Import and assess the uploaded Memory RTL bundle

- Owner: Codex
- Status: done
- Branch: `codex/memory-rtl-import` requested; the outer repository has no
  initial commit, so a task branch cannot be created yet.
- Scope:
  - Safely inspect and classify the uploaded Memory-only archive without
    overwriting the outer project or dirty `upstream/` repository.
  - Import the AXI read-DMA/BRAM-cache RTL, generated memory-map ABI, testbench,
    generator, image-integrity test, generated snapshot, and source handoff
    documents into the matching outer-repository folders.
  - Adapt repository-relative paths to the current nested `upstream/` layout.
  - Analyze how the imported raw 64-bit cache can serve the existing 128-bit
    GSU/projection weight and lane-packed parameter request interfaces.
  - Record architectural conflicts, missing adapters, and a staged integration
    recommendation using repository and RTL evidence.
- Files expected to change:
  - `rtl/memory/`
  - `rtl/tb/tb_memory.v`
  - `rtl/scripts/run_memory_xsim.ps1`
  - `rtl/tools/generate_axi_memory_image.py`
  - `rtl/tests/test_axi_memory_image.py`
  - `outputs/memory/2026-09-01/`
  - `docs/memory/`
  - `rtl/Makefile`
  - `rtl/scripts/run_all_xsim.tcl`
  - `rtl/scripts/Run-XSim-Tests.cmd`
  - `rtl/README.md`
  - `PROJECT_STATUS.md`
  - `team_workspace/handoffs/2026-09-01-memory-rtl-import.md`
- Out of scope:
  - Changes inside the dirty `upstream/` nested repository.
  - Implementing the missing weight-layout adapter, parameter unpacker, global
    FSM/top wrapper, AXI block design, CDC, writeback DMA, or PS driver.
  - Synthesis, implementation, bitstream generation, or PYNQ-Z1 measurement.
- Acceptance checks:
  - [x] ZIP integrity, path safety, source SHA-256, and destination mapping are
    recorded.
  - [x] Imported files do not overwrite unrelated project or `upstream/` work.
  - [x] The image generator reproduces the uploaded binary and Verilog header
    from the current `upstream/parameters` inputs.
  - [x] The Python image integrity test passes from its classified location.
  - [x] Memory RTL is included in the existing simulator manifests; available
    local checks are run and unavailable Vivado/board checks are explicit.
  - [x] The integration report distinguishes facts, analytical conclusions,
    prior local evidence, and unverified implementation/board claims.
