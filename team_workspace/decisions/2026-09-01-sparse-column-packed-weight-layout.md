# Decision: source-major, 16-lane-packed weight image

- Date: 2026-09-01
- Status: accepted as the v3 image contract; RTL adapter not yet implemented
- Supersedes: no earlier logical decision. This refines
  `2026-08-31-sparse-weight-column-layout.md` with a physical byte order.

## Context

For `y = W x`, an active spike at source index `i` selects matrix column
`W[:, i]`. The current `parameters.bin` and v2 AXI image store each matrix in
C-order row-major form, so the 16 bytes needed by a 16-lane PE word are separated
by `input_size` bytes. A direct 16-lane response would therefore require a
strided gather instead of two adjacent 64-bit reads.

The team's phrase “read a selected weight row” is valid only after viewing the
matrix as transposed for storage: one stored source row is one mathematical
column of the original matrix.

## Decision

- Keep the logical request `{operator, matrix, source_index, row_tile}`.
- Store INT8 weight words in this physical order:

  ```text
  operator -> matrix -> source_index -> row_tile -> lane
  word_index = source_index * row_tiles + row_tile
  row_tiles = ceil(output_rows / 16)
  ```

- Each word is 16 bytes / 128 bits. Lane 0 occupies the lowest-address byte;
  invalid lanes in a final partial tile are zero.
- For a shared-weight GSU, store only the first `hidden_size` rows after verifying
  that the two gate halves in the source blob are byte-identical.
- Keep per-channel bias/requantization records and LUT data in separate,
  range-checked packed sections; they are not interleaved with every weight word.
- A 64-bit raw cache must use two consecutive local reads to assemble one
  128-bit weight response, or expose a wider/banked local port.

## Why source-major

All row tiles for one active source become a contiguous run. This is the layout
most directly compatible with active-index-driven DDR bursts or tile prefetch.
The current sparse RTL traverses row tile before active source; it can still use
the address formula for random BRAM reads, but it will not obtain the full DDR
burst advantage until the scheduler/prefetch adapter groups work by active
source or buffers the requested column.

## Consequences

- Logical weight reads become `active_count * row_tiles`; the exact reduction is
  proportional to activation sparsity.
- Repacking changes address order but does not compress matrix bytes. It removes
  duplicate GSU gate halves and optional pad bytes only.
- Loading an entire stage from DDR every time transfers the same stage bytes
  regardless of spike density. To reduce DDR traffic, the memory service must
  fetch selected source rows on demand or into a smaller active tile cache.
- First-GSU input matrices receive dense normalized INT8 features and therefore
  read every source row; their recurrent matrix still benefits from sparse
  spikes. Second-GSU input/recurrent and projection matrices are sparse-eligible.
- The real-blob host regression in
  `rtl/tests/test_sparse_parameter_reads.py` is the golden byte-order/reference
  test for the future v3 generator. It is not AXI timing or board evidence.
