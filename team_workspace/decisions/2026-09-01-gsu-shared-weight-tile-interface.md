# Decision: shared-weight GSU tile interface

- Date: 2026-09-01
- Status: accepted for the fullband prototype
- Context:
  - Both fullband GSU cells in `model_config.json` use
    `shared_weights=true`.
  - The exported forget/cell halves of `weight_ih_q` and `weight_hh_q` are
    byte-identical, while their bias and requantization tensors differ.
  - PYNQ-Z1 cannot keep all full model weights on chip, so the GSU arithmetic
    must not own a fixed monolithic weight memory.
- Decision:
  - One weight response contains 16 INT8 weights for one output-neuron tile.
  - The address is `{matrix_kind, row_tile, source_index}`, where matrix kind
    selects input or recurrent weights.
  - One shared MAC accumulator feeds both gate postprocess paths.
  - One parameter response supplies the separate gate and state parameters for
    the same 16-neuron tile.
  - Prior hidden spikes are encoded once per frame and reused over all tiles.
  - Fullband layer 1 uses dense INT8 input mode; layer 2 uses binary sparse
    input mode through the same parameterized RTL.
- Consequences:
  - The duplicated second gate weight half in `parameters.bin` need not be read
    by this hardware path.
  - `memory.v` remains free to back the interface with BRAM tiles or DDR DMA.
  - A non-shared-weight GSU checkpoint would require a second gate-weight MAC
    path and is outside this interface contract.
