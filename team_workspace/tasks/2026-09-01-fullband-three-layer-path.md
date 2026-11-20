# Task: Build the fullband GSU1 -> GSU2 -> projection path

- Owner: Codex
- Status: complete
- Branch: `codex/fullband-three-layer-path` requested; no branch can be created
  before the outer repository has an initial commit.
- Scope:
  - Add a binary-input INT8 linear projection with packed 16-lane weight and
    parameter interfaces.
  - Verify projection sparsity, requantization, saturation, and backpressure as
    a standalone module.
  - Instantiate the verified GSU layer as fullband layer 1 (64 -> 320, dense
    input) and layer 2 (320 -> 320, binary sparse input).
  - Connect layer-1 spikes to layer 2 and layer-2 spikes to the 320 -> 64
    fullband projection under an explicit chain controller.
  - Add a self-checking reduced-dimension three-layer integration testbench
    before any physical memory or board integration.
- Out of scope:
  - PC LayerNorm, STFT/ISTFT, AXI/DMA, actual `parameters.bin` loader, and final
    `top.v` integration.
  - Synthesis, implementation, timing, bitstream, and PYNQ-Z1 measurements.
  - Changes inside the dirty `upstream/` nested repository.
- Acceptance checks:
  - [x] Standalone projection matches an independent dense integer reference.
  - [x] Projection reads only active layer-2 spike columns.
  - [x] Layer 1, layer 2, and projection execute in the requested order.
  - [x] Separate recurrent states persist for both GSU instances.
  - [x] Final projected outputs match a three-layer software reference.
  - [x] Full Windows XSim and Python regression pass with results documented.
