# Decision: GSN neuron reference cell and production resource sharing

- Date: 2026-09-01
- Participants: project team, Codex
- Status: accepted
- Context: a standalone bit-exact GSN/GSU neuron cell needs seven requant
  operations, two membrane products and one sigmoid lookup. Its XC7Z020 OOC
  result is 5 DSP per validation instance.
- Decision: keep `pe_gsn_cell` as a one-transaction bit-exact RTL checkpoint and
  integration reference. Do not replicate it once per 320 neuron channels.
  Production fullband layers must time-multiplex the existing 16 Hybrid PEs and
  four-lane Local RQ bank across neuron tiles and share postprocess resources.
- Consequences: standalone cell latency/resource figures cannot be multiplied
  into a claimed board architecture. The connected GSN scheduler must prove
  multi-frame correctness, intended-count OOC resources, memory bandwidth,
  implementation timing and board performance separately.
- Supersedes: none
