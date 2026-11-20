import pytest

from software.pynq.accelerator_profile import (
    PROFILE_SCHEMA,
    PROFILE_STATUS_BUSY,
    PROFILE_STATUS_ENABLE,
    PROFILE_STATUS_VALID,
    PROFILE_WORD_COUNT,
    REG_PROFILE_BASE,
    REG_PROFILE_STATUS,
    ProfileError,
    decode_profile_words,
    profile_control_value,
    read_profile_snapshot,
    read_profile_snapshot_words,
)
from software.pynq.run_accelerator_inference import summarize_hardware_profiles


def set_u64(words, index, value):
    words[index] = value & 0xFFFF_FFFF
    words[index + 1] = (value >> 32) & 0xFFFF_FFFF


def example_words():
    words = [0] * PROFILE_WORD_COUNT
    words[0] = PROFILE_SCHEMA
    words[1] = PROFILE_STATUS_ENABLE | PROFILE_STATUS_VALID | (1 << 4)
    words[2] = (2 << 21) | (5 << 17) | 7
    words[3] = 11
    set_u64(words, 4, 4)
    set_u64(words, 6, 4)
    for state in (1, 2, 3, 5):
        set_u64(words, 8 + 2 * state, 1)
    set_u64(words, 120 + 2 * 17, 100)
    set_u64(words, 120 + 2 * 20, 200)
    set_u64(words, 120 + 2 * 21, 1600)
    set_u64(words, 120 + 2 * 22, 1600)
    set_u64(words, 120 + 2 * 23, 64)
    set_u64(words, 120 + 2 * 24, 192)
    return words


def test_profile_decoder_enforces_cycle_conservation_and_derives_sparsity():
    decoded = decode_profile_words(example_words())
    assert decoded["frame_id"] == 7
    assert decoded["end_state"] == 5
    assert decoded["compute_owner"] == 2
    assert decoded["sparse"] is True
    assert decoded["pl_latency_s"] == pytest.approx(40e-9)
    assert decoded["state_cycles"]["wait_ps"] == 1
    assert decoded["counters"]["weight_requests"] == 100
    assert decoded["derived"]["request_sparsity"] == pytest.approx(0.5)
    assert decoded["derived"]["mac_skip_fraction"] == pytest.approx(0.5)
    assert decoded["derived"]["parameter_byte_savings_fraction"] == pytest.approx(0.75)


def test_profile_decoder_rejects_invalid_or_nonconserving_snapshot():
    words = example_words()
    words[1] &= ~PROFILE_STATUS_VALID
    with pytest.raises(ProfileError, match="not valid"):
        decode_profile_words(words)
    words = example_words()
    set_u64(words, 6, 5)
    with pytest.raises(ProfileError, match="cycle conservation"):
        decode_profile_words(words)


def test_profile_reader_checks_status_sequence_and_expected_frame():
    words = example_words()

    def read_word(address):
        if address == REG_PROFILE_STATUS:
            return PROFILE_STATUS_ENABLE | PROFILE_STATUS_VALID
        return words[(address - REG_PROFILE_BASE) // 4]

    decoded = read_profile_snapshot(read_word, expected_frame_id=7)
    assert decoded["snapshot_sequence"] == 11
    with pytest.raises(ProfileError, match="frame mismatch"):
        read_profile_snapshot(read_word, expected_frame_id=8)


def test_profile_reader_bulk_copies_once_and_can_defer_decode():
    words = example_words()
    scalar_reads = []
    bulk_reads = []

    def read_word(address):
        scalar_reads.append(address)
        if address == REG_PROFILE_STATUS:
            return PROFILE_STATUS_ENABLE | PROFILE_STATUS_VALID
        return words[(address - REG_PROFILE_BASE) // 4]

    def read_words(address, count):
        bulk_reads.append((address, count))
        return words[:count]

    raw = read_profile_snapshot_words(
        read_word,
        read_words=read_words,
        expected_frame_id=7,
    )
    assert raw == tuple(words)
    assert bulk_reads == [(REG_PROFILE_BASE, PROFILE_WORD_COUNT)]
    assert len(scalar_reads) == 5
    assert decode_profile_words(list(raw))["frame_cycles"] == 4


def test_profile_reader_waits_for_serialized_snapshot_completion():
    words = example_words()
    status_reads = 0

    def read_word(address):
        nonlocal status_reads
        if address == REG_PROFILE_STATUS:
            status_reads += 1
            if status_reads <= 2:
                return PROFILE_STATUS_ENABLE | PROFILE_STATUS_BUSY
            return PROFILE_STATUS_ENABLE | PROFILE_STATUS_VALID
        return words[(address - REG_PROFILE_BASE) // 4]

    decoded = read_profile_snapshot(
        read_word,
        expected_frame_id=7,
        ready_timeout_s=0.010,
        poll_interval_s=0.0,
    )
    assert decoded["snapshot_sequence"] == 11
    assert status_reads >= 4


def test_profile_reader_rejects_torn_sequence_and_control_encoding_is_exact():
    words = example_words()
    sequence_reads = 0

    def torn_read(address):
        nonlocal sequence_reads
        if address == REG_PROFILE_STATUS:
            return PROFILE_STATUS_ENABLE | PROFILE_STATUS_VALID
        if address == REG_PROFILE_BASE + 12:
            sequence_reads += 1
            return 11 if sequence_reads < 3 else 12
        return words[(address - REG_PROFILE_BASE) // 4]

    with pytest.raises(ProfileError, match="sequence changed"):
        read_profile_snapshot(torn_read, retries=1)
    assert profile_control_value(enable=True, clear=True, snapshot=True) == 0x7
    assert profile_control_value(enable=False) == 0


def test_hardware_profile_aggregation_preserves_cycle_and_sparsity_totals():
    first = decode_profile_words(example_words())
    second = decode_profile_words(example_words())
    summary = summarize_hardware_profiles([first, second])
    assert summary["frames"] == 2
    assert summary["cycle_conservation_all_frames"] is True
    assert summary["state_cycle_totals"]["wait_ps"] == 2
    assert summary["counter_totals"]["weight_requests"] == 200
    assert summary["request_sparsity"] == pytest.approx(0.5)
    assert summary["parameter_byte_savings_fraction"] == pytest.approx(0.75)
