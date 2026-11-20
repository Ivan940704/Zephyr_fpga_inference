# PE array and Sequential v4 memory freeze

Status: frozen for FSM and accelerator-top integration

Freeze label: `sequential-v4-pe-memory-v1`

Frozen implementation checkpoint: `67b515757364fd9c9cabb404dcae303a45d9ea17`

Freeze branch base: `4363a88`

## Boundary

The byte identity of the following production inputs is frozen:

- the complete formal PE archive under `rtl/pe_array/baseline/v1/`;
- the Sequential v4 memory, service, recurrent-context, PE-job-controller, and
  subsystem sources listed in `PE_MEMORY_V4_SHA256SUMS`;
- `layernorm_mailbox.v`, the v4 parameter image/layout/golden artifacts, the
  generated mapping/readback tables, and the subsystem OOC constraint listed
  in that checksum file.

`rtl/control/fsm.v` is deliberately excluded.  The FSM and future accelerator
top glue may change while integrating against this frozen boundary.  A change
to any frozen byte requires a new reviewed freeze label and a new checksum
manifest; it must not be folded silently into this version.

This freeze is a source-control and checksum boundary.  It does not claim that
a production accelerator top, v4 bitstream, PS driver, or PYNQ-Z1 inference run
already exists.

## Verification

From the repository root in WSL:

```bash
(cd rtl/pe_array/baseline/v1 && sha256sum -c SHA256SUMS)
sha256sum -c docs/frozen/PE_MEMORY_V4_SHA256SUMS
```

Initial verification on 2026-09-05:

- PE archive: 158/158 entries `OK`;
- PE/memory production boundary: 25/25 entries `OK`.

Git protections remain the normal review process: do not edit these paths on
an FSM/top branch, and review `git diff --name-only` before committing.  The
checksums are the authoritative byte-level guard.
