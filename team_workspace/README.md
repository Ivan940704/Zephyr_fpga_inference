# Team workspace

This directory stores optional historical and collaboration context that can
travel with the Git repository. Git commits are the required record. Routine
work does not create a task card.

Use [`PROJECT_STATUS.md`](../PROJECT_STATUS.md) when a summary of the current
project phase, verification evidence, limitations, and next actions is useful.
Update it when the aggregate project state materially changes, not for every
checkpoint.

- `tasks/`: preserve historical task cards; create a new one only when the user
  explicitly requests it.
- `handoffs/`: optionally record context needed by the next contributor.
- `decisions/`: optionally record durable decisions that affect multiple tasks.

Use filenames beginning with an ISO date, for example
`2026-08-31-fpga-estimate-review.md`.
