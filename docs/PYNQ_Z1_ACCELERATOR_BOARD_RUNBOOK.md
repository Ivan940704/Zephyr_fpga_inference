# PYNQ-Z1 accelerator first-board runbook

Date: 2026-09-08

## Current authorization state

**PROFILING V2 STAGE 2 READ-ONLY ABI PASS; STAGE 3 RUNTIME BLOCKED.** The full
implementation and artifact gates pass for hardware baseline `0d914230`.
Matching `zephyr_full.bit`/`.hwh` artifacts were hash-pinned, then the BIT was
programmed through the explicitly identified Digilent JTAG target
`003017B78476A`. Configuration DONE/CRC/IDCODE checks and read-only accelerator
ABI checks passed for image `0x00040002`.

The fresh JTAG snapshot did not capture a board revision, PYNQ/kernel version,
or a network/OS endpoint. APU/AHB-AP0 reads observed zero accelerator status,
control error, and profiling status and performed no MMIO write. DMA state was
not read in the v2 smoke, so the fail-closed reset prerequisite is not proven;
no reset, buffer allocation, DMA traffic, profiling enable, or START was
attempted.

## Stage 0: release gates

Before copying an artifact to a board, require all of the following in one
release record:

- target `xc7z020clg400-1`, Digilent PYNQ-Z1 preset, FCLK0 100 MHz;
- standard setup WNS at least `+0.250 ns`, TNS 0, and no setup failures;
- 50 ps hold guardband WHS at least 0 and raw hold margin at least 50 ps;
- zero routing errors/unrouted nets, clockless registers, unconstrained
  internal endpoints, timing loops, DRC errors, and DRC critical warnings;
- all tracked resource classes below 80 percent;
- BIT and HWH produced from the same clean build and sharing one basename;
- SHA-256 manifest binding the artifacts, reports, source commit, v4 parameter
  image, part, clock, address map, and image ABI `0x00040002`;
- a named board endpoint confirmed by the operator.

If any item is missing, stop here.  A positive standard WNS alone is not a
release authorization.

## Stage 1: artifact and board identity

On the PYNQ target, enter the release directory and verify the release-provided
checksum file before importing PYNQ or touching PL:

```bash
sha256sum -c SHA256SUMS
```

Confirm the expected board model/revision and capture the kernel/PYNQ versions,
artifact checksum output, power-cycle time, and the physical/JTAG or network
endpoint selected by the operator.  BIT/HWH basenames and their manifest
entries must match exactly.

Compile the already-reviewed ARM completion barrier locally on the board:

```bash
cc -O2 -fPIC -shared \
  -o software/pynq/libzephyr_arm_barrier.so \
  software/pynq/arm_barrier.c
```

Compilation on a non-ARM host is intentionally rejected by the source.

## Stage 2: program and read-only ABI smoke

Acquired on 2026-09-08 through Vivado/XSCT JTAG. The programmed BIT SHA-256 is
`52d8f0296965068716d1b2a50966b5423f2abd92e8589e2e3fa372893097f289`;
internal DONE, DONE pin and IR DONE were all `1`, with CRC/IDCODE/security
errors all `0`. Physical AHB-AP0 reads returned the expected three identity
values below, with zero writes.

Only after Stage 0 and Stage 1 pass, program the named artifact using its
matching HWH.  Immediately perform read-only identity checks before allocating
or starting DMA:

```python
from pathlib import Path
from pynq import Overlay
from software.pynq.accelerator_bringup import AcceleratorBringupDriver
from software.pynq.parameter_bram_bringup import load_arm_dsb_sy

release = Path("/absolute/path/to/verified/release")
overlay = Overlay(str(release / "zephyr_full.bit"), download=True)
driver = AcceleratorBringupDriver.from_pynq(barrier=load_arm_dsb_sy())
print(driver.verify_identity())
```

The expected identity is:

| Register | Expected |
| --- | ---: |
| `IMAGE_VERSION` (`0x0A4`) | `0x00040002` |
| `PACKET_BYTES_0` (`0x038`) | FB 64 B, spectrum 512 B |
| `PACKET_BYTES_1` (`0x03C`) | output 2,048 B |

Any mismatch blocks DMA, mailbox writes, reset, and START.  Save the raw values
and reprogram/power-cycle only by explicit operator decision.

## Stage 3: DMA and reset smoke

Current v2 state: **NOT ACQUIRED**. Historical v1 bring-up once observed
Halted=1 but Idle=0 on IO-MM2S, IO-S2MM, and spectrum-MM2S; that observation
cannot be reused for the newly programmed image. The sequence below must not
start until a PYNQ/PS runtime endpoint is captured and every prerequisite in
the driver can be observed safely.

Application submission must remain disabled for the entire recovery sequence.
The reviewed helper enforces this hardware/software order:

1. issue accelerator ABORT once;
2. clear RS on IO-MM2S, IO-S2MM, and spectrum-MM2S;
3. require Halted+Idle and zero DMA error bits on all three channels;
4. raise the persistent hardware reset-quiesce fence;
5. require quiesce+safe with active/pending clear;
6. issue one custom-datapath reset and execute `dsb sy`;
7. require reset epoch advancement, recheck ABI, and acknowledge DMA IRQs.

The invocation is deliberately single-use:

```python
evidence = driver.safe_soft_reset(timeout_s=1.0)
print(evidence)
```

On a timeout or DMA/control error, do not retry reset with the same driver or
release new buffers.  Capture DMA control/status, `RESET_STATUS`,
`CONTROL_ERROR`, IRQ status, and first-fault registers; then choose overlay
reprogramming or a power cycle explicitly.

The capture helper is read-only and is safe to call before and after a failed
attempt:

```python
print(driver.diagnostic_snapshot())
```

## Stage 4: traffic and numerical gates

These gates are still **NOT ACQUIRED** and must be run in order:

1. destructive-free PS DDR memory test, followed by aligned single-channel DMA
   transfer tests for IO-MM2S, IO-S2MM, and spectrum-MM2S;
2. simultaneous DMA stress with cache flush/invalidate and the ARM barrier;
3. mailbox claim/write/commit/read/release ordering for both slots, including
   wrong-frame rejection and timeout recovery;
4. one frozen input frame with a repository-tracked end-to-end golden output,
   compared byte-for-byte/INT32-for-INT32 before any audio-quality claim;
5. multi-frame state evolution, abort/reset/reload, and parameter-cache reload;
6. only then latency, sustained bandwidth, RTF, power, and audio measurements.

The repository now has a 33-frame NumPy-validated historical v1 end-to-end
golden used by the automated v2 experiment matrix. It is a required boundary
comparison input, not evidence that v2 has run; Stage 4 must still acquire and
compare every v2 boundary/output before any optimization is promoted.

## Required board evidence record

Preserve timestamps, artifact/source/image SHA-256, board revision, PYNQ/kernel
versions, raw register snapshots, physical buffer addresses and alignment,
cache operations, DMA lengths/status, mailbox frame/slot ownership, output
hash/comparison count, cycles/latency, and cleanup result.  Label an interrupted
run FAIL or BLOCKED; never upgrade a host mock or implementation report to a
board PASS.
