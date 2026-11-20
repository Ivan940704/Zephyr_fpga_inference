# Decision: PE Array small-model verification boundary

- Fullband LayerNorm remains outside PL because its fixed-point epsilon,
  variance, affine and rounding contract is not frozen. The reference produces
  normalized INT8 input using the exported model input scale.
- The first hardware architecture uses one 16-lane Hybrid MAC array. Fullband
  layers, projection and DeepFilter time-multiplex it; no three-engine
  replication is enabled on PYNQ-Z1.
- A one-entry registered product pipeline is mandatory in each Hybrid MAC. It
  preserves II=1 and changed 200 MHz OOC timing from -3.294 ns to +0.270 ns.
- The full-shape test uses real `parameters.bin` weights and parameters but zero
  recurrent initial state for one frame. Multi-frame state and production
  memory/AXI integration remain separate acceptance gates.
- OOC resource results for the 16-MAC arithmetic shell must not be presented as
  full-system fit because Local RQ, cache, AXI and memory fabric are excluded.
