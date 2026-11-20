# Sparse Memory v1 isolation rules

This directory is an isolated development boundary for
`sequential-v4-sparse-load-v1`.

- Read the repository `PROJECT_STATUS.md`, the PYNQ-Z1 feasibility checklist,
  this file, `STATUS.md`, and `MANIFEST.md` before changing this subtree.
- All files created or modified for this work must remain under
  `sparse_memory_v1/`. Do not modify the repository's existing `rtl/memory/`,
  `docs/memory/`, accelerator-top sources, global tests, scripts, or reports.
- Files under `imports/` are immutable byte-for-byte snapshots. Never edit,
  regenerate, symlink, or overwrite them. Copy a required source into `rtl/`,
  `tb/`, `tests/`, or another local working directory before changing it.
- Compile and simulation runners must use explicit source allowlists. They may
  not glob or compile sources outside this directory.
- Use unique names for new RTL modules, tops, tests, reports, and artifacts.
- Stage and commit only paths below `sparse_memory_v1/`. Each completed
  checkpoint requires its own descriptive Git commit.
- Keep analytical estimates, host/reference results, RTL simulation, Vivado
  measurements, and board measurements clearly separated.
- Promotion into the existing accelerator top requires a separate explicit
  user authorization after this isolated line is frozen.

