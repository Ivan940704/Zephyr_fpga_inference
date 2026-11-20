# Publish complete RTL source

- Owner: Codex
- Status: done
- Branch: codex/publish-rtl
- Scope: Initial private source publication from development commit d842ca1399c41e59446306ca1445e7925e3cb69d.
- Changed files: 670 copied source/support files, source manifest, publication README, and collaboration records. No RTL behavior changes.
- Acceptance: all 209 tracked HDL files retained; source hashes checked; recognizable embedded credential scan found no matches; model submodule retained at 13ea1405c9a400aac647025a42b216975765a9bb.
- Checks: older sparse-v5 commit 946c002 is an ancestor of the selected source; original source worktrees were clean before publication. Remote commit and private visibility are checked after push.
- Limitations: no new simulation, Vivado or board tests; this is a source snapshot without development history or generated binary artifacts.
