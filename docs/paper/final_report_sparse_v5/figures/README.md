# Hardware architecture figure

`zephyr_sparse_v5_hardware_modules.svg` is the editable vector source and
`zephyr_sparse_v5_hardware_modules.png` is the rendered 2200 x 1320 paper and
presentation copy.

The module boundaries and connections were traced from production RTL:

- `rtl/top/accelerator_system_top.v`: PS/PL control, parameter AXI, three DMA
  streams, profiling counters and the accelerator wrapper.
- `rtl/top/accelerator_top.v`: global scheduler, PL LayerNorm, feature
  dispatcher, PE/memory subsystem, coefficient store and DeepFilter engine.
- `rtl/memory/sequential_v5_pe_memory_subsystem.v`: recurrent context, sparse
  union planning, memory service, PE job controller and 32-lane PE datapath.
- `rtl/experiments/realtime_layernorm/realtime_layernorm_coordinator.v`:
  LayerNorm frame buffers, Q12 normalization engine and gamma/beta ROM.

The figure intentionally collapses bit-level ready/valid nets, counters,
timeouts and fault fan-in. Solid blue arrows are feature/coefficient streams,
orange arrows are DDR parameter traffic, dashed grey arrows are control or
monitoring, and green arrows are recurrent state or sparse active-list flow.
