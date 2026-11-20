# Zephyr FPGA Git Collaboration Guide

This repository uses Git history as the required collaboration record. Codex
and human contributors should keep the workflow lightweight and preserve work
that is already present in the shared checkout.

## Required workflow

- Before editing, read `PROJECT_STATUS.md` and
  `docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md`. Confirm the current project state and
  the applicable PYNQ-Z1 constraints before changing files.
- Run `git status --short --branch` before editing. If work touches `upstream/`,
  also run `git -C upstream status --short --branch`.
- Do not overwrite, discard, stage, or reformat another contributor's unrelated
  changes.
- Do not create a task card for routine work. Create one only when the user
  explicitly requests it.
- Every completed update must be recorded in a Git commit. Stage only the files
  that belong to the update and use a descriptive commit message.
- When a shared remote is configured, push the commit or its branch before
  handing the work to another contributor.
- Run checks appropriate to the change and report accurately what was and was
  not verified.

Handoff notes, decision records, `PROJECT_STATUS.md` updates, task-specific
branches, and pull requests are optional. Use them only when they add useful
context; they are not required for every update.

## Hardware evidence

For substantial RTL, PS datapath, memory, AXI, or integration changes, apply the
relevant gates from `docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md`. Keep analytical
estimates, RTL/testbench evidence, Vivado measurements, and board measurements
clearly separated. Do not claim unverified implementation or board results.

## Repository boundary

- The outer repository owns project estimates, reports, generated presentation
  artifacts, and optional collaboration records.
- `upstream/` is a nested Git repository sourced from
  `https://github.com/Ivan940704/allen_Zephyr.git` on branch
  `fpga-inference`.
- Commit changes made inside `upstream/` in that repository first. Then commit
  the updated gitlink in the outer repository separately.
- Never delete `upstream/.git` or flatten the nested repository unless the team
  explicitly decides to change the repository architecture.
