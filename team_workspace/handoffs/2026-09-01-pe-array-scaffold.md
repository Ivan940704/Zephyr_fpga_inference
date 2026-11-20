# Handoff: Independent PE Array planning scaffold

- Date: 2026-09-01 (Asia/Taipei)
- Owner: Ivan Huang (PE Array), with Codex assistance
- Task: `team_workspace/tasks/2026-09-01-pe-array-independent-development.md`
- Status: planning checkpoint complete; implementation task remains in progress

## Changed files

- `rtl/pe_array/README.md`
- `rtl/pe_array/.gitignore`
- `rtl/pe_array/spec/MODULE_DEVELOPMENT_PLAN.md`
- `.gitkeep` placeholders in the isolated RTL/TB/reference/script/constraint/report
  subdirectories
- `team_workspace/tasks/2026-09-01-pe-array-independent-development.md`
- `team_workspace/handoffs/2026-09-01-pe-array-scaffold.md`
- `PROJECT_STATUS.md`

No `.v` or `.sv` file was created or modified.

## Verification performed

```text
find rtl/pe_array -type f ( -name '*.v' -o -name '*.sv' ) | wc -l
result: 0

find rtl/leaf rtl/sparse ... | sha256sum
before: 74f6880c9f2df6d0bd47e0b90b37c2dc857e4b828b762df8324bb2e2a661e2cc
after:  74f6880c9f2df6d0bd47e0b90b37c2dc857e4b828b762df8324bb2e2a661e2cc
```

The repository has no initial commit, so `git status` reports all pre-existing
project content as untracked and cannot provide a meaningful diff baseline. The
protected-tree hash was therefore used to confirm that `rtl/leaf/` and
`rtl/sparse/` were unchanged.

## Evidence and limitations

- Evidence: isolated directory tree exists; module order, provisional interfaces,
  and verification gates are documented; protected RTL hash is unchanged.
- Not performed: RTL simulation, Python bit-exact testing, Vivado synthesis,
  implementation, timing, resource measurement, RTF measurement, or board test.
- Consequently, this checkpoint makes no functionality, area, timing, or
  throughput claim.

## Next checkpoint

Implement only `pe_requant_lane` inside `rtl/pe_array/`, first freezing its signed
rounding contract against the upstream Python integer reference. Do not start the
four-lane bank until unit simulation, bit-exact vectors, and 5 ns out-of-context
Vivado synthesis all pass and their reports are recorded.

## Architecture clarification

The planned `pe_membrane_update` name has been replaced by
`pe_membrane_sequencer`. This is a control/storage module only: phase control,
temporary registers, lane/pending masks, Hybrid PE mode/control, and Local RQ
request/response scheduling. It must not contain or infer a multiplier, requant
lane, MAC, dedicated neuron lane, or separate membrane arithmetic datapath.
