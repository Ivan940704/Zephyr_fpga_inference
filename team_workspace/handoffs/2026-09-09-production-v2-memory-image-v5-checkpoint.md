# Production-v2 memory image-v5 checkpoint handoff

- Date: 2026-09-09 (Asia/Taipei)
- Owner: Codex
- Branch: `codex/latency-experiment-32pe`
- Checkpoint: Phase 5B complete; Phase 5C not authorized

## Delivered

- Added a separate deterministic image-v5 generator for 32-row weight and
  parameter packing.
- Added versioned v5 binary/layout/golden/checksum artifacts and generated RTL
  map, stage table, and 256-bit readback table.
- Added an independent exhaustive integer oracle that compares current raw
  tensors and every corresponding v4 tile/field pair.
- Preserved the external 64-bit bus contract and all v3/v4 files.

## Verification

- Phase 5B pytest: 7/7 PASS.
- Vivado 2018.3 `xvlog`: both v5 descriptor modules PASS.
- Deterministic temporary rebuild: byte-identical artifact set PASS.
- Image SHA-256:
  `0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a`.
- Exact geometry and limitations:
  `rtl/reports/production_v2_memory_image_v5/summary.md`.

The old v3/v4 tests remain 9 PASS / 4 FAIL because their frozen image headers
embed the former manifest SHA (`eb79...`) while the clean nested repository now
contains `e561...`. No v3/v4 file was changed; v5 explicitly locks both the
current source identity and the unchanged v4 payload semantics.

## Stop boundary

No memory-service/controller integration, production top, synthesis, BIT/HWH,
five-file board test, or 100-audio run was performed. Phase 5C may begin only
after explicit approval. Its scope is the 32-row memory-service response and
job-controller providers; Phase 5D and later remain out of scope.
