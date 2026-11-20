# Accelerator soft-reset and DMA recovery contract

Date: 2026-09-07
Target: PYNQ-Z1 / `xc7z020clg400-1` / 100 MHz FCLK0

## Hazard closed by this contract

The original full block design connected `soft_reset_request` through
`data_rst` to the accelerator, both AXI DMA instances, the AXI BRAM Controller,
and all four HP interconnects. A software reset could therefore assert reset on
an AXI endpoint or fabric while an accepted AR/R, MM2S, or S2MM transaction was
still outstanding.

The revised design makes the system reset and software reset scopes explicit:

- `PS/FCLK_RESET0_N -> control reset`: AXI-Lite control, AXI BRAM Controller,
  both AXI DMA instances, and HP0..HP3 interconnects.
- `PS/FCLK_RESET0_N or soft_reset_request -> data reset`: accelerator custom
  datapath only.

Thus a legal soft reset cannot asynchronously discard state inside the AXI
infrastructure. The accelerator's HP0 master must still be empty before its
custom datapath reset, and software must prove that all three DMA channels are
stopped.

## Hardware interlock

After software has stopped and observed all DMA channels idle, it writes
`CMD_RESET_QUIESCE` (command bit 5).  That persistent fence rejects new
START/mailbox ownership writes and prevents new framebuffer or spectrum AXIS
handshakes. Raising this fence before MM2S drains is forbidden: holding
`TREADY` low against an already asserted DMA `TVALID` could deadlock the stop
sequence. With DMA ownership returned and hardware admission stopped,
`accelerator_top.soft_reset_safe` requires all of the following:

- sparse planner, memory loader/abort drain, job controller, PE barrier,
  feature requests/responses, coefficient stream, context paths, and HP0
  AR/R channel are quiescent;
- mailbox adapter and both mailbox slot-state vectors are empty;
- global FSM, feature dispatcher, coefficient store, and DeepFilter engine are
  inactive;
- no output beat or input `TVALID` is present.

The full proof is sampled on two consecutive accelerator clock edges before a
registered `safe` indication reaches the AXI-Lite control plane.  This prevents
a stale one-cycle idle observation from authorizing reset and keeps the wide
quiescence cone out of the AXI-Lite command decode timing path.

The AXI-Lite control plane also requires no held START or mailbox ownership
command. A soft-reset request without the quiesce fence or while the registered
proof is low returns SLVERR and latches control error `0x07`.  START, mailbox,
or duplicate reset activity while fenced/pending returns SLVERR with error
`0x08`.  The fence deliberately has no software cancel command: a timeout is a
fail-closed recovery state requiring overlay reload or power cycle.

The control ABI adds:

| Offset | Name | Bits |
| --- | --- | --- |
| `0x0A4` | `IMAGE_VERSION` | `0x00040001` |
| `0x000` | `COMMAND` | bit 5 reset-quiesce, bit 2 soft reset, bit 1 abort |
| `0x0A8` | `RESET_STATUS` | `[31:16]` reset epoch, bit 3 quiesce, bit 2 pending, bit 1 active, bit 0 safe |

The live control plane increments the 16-bit epoch on the rising edge of the
data-plane reset and clears `pending`. Software waits for that change instead
of attempting to sample the short reset-active pulse.

## Required PS sequence

1. Stop accepting new application submissions and relinquish new buffer
   ownership.
2. Write accelerator `CMD_ABORT` once.
3. Confirm new application submissions remain blocked by the caller.
4. Clear `RS` for IO-DMA MM2S, IO-DMA S2MM, and spectrum-DMA MM2S.
5. Poll every channel for `Halted=1`, `Idle=1`, and no DMA error bits.
6. Write `CMD_RESET_QUIESCE` once, then poll `RESET_STATUS.safe=1`,
   `quiesce=1`, `active=0`, and `pending=0`.
7. Record the reset epoch, write `CMD_SOFT_RESET` once, and execute an ARM
   `dsb sy` barrier.
8. Wait for the epoch to change and pending to clear. Do not retry on timeout.
9. Recheck image/packet ABI, acknowledge DMA IRQ status, reinitialize DMA,
   flush the parameter image, execute the barrier, and reload the parameter
   cache before START.

`software/pynq/accelerator_bringup.py` implements steps 2 and 4 through the IRQ
acknowledgement portion of step 9 with injected MMIO/barrier objects. DMA
descriptor/buffer setup and parameter-cache reload remain application-owned.
The helper deliberately fails closed on a DMA error, DMA stop timeout,
custom-datapath quiesce timeout, control rejection, reset epoch timeout, ABI
mismatch, mailbox frame mismatch, or unaligned parameter buffer.

## Recovery boundary

If DMA cannot become Halted+Idle, the custom datapath never asserts safe, or
the epoch does not advance, software leaves DMA stopped and does not issue a
second reset. The board operator must retain the first-fault/status snapshot
and explicitly choose overlay reprogramming or a power cycle. A host mock PASS
does not prove AXI drain behavior or recovery on a physical board.
