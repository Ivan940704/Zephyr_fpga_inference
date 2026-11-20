# Publish complete RTL source

- Owner: Codex
- Status: done
- Branch: codex/publish-rtl
- Scope: Initial private source publication from development commit d842ca1399c41e59446306ca1445e7925e3cb69d.
- Changed files: 670 copied source/support files, source manifest, publication README, and collaboration records. No RTL behavior changes.
- Acceptance: all 209 tracked HDL files retained; source hashes checked; recognizable embedded credential scan found no matches; model submodule retained at 13ea1405c9a400aac647025a42b216975765a9bb.
- Checks: older sparse-v5 commit 946c002 is an ancestor of the selected source; original source worktrees were clean before publication. Remote commit and private visibility are checked after push.
- Limitations: no new simulation, Vivado or board tests; this is a source snapshot without development history or generated binary artifacts.
- Final-version clarification: recommend ABI 0x00050003 Hybrid PE + sparse-v5. Add BEST_VERSION.md and the exact 100-file evidence, retain tradeoffs versus sparse-v5, and tag v1.0.0-hybrid-pe-final. No production HDL/software changes from board hardware source f460743 through source snapshot d842ca1; only differential testbench/build/evidence updates.
