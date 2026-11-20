import json
from pathlib import Path

import numpy as np
import pytest

from software.pynq.accelerator_inference import (
    COEFFICIENT_SCALES,
    DMA_ERROR_MASK,
    DMA_HALTED,
    DMA_IOC_IRQ,
    DMA_MM2S_DMACR,
    DMA_MM2S_DMASR,
    DMA_MM2S_ADDRESS,
    DMA_MM2S_LENGTH,
    DMA_S2MM_ADDRESS,
    DMA_S2MM_DMASR,
    DMA_S2MM_LENGTH,
    DMA_RESET,
    FREQ_CUTOFFS,
    MAGNITUDE_Q12_MAX,
    SB_PAYLOAD_BYTES,
    SPECTRUM_SCALES,
    AxiDmaSimpleChannel,
    InferenceError,
    MailboxIO,
    NativeLayerNormEngine,
    NativeDmaEngine,
    NativeOutputDequantizer,
    PynqAcceleratorRuntime,
    RuntimeParameters,
    build_subband_payload,
    dequantize_output,
    layer_norm_quantize,
    pack_spectrum,
    pack_magnitude_q12,
    prepare_fullband_input,
    REG_COMMAND,
    REG_INPUT_BUFFER_STATUS,
)
from software.pynq.build_inference_bundle import build
from software.pynq.build_native_layernorm import build as build_native_layernorm
from software.pynq.run_accelerator_inference import (
    StreamingIstftAccumulator,
    istft_centered,
    make_signal,
    read_pcm16,
    ratio_or_none,
    stft_centered,
    write_pcm16,
)


ROOT = Path(__file__).resolve().parents[2]


def test_empty_audio_interval_has_no_rtf_instead_of_dividing_by_zero():
    assert ratio_or_none(1.0, 0.0) is None
    assert ratio_or_none(1.0, -1.0) is None
    assert ratio_or_none(0.5, 0.25) == pytest.approx(2.0)


def runtime_parameters() -> RuntimeParameters:
    return RuntimeParameters(
        fb_weight=np.ones(64, dtype=np.float32),
        fb_bias=np.zeros(64, dtype=np.float32),
        fb_input_scale=0.25,
        fb_projection_scale=0.5,
        sb_weights=tuple(np.ones(width, dtype=np.float32) for width in (46, 94, 158)),
        sb_biases=tuple(np.zeros(width, dtype=np.float32) for width in (46, 94, 158)),
        sb_input_scales=(0.25, 0.25, 0.25),
    )


def test_layer_norm_uses_population_variance_and_ties_to_even():
    values = np.asarray([-1.0, 1.0], dtype=np.float32)
    actual = layer_norm_quantize(values, np.ones(2), np.zeros(2), 0.5, epsilon=0)
    assert actual.tolist() == [-2, 2]
    ties = layer_norm_quantize(
        np.asarray([-1.0, 1.0]), np.zeros(2), np.asarray([0.5, 1.5]), 1.0, epsilon=0
    )
    assert ties.tolist() == [0, 2]


def test_magnitude_q12_packet_is_little_endian_and_ties_to_even():
    magnitude = np.zeros(256, dtype=np.float64)
    magnitude[:6] = [0.0, 0.5 / 4096, 1.5 / 4096, 1.0, 2.0, MAGNITUDE_Q12_MAX]
    packet = pack_magnitude_q12(magnitude)
    assert packet.dtype == np.uint8
    assert packet.shape == (512,)
    assert packet.view("<i2")[:6].tolist() == [0, 0, 2, 4096, 8192, 32767]


@pytest.mark.parametrize(
    "bad_value, message",
    [(-1.0, "non-negative"), (np.nan, "finite"), (np.inf, "finite")],
)
def test_magnitude_q12_rejects_invalid_values(bad_value, message):
    magnitude = np.zeros(256, dtype=np.float64)
    magnitude[17] = bad_value
    with pytest.raises(InferenceError, match=message):
        pack_magnitude_q12(magnitude)


def test_magnitude_q12_saturates_overflow_and_rejects_wrong_shape():
    overflow = pack_magnitude_q12(
        np.full(256, MAGNITUDE_Q12_MAX + 1 / 4096)
    )
    assert np.all(overflow.view("<i2") == 32767)
    with pytest.raises(InferenceError, match="256 bins"):
        pack_magnitude_q12(np.zeros(255))


def test_subband_payload_has_fixed_context_order_and_size():
    params = runtime_parameters()
    magnitude = np.linspace(0.0, 2.0, 256, dtype=np.float32)
    projection = np.arange(-32, 32, dtype=np.int8)
    payload = build_subband_payload(magnitude, projection, params)
    assert payload.dtype == np.int8
    assert payload.shape == (SB_PAYLOAD_BYTES,)
    assert [184, 184 + 282, 782] == [4 * 46, 4 * 46 + 3 * 94, payload.size]
    assert np.any(payload[:184]) and np.any(payload[184:466]) and np.any(payload[466:])


def test_native_layernorm_matches_numpy_reference(tmp_path):
    library = tmp_path / "libzephyr_native_layernorm.so"
    metadata = build_native_layernorm(
        ROOT / "software/pynq/native_layernorm.c", library
    )
    assert metadata["library_bytes"] > 0
    rng = np.random.default_rng(0x5EED)
    parameters = RuntimeParameters(
        fb_weight=rng.normal(1.0, 0.2, 64).astype(np.float32),
        fb_bias=rng.normal(0.0, 0.1, 64).astype(np.float32),
        fb_input_scale=0.03125,
        fb_projection_scale=0.046875,
        sb_weights=tuple(
            rng.normal(1.0, 0.2, width).astype(np.float32)
            for width in (46, 94, 158)
        ),
        sb_biases=tuple(
            rng.normal(0.0, 0.1, width).astype(np.float32)
            for width in (46, 94, 158)
        ),
        sb_input_scales=(0.027, 0.033, 0.041),
    )
    engine = NativeLayerNormEngine(library, parameters)
    for _ in range(200):
        magnitude = rng.normal(0.0, 3.0, 256).astype(np.float32)
        projection = rng.integers(-127, 128, 64, dtype=np.int16).astype(np.int8)
        assert np.array_equal(
            engine.prepare_fullband_input(magnitude),
            prepare_fullband_input(magnitude, parameters),
        )
        assert np.array_equal(
            engine.build_subband_payload(magnitude, projection),
            build_subband_payload(magnitude, projection, parameters),
        )


def test_native_output_dequantization_matches_numpy_reference(tmp_path):
    library = tmp_path / "libzephyr_native_output.so"
    build_native_layernorm(ROOT / "software/pynq/native_layernorm.c", library)
    engine = NativeOutputDequantizer(library)
    rng = np.random.default_rng(0xD3C0DE)
    output = np.empty(256, dtype=np.complex64)
    for _ in range(200):
        accumulators = rng.integers(
            -(1 << 22), 1 << 22, size=(256, 2), dtype=np.int32
        )
        expected = dequantize_output(accumulators)
        actual = engine.dequantize(accumulators, output=output)
        assert actual is output
        assert np.array_equal(actual, expected)

    accumulator_batch = rng.integers(
        -(1 << 22), 1 << 22, size=(200, 256, 2), dtype=np.int32
    )
    expected_batch = np.stack(
        [dequantize_output(frame) for frame in accumulator_batch]
    )
    output_batch = np.empty((200, 256), dtype=np.complex64)
    actual_batch = engine.dequantize_batch(accumulator_batch, output=output_batch)
    assert actual_batch is output_batch
    assert np.array_equal(actual_batch, expected_batch)


def test_native_dma_engine_submits_and_waits_with_mapped_words(tmp_path):
    library = tmp_path / "libzephyr_native_dma.so"
    build_native_layernorm(ROOT / "software/pynq/native_layernorm.c", library)
    control = np.zeros(1024, dtype=np.uint32)
    io_dma = np.zeros(1024, dtype=np.uint32)
    spectrum_dma = np.zeros(1024, dtype=np.uint32)
    control[REG_INPUT_BUFFER_STATUS // 4] = 3
    io_dma[DMA_S2MM_DMASR // 4] = DMA_IOC_IRQ
    engine = NativeDmaEngine(library, control, io_dma, spectrum_dma)

    started = engine.submit_and_start(
        output_address=0x1000,
        fullband_address=0x2000,
        fullband_bytes=512,
        spectrum_address=0x3000,
        timeout_s=0.1,
    )

    assert started > 0
    assert int(control[REG_COMMAND // 4]) == 1
    assert int(io_dma[DMA_S2MM_ADDRESS // 4]) == 0x1000
    assert int(io_dma[DMA_S2MM_LENGTH // 4]) == 2048
    assert int(io_dma[DMA_MM2S_ADDRESS // 4]) == 0x2000
    assert int(io_dma[DMA_MM2S_LENGTH // 4]) == 512
    assert int(spectrum_dma[DMA_MM2S_ADDRESS // 4]) == 0x3000
    assert int(spectrum_dma[DMA_MM2S_LENGTH // 4]) == 512
    assert engine.wait_output(timeout_s=0.1) & DMA_IOC_IRQ


def test_spectrum_pack_and_output_dequantization_follow_band_scales():
    spectrum = np.empty(256, dtype=np.complex64)
    for band, (lower, upper) in enumerate(zip(FREQ_CUTOFFS[:-1], FREQ_CUTOFFS[1:])):
        spectrum[lower:upper] = SPECTRUM_SCALES[band] * (2 - 3j)
    packed = pack_spectrum(spectrum)
    assert packed[0::2].tolist() == [2] * 256
    assert packed[1::2].tolist() == [-3] * 256

    accumulators = np.ones((256, 2), dtype=np.int32)
    output = dequantize_output(accumulators)
    for band, (lower, upper) in enumerate(zip(FREQ_CUTOFFS[:-1], FREQ_CUTOFFS[1:])):
        expected = SPECTRUM_SCALES[band] * COEFFICIENT_SCALES[band]
        assert np.allclose(output[lower:upper].real, expected)
        assert np.allclose(output[lower:upper].imag, expected)


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class FakeDmaMmio:
    def __init__(self, *, error=0):
        self.registers = {DMA_MM2S_DMACR: 0, DMA_MM2S_DMASR: DMA_HALTED | error}
        self.error = error
        self.writes = []

    def write(self, offset, value):
        self.writes.append((offset, value))
        if offset == DMA_MM2S_DMACR:
            self.registers[offset] = 0 if value & DMA_RESET else value
            if value & 1:
                self.registers[DMA_MM2S_DMASR] &= ~DMA_HALTED
        elif offset == DMA_MM2S_DMASR:
            self.registers[offset] &= ~value
        else:
            self.registers[offset] = value

    def read(self, offset):
        return self.registers.get(offset, 0)


class FakeMailboxMmio:
    def __init__(self):
        self.array = np.zeros(1024, dtype=np.uint32)
        self.reads = []
        self.writes = []

    def read(self, offset):
        self.reads.append(offset)
        return int(self.array[offset // 4])

    def write(self, offset, value):
        self.writes.append((offset, value))
        self.array[offset // 4] = value


def test_bulk_mailbox_is_byte_identical_to_scalar_reference():
    projection = np.arange(64, dtype=np.uint8)
    payload = np.arange(SB_PAYLOAD_BYTES, dtype=np.uint16).astype(np.uint8).view(np.int8)
    results = {}
    snapshots = {}
    call_counts = {}
    for mode in ("scalar", "bulk"):
        mmio = FakeMailboxMmio()
        mmio.array[:16] = np.frombuffer(projection.tobytes(), dtype="<u4")
        accessor = MailboxIO(mmio, mode)
        results[mode] = accessor.read_fullband_projection(0)
        accessor.write_subbands(1, payload)
        start = 0x800 // 4
        snapshots[mode] = mmio.array[start : start + 196].copy()
        call_counts[mode] = (len(mmio.reads), len(mmio.writes))
    assert np.array_equal(results["scalar"].view(np.uint8), projection)
    assert np.array_equal(results["bulk"], results["scalar"])
    assert np.array_equal(snapshots["bulk"], snapshots["scalar"])
    assert int(snapshots["bulk"][-1]) >> 16 == 0
    assert call_counts["scalar"] == (17, 196)
    assert call_counts["bulk"] == (0, 0)


def test_bulk_mailbox_requires_a_4k_word_mapping():
    mmio = FakeMailboxMmio()
    mmio.array = np.zeros(8, dtype=np.uint32)
    with pytest.raises(InferenceError, match="at least 4 KiB"):
        MailboxIO(mmio, "bulk")


def test_simple_dma_reset_submit_and_completion():
    clock = FakeClock()
    mmio = FakeDmaMmio()
    channel = AxiDmaSimpleChannel(
        mmio, "mm2s", monotonic=clock.monotonic, sleep=clock.sleep
    )
    channel.reset()
    channel.submit(0x1000, 64)
    mmio.registers[DMA_MM2S_DMASR] |= DMA_IOC_IRQ
    assert channel.wait() & DMA_IOC_IRQ
    with pytest.raises(InferenceError, match="aligned"):
        channel.submit(0x1001, 64)


def test_simple_dma_start_does_not_reset_shared_core():
    clock = FakeClock()
    mmio = FakeDmaMmio()
    channel = AxiDmaSimpleChannel(
        mmio, "mm2s", monotonic=clock.monotonic, sleep=clock.sleep
    )
    channel.start()
    assert (DMA_MM2S_DMACR, DMA_RESET) not in mmio.writes


def test_simple_dma_fails_closed_on_error():
    clock = FakeClock()
    mmio = FakeDmaMmio(error=DMA_ERROR_MASK & 0x10)
    channel = AxiDmaSimpleChannel(
        mmio, "mm2s", monotonic=clock.monotonic, sleep=clock.sleep
    )
    channel.reset()
    mmio.registers[DMA_MM2S_DMASR] |= DMA_ERROR_MASK & 0x10
    with pytest.raises(InferenceError, match="pre-submit error"):
        channel.submit(0x1000, 64)


def test_fast_dma_submit_uses_only_address_and_length_writes():
    mmio = FakeDmaMmio()
    channel = AxiDmaSimpleChannel(mmio, "mm2s", register_io_mode="scalar")
    channel.submit_fast(0x1000, 512)
    assert mmio.writes == [(DMA_MM2S_ADDRESS, 0x1000), (DMA_MM2S_LENGTH, 512)]


def test_dma_bulk_register_io_bypasses_scalar_python_calls():
    class BulkOnlyMmio:
        def __init__(self):
            self.array = np.zeros(1024, dtype=np.uint32)

        def read(self, _offset):
            pytest.fail("bulk register path called scalar read")

        def write(self, _offset, _value):
            pytest.fail("bulk register path called scalar write")

    mmio = BulkOnlyMmio()
    channel = AxiDmaSimpleChannel(mmio, "mm2s", register_io_mode="bulk")
    channel.submit_fast(0x2000, 1024)
    assert int(mmio.array[DMA_MM2S_ADDRESS // 4]) == 0x2000
    assert int(mmio.array[DMA_MM2S_LENGTH // 4]) == 1024


class FakeContiguousBuffer:
    def __init__(self, size, address):
        self.array = np.zeros(size, dtype=np.uint8)
        self.physical_address = address
        self.flush_count = 0

    @property
    def size(self):
        return self.array.size

    def __setitem__(self, key, value):
        self.array[key] = value

    def flush(self):
        self.flush_count += 1


def test_prepare_frame_uses_alternating_dma_buffers_and_flushes_packets():
    runtime = object.__new__(PynqAcceleratorRuntime)
    runtime.frontend_mode = "pl"
    runtime.layernorm_engine = None
    runtime.parameters = runtime_parameters()
    runtime.conservative_output_cache = True
    runtime.fb_buffers = (
        FakeContiguousBuffer(512, 0x1000),
        FakeContiguousBuffer(512, 0x2000),
    )
    runtime.spectrum_buffers = (
        FakeContiguousBuffer(512, 0x3000),
        FakeContiguousBuffer(512, 0x4000),
    )
    runtime.output_buffers = (
        FakeContiguousBuffer(2048, 0x5000),
        FakeContiguousBuffer(2048, 0x6000),
    )
    magnitude = np.linspace(0.0, 2.0, 256, dtype=np.float32)
    spectrum = np.ones(256, dtype=np.complex64) * (2 - 3j)

    even = runtime.prepare_frame(magnitude, spectrum, frame_id=18)
    odd = runtime.prepare_frame(magnitude, spectrum, frame_id=19)

    assert (even.frame_id, even.slot) == (18, 0)
    assert (odd.frame_id, odd.slot) == (19, 1)
    assert runtime.fb_buffers[0].flush_count == 1
    assert runtime.fb_buffers[1].flush_count == 1
    assert runtime.spectrum_buffers[0].flush_count == 1
    assert runtime.spectrum_buffers[1].flush_count == 1
    assert runtime.output_buffers[0].flush_count == 1
    assert runtime.output_buffers[1].flush_count == 1
    assert np.array_equal(runtime.fb_buffers[0].array, pack_magnitude_q12(magnitude))
    assert np.array_equal(runtime.spectrum_buffers[1].array.view(np.int8), odd.spectrum_q)


def test_prepare_frame_uses_software_sequence_without_mmio_read():
    runtime = object.__new__(PynqAcceleratorRuntime)
    runtime.frontend_mode = "pl"
    runtime.layernorm_engine = None
    runtime.parameters = runtime_parameters()
    runtime.conservative_output_cache = True
    runtime.expected_frame_id = 18
    runtime._read = lambda _offset: pytest.fail("fast path performed an MMIO read")
    runtime.fb_buffers = (
        FakeContiguousBuffer(512, 0x1000),
        FakeContiguousBuffer(512, 0x2000),
    )
    runtime.spectrum_buffers = (
        FakeContiguousBuffer(512, 0x3000),
        FakeContiguousBuffer(512, 0x4000),
    )
    runtime.output_buffers = (
        FakeContiguousBuffer(2048, 0x5000),
        FakeContiguousBuffer(2048, 0x6000),
    )

    prepared = runtime.prepare_frame(
        np.linspace(0.0, 2.0, 256, dtype=np.float32),
        np.ones(256, dtype=np.complex64) * (2 - 3j),
    )

    assert (prepared.frame_id, prepared.slot) == (18, 0)


def test_prepare_packed_frame_is_byte_exact_without_requantization():
    runtime = object.__new__(PynqAcceleratorRuntime)
    runtime.frontend_mode = "pl"
    runtime.conservative_output_cache = False
    runtime.expected_frame_id = 9
    runtime.fb_buffers = (
        FakeContiguousBuffer(512, 0x1000),
        FakeContiguousBuffer(512, 0x2000),
    )
    runtime.spectrum_buffers = (
        FakeContiguousBuffer(512, 0x3000),
        FakeContiguousBuffer(512, 0x4000),
    )
    runtime.output_buffers = (
        FakeContiguousBuffer(2048, 0x5000),
        FakeContiguousBuffer(2048, 0x6000),
    )
    magnitude_q12 = np.arange(512, dtype=np.uint16).astype(np.uint8)
    spectrum_q = np.arange(512, dtype=np.uint16).astype(np.uint8).view(np.int8)
    prepared = runtime.prepare_packed_frame(magnitude_q12, spectrum_q)
    assert (prepared.frame_id, prepared.slot) == (9, 1)
    assert np.array_equal(runtime.fb_buffers[1].array, magnitude_q12)
    assert np.array_equal(runtime.spectrum_buffers[1].array, spectrum_q.view(np.uint8))
    assert prepared.spectrum_q is spectrum_q


def test_wait_for_fast_path_does_not_read_fault_registers_on_success():
    runtime = object.__new__(PynqAcceleratorRuntime)
    runtime._raise_if_fault = lambda _context: pytest.fail(
        "successful fast path read fault registers"
    )

    assert runtime._wait_for(
        lambda: 42,
        1.0,
        "fast completion",
        check_faults=False,
    ) == 42


def test_runtime_bundle_extracts_real_manifest(tmp_path):
    output = tmp_path / "runtime.npz"
    build(ROOT / "upstream/parameters/manifest.json", output)
    params = RuntimeParameters.load(output)
    params.validate()
    assert params.fb_input_scale == pytest.approx(0.058943857358196586)
    assert params.fb_projection_scale == pytest.approx(0.03495301599577656)
    assert params.sb_input_scales == pytest.approx(
        (0.03978675181471457, 0.030964057276568074, 0.020789506867175966)
    )


def test_numpy_stft_istft_round_trip():
    _, noisy = make_signal(4096)
    rebuilt = istft_centered(stft_centered(noisy), noisy.size)
    assert np.max(np.abs(rebuilt - noisy)) < 1e-6


def test_streaming_istft_is_equivalent_to_batch_path():
    _, noisy = make_signal(4096)
    spectrum = stft_centered(noisy)
    expected = istft_centered(spectrum, noisy.size)
    streaming = StreamingIstftAccumulator(spectrum.shape[1])
    for frame in range(spectrum.shape[1]):
        streaming.add(spectrum[:, frame])
    actual = streaming.finish(noisy.size)
    assert np.array_equal(actual, expected)


def test_pcm16_wav_round_trip_uses_fixed_runtime_format(tmp_path):
    source = np.asarray([-1.0, -0.25, 0.0, 0.25, 0.999], dtype=np.float32)
    path = tmp_path / "runtime.wav"
    write_pcm16(path, source)
    actual = read_pcm16(path)
    assert actual.shape == source.shape
    assert np.max(np.abs(actual - source)) <= 2.0 / 32768.0


def test_runtime_constants_match_manifest_and_layout():
    manifest = json.loads((ROOT / "upstream/parameters/manifest.json").read_text())
    deepfilter = json.loads((ROOT / "upstream/parameters/deepfilter.json").read_text())
    assert tuple(manifest["model"]["args"]["freq_cutoffs"]) == FREQ_CUTOFFS
    assert tuple(float(deepfilter["bands"][str(order)]["spectrum_scale"]) for order in (5, 3, 1)) == pytest.approx(SPECTRUM_SCALES)
