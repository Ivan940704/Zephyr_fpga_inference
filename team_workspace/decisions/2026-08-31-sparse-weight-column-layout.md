# Decision: index-buffered column-major sparse execution

- Date: 2026-08-31
- Participants: Zephyr FPGA team, Codex
- Status: accepted for the standalone prototype
- Context:
  - Presentation pages 27 and 30 require inactive spike columns to skip both
    computation and weight access.
  - Page 29 includes an index buffer after spike generation, and the PE array is
    organized as 16 output-neuron lanes.
  - A 320x320 matrix therefore has 20 row tiles per weight column at 16 lanes.
- Decision:
  - Encode a binary spike vector into ascending active column indices once.
  - Store the active indices in a local index buffer.
  - Traverse row tiles outside and active indices inside so the same index list
    is reused for every output-neuron tile.
  - Define the logical weight-memory request as `{column_index, row_tile}`.
  - Return one packed word containing 16 signed INT8 weights, one per PE lane.
  - In spike mode, add the selected weights; multiplication by the binary value
    one is implicit, and zero-spike columns generate no request.
- Consequences:
  - Ideal weight reads are `active_count * ceil(rows / 16)` instead of
    `columns * ceil(rows / 16)`.
  - The memory/DMA task must preserve column/tile addressability when defining
    physical BRAM banking and DDR tile layout.
  - The current serial encoder proves function but is not the final performance
    design. A later task must evaluate a 16- or 32-bit-per-cycle encoder.
  - Physical BRAM organization, multiple outstanding reads, and overlap between
    encoding and compute remain open decisions.
- Supersedes: none
