# Experimental shared Q12 LayerNorm engine

This leaf implements the frozen signed-Q12/Q24/Q20 LayerNorm contract for
vectors of length 2 through 158. It is intentionally outside the frozen
`rtl/pe_array/baseline/v1` hierarchy until production integration is verified.

Run `rtl/scripts/Run-Realtime-LayerNorm-Vivado.cmd` from a Windows shell with
Vivado 2018.3 available. The wrapper regenerates deterministic oracle vectors,
runs bit-exact XSim with randomized stalls, performs OOC place-and-route at
125 MHz, and copies reports to
`rtl/reports/realtime_layernorm_q12_125mhz/`.

Passing this leaf gate does not prove full-system timing or board latency. A
matching production coordinator, parameter storage, BIT/HWH, runtime, and the
frozen five-file board test are still required.

The model-specific `layernorm_parameter_rom_q12` is generated from the frozen
`upstream/parameters/manifest.json` and checksum-verified parameter blob. It
contains 362 packed Q12 gamma/beta pairs for the four unique profiles. The
same generator also emits the 255-entry fullband projection dequantization map
and the 782-entry subband source-index map needed by the coordinator. Regenerate
with:

```text
python3 software/host/generate_layernorm_parameter_rom.py \
  --manifest upstream/parameters/manifest.json \
  --output-dir rtl/experiments/realtime_layernorm/data
```

The ROM gate checks all 362 entries plus invalid-index behavior and output
backpressure. Its 125 MHz OOC implementation is recorded separately under
`rtl/reports/realtime_layernorm_parameter_rom_q12_125mhz`; it is not a
full-system or board latency result.
