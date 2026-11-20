#!/usr/bin/env python3
"""Dependency-free checks for the arithmetic vectors used by the Verilog TBs.

These checks validate the expected values independently of the HDL simulator.
They do not replace compiling and running the self-checking Verilog testbenches.
"""

from __future__ import annotations

import unittest
from pathlib import Path


def round_shift(value: int, shift: int) -> int:
    if shift == 0:
        return value
    rounded = (abs(value) + (1 << (shift - 1))) >> shift
    return -rounded if value < 0 else rounded


def requant(value: int, multiplier: int, shift: int) -> int:
    return round_shift(value * multiplier, shift)


def sat_int8(value: int) -> tuple[int, bool]:
    clipped = value < -127 or value > 127
    return max(-127, min(127, value)), clipped


def gate_postprocess(
    input_acc: int,
    recurrent_acc: int,
    input_multiplier: int,
    input_shift: int,
    recurrent_multiplier: int,
    recurrent_shift: int,
    bias: int,
    guard_bits: int = 8,
) -> tuple[int, bool]:
    total = (
        requant(input_acc, input_multiplier, input_shift)
        + requant(recurrent_acc, recurrent_multiplier, recurrent_shift)
        + bias
    )
    return sat_int8(round_shift(total, guard_bits))


def state_update(
    forget: int,
    previous: int,
    cellgate: int,
    previous_multiplier: int,
    previous_shift: int,
    cellgate_multiplier: int,
    cellgate_shift: int,
    bn_multiplier: int,
    bn_shift: int,
    bn_bias: int,
    denominator: int = 255,
    guard_bits: int = 8,
) -> tuple[int, int, int, bool, bool]:
    previous_term = forget * previous
    cellgate_term = (denominator - forget) * cellgate
    state_pre_unclamped = round_shift(
        requant(previous_term, previous_multiplier, previous_shift)
        + requant(cellgate_term, cellgate_multiplier, cellgate_shift),
        guard_bits,
    )
    state_pre, pre_clipped = sat_int8(state_pre_unclamped)
    state_unclamped = round_shift(
        requant(state_pre, bn_multiplier, bn_shift) + bn_bias,
        guard_bits,
    )
    state, state_clipped = sat_int8(state_unclamped)
    return state_pre, state, int(state >= 0), pre_clipped, state_clipped


def shared_gsu_test_frame(
    input_values: list[int], previous_spikes: list[int], previous_states: list[int]
) -> tuple[list[int], list[int], list[int], list[int], int, int]:
    """Independent model for the deterministic vectors in tb_gsu_layer."""
    hidden_size = len(previous_spikes)
    lanes = 4
    input_weights = [
        [((neuron * 7 + index * 5 + 3) % 15) - 7 for index in range(len(input_values))]
        for neuron in range(hidden_size)
    ]
    recurrent_weights = [
        [((neuron * 11 + index * 3 + 5) % 13) - 6 for index in range(hidden_size)]
        for neuron in range(hidden_size)
    ]
    sigmoid = list(range(255))
    forget_values: list[int] = []
    cellgate_values: list[int] = []
    state_values: list[int] = []
    spike_values: list[int] = []

    for neuron in range(hidden_size):
        input_acc = sum(
            value * weight
            for value, weight in zip(input_values, input_weights[neuron])
        )
        recurrent_acc = sum(
            recurrent_weights[neuron][index]
            for index, spike in enumerate(previous_spikes)
            if spike
        )
        forget_unclamped = round_shift(
            requant(input_acc, 1 << 30, 22 + neuron % 2)
            + requant(recurrent_acc, 1 << 30, 22)
            + (neuron * 18 - 60) * 256,
            8,
        )
        cellgate_unclamped = round_shift(
            requant(input_acc, 1 << 30, 22)
            + requant(recurrent_acc, 1 << 30, 22)
            + (neuron * 20 - 70) * 256,
            8,
        )
        forget = sat_int8(forget_unclamped)[0]
        cellgate = sat_int8(cellgate_unclamped)[0]
        forget_u8 = sigmoid[forget + 127]
        _, state, spike, _, _ = state_update(
            forget_u8,
            previous_states[neuron],
            cellgate,
            1 << 30,
            30,
            1 << 30,
            30,
            1 << 30,
            22,
            ((neuron % 3) - 1) * 512,
        )
        forget_values.append(forget)
        cellgate_values.append(cellgate)
        state_values.append(state)
        spike_values.append(spike)

    row_tiles = hidden_size // lanes
    input_reads = len(input_values) * row_tiles
    recurrent_reads = sum(previous_spikes) * row_tiles
    return forget_values, cellgate_values, state_values, spike_values, input_reads, recurrent_reads


def complex_term(sr: int, si: int, cr: int, ci: int) -> tuple[int, int]:
    return sr * cr - si * ci, sr * ci + si * cr


def sparse_binary_matvec(
    weights: list[list[int]], spike_vector: list[int], lanes: int
) -> tuple[list[int], list[int], int]:
    """Column-select binary matvec used by the sparsity-aware RTL contract."""
    active_columns = [index for index, spike in enumerate(spike_vector) if spike]
    result = [
        sum(row[column] for column in active_columns)
        for row in weights
    ]
    row_tiles = (len(weights) + lanes - 1) // lanes
    reads = len(active_columns) * row_tiles
    return result, active_columns, reads


def deterministic_weight(row: int, column: int) -> int:
    """Signed INT8 weight formula mirrored by the presentation-scale TB."""
    return (row * 73 + column * 151 + ((row * column) % 257) * 19 + 23) % 255 - 127


def scattered_spikes(
    width: int, count: int, offset: int, stride: int
) -> list[int]:
    spikes = [0] * width
    for index in range(count):
        spikes[(offset + index * stride) % width] = 1
    return spikes


def clustered_spikes(width: int, count: int, first_column: int) -> list[int]:
    spikes = [0] * width
    for index in range(count):
        spikes[(first_column + index) % width] = 1
    return spikes


def correlated_churn(base: list[int], replace_count: int) -> list[int]:
    result = base.copy()
    removed = 0
    for column, spike in enumerate(base):
        if spike and removed < replace_count:
            result[column] = 0
            removed += 1

    added = 0
    candidate = 211
    guard = 0
    while added < replace_count and guard < len(base) * 2:
        if not base[candidate] and not result[candidate]:
            result[candidate] = 1
            added += 1
        candidate = (candidate + 29) % len(base)
        guard += 1
    if removed != replace_count or added != replace_count:
        raise ValueError("unable to construct requested correlated churn")
    return result


class ArithmeticVectors(unittest.TestCase):
    def test_round_shift(self) -> None:
        self.assertEqual(round_shift(3, 1), 2)
        self.assertEqual(round_shift(-3, 1), -2)
        self.assertEqual(round_shift(127, 8), 0)
        self.assertEqual(round_shift(-127, 8), 0)

    def test_requantizer(self) -> None:
        self.assertEqual(requant(100, 3, 1), 150)
        self.assertEqual(requant(-101, 3, 1), -152)
        self.assertEqual(requant(9, -5, 2), -11)
        self.assertEqual(requant(12345, 1 << 30, 30), 12345)

    def test_gate_postprocess(self) -> None:
        identity = 1 << 30
        self.assertEqual(
            gate_postprocess(2560, -512, identity, 30, identity, 30, 256),
            (9, False),
        )
        self.assertEqual(
            gate_postprocess(-384, 0, identity, 30, identity, 30, 0),
            (-2, False),
        )
        self.assertEqual(
            gate_postprocess(40000, 0, identity, 30, identity, 30, 0),
            (127, True),
        )

    def test_state_update(self) -> None:
        identity = 1 << 30
        common = (identity, 30, identity, 30, identity, 22, 0)
        self.assertEqual(state_update(255, 10, -20, *common)[:3], (10, 10, 1))
        self.assertEqual(state_update(0, 10, -20, *common)[:3], (-20, -20, 0))
        self.assertEqual(state_update(128, 100, -100, *common)[:3], (0, 0, 1))
        clipped = state_update(255, 127, 0, identity, 29, identity, 30, identity, 22, 0)
        self.assertEqual(clipped[:3], (127, 127, 1))
        self.assertTrue(clipped[3])

    def test_shared_gsu_layer_multiframe_state(self) -> None:
        previous_spikes = [0] * 8
        previous_states = [0] * 8
        expected = (
            (
                [3, -2, 5, 1, -4],
                [-52, -20, -19, -31, 14, 4, 47, 39],
                [-62, -6, -25, -59, 12, -22, 49, 15],
                [-46, -3, -12, -39, 5, -9, 14, 5],
                [0, 0, 0, 0, 1, 0, 1, 1],
                0,
            ),
            (
                [-7, 4, 0, 6, 2],
                [-54, -62, -22, 18, 10, 40, 42, 87],
                [-64, -92, -28, 34, 8, 57, 44, 106],
                [-61, -69, -19, -9, 6, 16, 22, 21],
                [0, 0, 0, 0, 1, 1, 1, 1],
                6,
            ),
            (
                [127, -127, 127, -127, 127],
                [127, -127, 127, -127, 127, -127, 127, -127],
                [127, -127, 127, -127, 127, -127, 127, -127],
                [-62, -127, -16, -127, 6, -125, 20, -127],
                [0, 0, 0, 0, 1, 0, 1, 0],
                8,
            ),
        )
        for input_values, forget, cellgate, state, spike, recurrent_reads in expected:
            actual = shared_gsu_test_frame(input_values, previous_spikes, previous_states)
            self.assertEqual(actual[0], forget)
            self.assertEqual(actual[1], cellgate)
            self.assertEqual(actual[2], state)
            self.assertEqual(actual[3], spike)
            self.assertEqual(actual[4], 10)
            self.assertEqual(actual[5], recurrent_reads)
            previous_states = state
            previous_spikes = spike

        cleared = shared_gsu_test_frame([3, -2, 5, 1, -4], [0] * 8, [0] * 8)
        self.assertEqual(cleared[2], expected[0][3])
        self.assertEqual(cleared[3], expected[0][4])
        self.assertEqual(cleared[5], 0)

    def test_reduced_fullband_three_layer_sequence(self) -> None:
        hidden = 4
        lanes = 2
        l1_input_weights = [
            [((neuron * 5 + index * 3 + 2) % 11) - 5 for index in range(3)]
            for neuron in range(hidden)
        ]
        l1_recurrent_weights = [
            [((neuron * 7 + index * 2 + 1) % 9) - 4 for index in range(hidden)]
            for neuron in range(hidden)
        ]
        l2_input_weights = [
            [((neuron * 3 + index * 5 + 4) % 11) - 5 for index in range(hidden)]
            for neuron in range(hidden)
        ]
        l2_recurrent_weights = [
            [((neuron * 5 + index * 3 + 2) % 9) - 4 for index in range(hidden)]
            for neuron in range(hidden)
        ]
        projection_weights = [
            [((neuron * 7 + index * 4 + 3) % 13) - 6 for index in range(hidden)]
            for neuron in range(hidden)
        ]
        sigmoid_luts = (
            list(range(255)),
            [min(254, (address * 3) // 4 + 32) for address in range(255)],
        )

        def gsu_step(
            values: list[int],
            old_spikes: list[int],
            old_states: list[int],
            layer: int,
        ) -> tuple[list[int], list[int]]:
            input_weights = l1_input_weights if layer == 0 else l2_input_weights
            recurrent_weights = (
                l1_recurrent_weights if layer == 0 else l2_recurrent_weights
            )
            new_states: list[int] = []
            new_spikes: list[int] = []
            for neuron in range(hidden):
                input_acc = sum(
                    value * weight
                    for value, weight in zip(values, input_weights[neuron])
                )
                recurrent_acc = sum(
                    recurrent_weights[neuron][index]
                    for index, spike in enumerate(old_spikes)
                    if spike
                )
                forget_bias = neuron * 20 - 30 if layer == 0 else neuron * 8 - 12
                cell_bias = neuron * 25 - 40 if layer == 0 else neuron * 5 - 5
                forget = sat_int8(
                    round_shift(
                        requant(input_acc, 1 << 30, 22 + neuron % 2)
                        + requant(recurrent_acc, 1 << 30, 22)
                        + forget_bias * 256,
                        8,
                    )
                )[0]
                cellgate = sat_int8(
                    round_shift(
                        requant(input_acc, 1 << 30, 22)
                        + requant(recurrent_acc, 1 << 30, 22)
                        + cell_bias * 256,
                        8,
                    )
                )[0]
                forget_u8 = sigmoid_luts[layer][forget + 127]
                _, state, spike, _, _ = state_update(
                    forget_u8,
                    old_states[neuron],
                    cellgate,
                    1 << 30,
                    30,
                    1 << 30,
                    30,
                    1 << 30,
                    22,
                    ((neuron % 3) - 1) * 256,
                )
                new_states.append(state)
                new_spikes.append(spike)
            return new_spikes, new_states

        l1_spikes = [0] * hidden
        l1_states = [0] * hidden
        l2_spikes = [0] * hidden
        l2_states = [0] * hidden
        expected_frames = (
            ([3, -2, 5], [0, 0, 1, 1], [0, 0, 1, 1], [-7, -1, 7, 12], (0, 4, 0, 4)),
            ([-4, 6, 1], [0, 0, 1, 1], [0, 0, 1, 1], [-7, -1, 7, 12], (4, 4, 4, 4)),
            ([127, -127, 127], [0, 0, 0, 0], [0, 1, 1, 1], [-6, -4, 9, 10], (4, 0, 4, 6)),
        )
        for frame, expected_l1, expected_l2, expected_projection, expected_reads in expected_frames:
            previous_l1_active = sum(l1_spikes)
            previous_l2_active = sum(l2_spikes)
            l1_spikes, l1_states = gsu_step(frame, l1_spikes, l1_states, 0)
            l2_spikes, l2_states = gsu_step(l1_spikes, l2_spikes, l2_states, 1)
            projection = []
            for output, row in enumerate(projection_weights):
                accumulator = sum(weight for weight, spike in zip(row, l2_spikes) if spike)
                projection.append(
                    sat_int8(
                        round_shift(
                            requant(accumulator, 1 << 30, 22 + output % 2)
                            + (-8 + output * 6) * 256,
                            8,
                        )
                    )[0]
                )
            self.assertEqual(l1_spikes, expected_l1)
            self.assertEqual(l2_spikes, expected_l2)
            self.assertEqual(projection, expected_projection)
            actual_reads = (
                previous_l1_active * (hidden // lanes),
                sum(l1_spikes) * (hidden // lanes),
                previous_l2_active * (hidden // lanes),
                sum(l2_spikes) * (hidden // lanes),
            )
            self.assertEqual(actual_reads, expected_reads)

    def test_deepfilter_orders(self) -> None:
        terms = [
            (3, 4, 5, -2),
            (-2, 1, 4, 3),
            (7, -3, -1, 2),
            (-8, -7, 6, -5),
            (127, -127, -127, 127),
        ]
        accum = [complex_term(*term) for term in terms]
        real = 0
        imag = 0
        checkpoints: list[tuple[int, int]] = []
        for r_value, i_value in accum:
            real += r_value
            imag += i_value
            checkpoints.append((real, imag))
        self.assertEqual(checkpoints[0], (23, 14))
        self.assertEqual(checkpoints[2], (11, 29))
        self.assertEqual(checkpoints[4], (-72, 32285))

    def test_sparsity_aware_column_selection(self) -> None:
        weights = [
            [column + 1 for column in range(8)],
            [-(column + 1) for column in range(8)],
            [10 * (column + 1) for column in range(8)],
            [-10 * (column + 1) for column in range(8)],
            [2 * (column + 1) for column in range(8)],
            [3 * (column + 1) for column in range(8)],
            [-2 * (column + 1) for column in range(8)],
            [1, -1, 2, -2, 3, -3, 4, -4],
        ]
        for mask, expected_active in (
            (0x00, []),
            (0x42, [1, 6]),
            (0xA5, [0, 2, 5, 7]),
            (0xFF, list(range(8))),
        ):
            spikes = [(mask >> column) & 1 for column in range(8)]
            sparse, active, reads = sparse_binary_matvec(weights, spikes, lanes=4)
            dense_reference = [
                sum(weight * spike for weight, spike in zip(row, spikes))
                for row in weights
            ]
            self.assertEqual(active, expected_active)
            self.assertEqual(sparse, dense_reference)
            self.assertEqual(reads, len(expected_active) * 2)

    def test_presentation_scale_spike_profiles(self) -> None:
        width = 320
        row_tiles = 20
        for active in (0, 16, 32, 64, 96, 160, 320):
            spikes = scattered_spikes(width, active, offset=3, stride=37)
            self.assertEqual(sum(spikes), active)
            self.assertEqual(sum(spikes) * row_tiles, active * row_tiles)
            self.assertEqual(
                width * row_tiles - active * row_tiles,
                (width - active) * row_tiles,
            )

        wrapped_cluster = clustered_spikes(width, 16, first_column=300)
        self.assertEqual(sum(wrapped_cluster), 16)
        self.assertTrue(all(wrapped_cluster[column] for column in range(300, 316)))

    def test_temporally_correlated_spike_profiles(self) -> None:
        base = scattered_spikes(320, 32, offset=13, stride=37)
        repeated = base.copy()
        churned = correlated_churn(base, replace_count=8)
        burst = clustered_spikes(320, 32, first_column=100)
        shifted_burst = clustered_spikes(320, 32, first_column=104)

        self.assertEqual(sum(a and b for a, b in zip(base, repeated)), 32)
        self.assertEqual(sum(a != b for a, b in zip(base, repeated)), 0)
        self.assertEqual(sum(churned), 32)
        self.assertEqual(sum(a and b for a, b in zip(base, churned)), 24)
        self.assertEqual(sum(a != b for a, b in zip(base, churned)), 16)
        self.assertEqual(sum(a and b for a, b in zip(burst, shifted_burst)), 28)
        self.assertEqual(sum(a != b for a, b in zip(burst, shifted_burst)), 8)

    def test_presentation_scale_weighted_checksums(self) -> None:
        for spikes, expected_checksum in (
            (scattered_spikes(320, 16, offset=3, stride=37), -458489),
            (scattered_spikes(320, 32, offset=13, stride=37), -78258),
            ([1] * 320, -492936),
        ):
            active = [column for column, spike in enumerate(spikes) if spike]
            outputs = [
                sum(deterministic_weight(row, column) for column in active)
                for row in range(320)
            ]
            checksum = sum((row + 1) * value for row, value in enumerate(outputs))
            self.assertEqual(checksum, expected_checksum)


class TestbenchCoverage(unittest.TestCase):
    def test_every_leaf_has_testbench(self) -> None:
        root = Path(__file__).resolve().parents[1]
        leaves = {path.stem for path in (root / "leaf").glob("*.v")}
        benches = {
            path.stem.removeprefix("tb_")
            for path in (root / "tb").glob("tb_*.v")
        }
        self.assertFalse(leaves - benches, f"missing testbenches: {sorted(leaves - benches)}")

    def test_testbenches_are_self_checking(self) -> None:
        root = Path(__file__).resolve().parents[1]
        for path in (root / "tb").glob("tb_*.v"):
            source = path.read_text(encoding="utf-8")
            self.assertTrue(
                ("errors" in source) or ("failures" in source),
                path.name,
            )
            self.assertIn("PASS", source, path.name)
            self.assertIn("FAIL", source, path.name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
