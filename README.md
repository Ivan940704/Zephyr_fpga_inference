# Zephyr FPGA inference RTL

Complete tracked RTL source snapshot from development commit `d842ca1399c41e59446306ca1445e7925e3cb69d` (`codex/hybrid-pe-deepfilter`). This includes the earlier sparse-v5 checkpoint and subsequent hybrid PE / DeepFilter integration.

- `rtl/`: accelerator modules, historical baselines, testbenches, constraints and Vivado scripts.
- `sparse_memory_v1/`: isolated sparse-memory implementation and imported baseline.
- `software/`: host / PYNQ runtime sources.
- `docs/`: design and verification documentation.
- `upstream/`: model repository submodule pinned to `13ea1405c9a400aac647025a42b216975765a9bb`.
- `SOURCE_MANIFEST.json`: original source paths, SHA-256 hashes and byte counts.

Clone with `git clone --recurse-submodules <repository-url>`.
See `rtl/README.md`, `rtl/Makefile`, and the relevant scripts for build/test entry points. Existing scripts can contain historical machine-specific paths; adjust them to the local environment. Generated build products, binary model data and curated measurement report directories are outside this source snapshot; dependencies may need regeneration using the included scripts and model submodule.

Publication checks cover source completeness and byte identity. Simulation, synthesis, timing and board tests were not rerun for this upload. Historical measurements in documentation retain their original scope and are not fresh verification of this snapshot. This is a source snapshot, not the complete development Git history.
