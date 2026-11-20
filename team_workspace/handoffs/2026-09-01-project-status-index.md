# Handoff: 共用專案進度入口

- From: Codex
- To: 所有後續 RTL、testbench、memory、Vivado 與板測任務負責人
- Branch / commit: requested `codex/project-status-index`; no commit because
  the outer repository has no initial commit.
- Main files:
  - `PROJECT_STATUS.md`
  - `docs/音訊降噪系統整合報告.pdf`
  - `AGENTS.md`
  - `TEAM_COLLABORATION.md`
  - `team_workspace/README.md`
  - `team_workspace/tasks/2026-09-01-project-status-index.md`
  - This handoff

## Result

- `PROJECT_STATUS.md` is now the single entry point for current architecture,
  completed and pending work, evidence level, limitations, decisions, and next
  checkpoints.
- The original presentation was copied from the private Codex attachment path
  into the shared project. Source and project copy both have SHA-256
  `d44675cc82b0464a1842f9633e62836f345a01306474097eb57a6636e06aea56`.
- Team instructions now require this status page to be updated whenever a
  verifiable checkpoint is completed.
- The status snapshot records the latest behavioral evidence as Windows XSim
  17/17 PASS and Python integer reference 13/13 PASS. It explicitly records
  that synthesis, implementation, timing, and PYNQ-Z1 measurements do not yet
  exist.

## Verification performed

- Re-ran `python3 rtl/tests/reference_checks.py`: PASS, 13/13.
- Confirmed `rtl/test-results/xsim-console.log` contains 17 `XSIM_PASS` markers
  and `XSIM_SUMMARY passed=17 total=17`.
- Parsed all 18 local links in `PROJECT_STATUS.md`: 18 resolved, 0 missing.
- Recomputed the copied presentation SHA-256: it matches the source attachment.

## Maintenance rule

At every completed checkpoint, update `PROJECT_STATUS.md` in the same branch or
pull request as the task and handoff. Do not replace behavioral simulation
evidence with synthesis or board claims unless those tools or the physical
board were actually run and their reports are linked.

## Current limitation

The outer repository still has no initial commit or shared remote recorded in
the repository. The documentation is available in this shared folder now, but
versioned collaboration and pull-request review require the repository setup
listed in `PROJECT_STATUS.md`.
