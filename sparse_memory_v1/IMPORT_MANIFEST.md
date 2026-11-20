# Imported baseline manifest

All files below `imports/` were copied from repository commit
`a73c884d5514a3e6d812339836b2ff4b24008015`. The individual content hashes are
authoritative in `IMPORT_SHA256SUMS`.

| Destination | Source | Purpose |
|---|---|---|
| `imports/memory_v4/memory/` | `rtl/memory/` selected v4 files | Dense loader, v4 geometry, context/controller, subsystem, and XDC baseline |
| `imports/memory_v4/tb/` | `rtl/tb/` selected tests | Historical connected-test reference only |
| `imports/memory_v4/tests/` | `rtl/tests/` selected references | Historical Python/reference behavior only |
| `imports/pe_v1/rtl/` | `rtl/pe_array/baseline/v1/rtl/` | Frozen PE sources needed by isolated connected validation |
| `imports/control/fsm.v` | `rtl/control/fsm.v` | Frozen schedule source needed by isolated connected validation |
| `imports/baseline_docs/` | current memory/freeze/feasibility records | Read-only provenance and evidence boundary |
| `imports/fixtures/v4/` | `outputs/memory/2026-09-03/v4/` | Immutable v4 image, layout, golden, and checksum fixture |

Imports are excluded from modification. Active RTL must be copied to `rtl/`
and renamed before it is changed.

