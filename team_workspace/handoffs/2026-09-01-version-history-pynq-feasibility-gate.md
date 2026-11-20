# Handoff: version history and PYNQ-Z1 feasibility gate

- From: Codex
- To: All future RTL, PS software, memory/AXI, integration, and repository tasks
- Branch: `codex/version-history-pynq-gate`
- Commits:
  - `124a771 Establish verified Zephyr FPGA project baseline`
  - Feasibility-gate changes are the next commit on this branch; use
    `git log --oneline --decorate` for its final hash.
- Main files:
  - `.gitignore`
  - `.gitmodules`
  - `AGENTS.md`
  - `TEAM_COLLABORATION.md`
  - `docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md`
  - `PROJECT_STATUS.md`
  - `team_workspace/tasks/README.md`
  - `team_workspace/decisions/2026-09-01-pynq-z1-feasibility-gate.md`
  - `team_workspace/tasks/2026-09-01-version-history-pynq-feasibility-gate.md`
  - This handoff

## Result

- The outer repository now has an initial baseline commit containing the
  project documentation, RTL, self-checking testbenches, curated logs/reports,
  memory image, collaboration records, and presentation artifacts.
- `upstream/` is stored as a gitlink at
  `13ea1405c9a400aac647025a42b216975765a9bb`, with `.gitmodules` pointing to
  the `fpga-inference` branch.  Its pre-existing uncommitted changes were not
  staged, committed, reformatted, or discarded.
- Vivado/XSim build products, local Codex metadata, Python caches, and the host
  setup report are ignored.  Curated test and synthesis evidence remains
  tracked.
- A private Tailscale/hostname report was excluded; committed Vivado reports
  retain metrics but use `<redacted-host>` instead of the laptop name.
- Every future hardware/PS datapath task must complete PYNQ-Z1 Gate A before
  implementation and Gate B/C evidence as it progresses.

## PYNQ-Z1 gate summary

- Planning target: `xc7z020clg400-1`.
- Required precheck: intended instance count, scaled LUT/FF/DSP/BRAM, buffer and
  ports, DDR/AXI traffic, cycles/II/RTF, target clock/CDC, main risk, fallback,
  and evidence level.
- More than 80% of any resource is a high-risk review trigger, not a guarantee
  that lower utilization will route.
- Multiplier/BRAM/multi-lane/AXI/wide datapaths require representative OOC
  synthesis when Vivado is available.
- Board-ready claims require full implementation and physical PYNQ-Z1
  measurements; XSim or a single-lane OOC report is insufficient.

## Verification

- Baseline commit contains 204 paths and records `upstream` with mode `160000`.
- `rtl/build/`, `rtl/.Xil/`, local workspace metadata, and host setup report
  resolve through `.gitignore` and are absent from the commit.
- Staged-content secret/path scan found no private key, Tailscale address,
  unredacted laptop name, or user-home absolute path.
- Markdown link validation is recorded in the final task verification.

## Remaining collaboration step

The outer repository has no remote.  A project owner still needs to create or
select the shared GitHub repository, add it as `origin`, push this branch, and
have a teammate verify `git clone --recurse-submodules` before the PR workflow
is considered operational.
