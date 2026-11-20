from dataclasses import dataclass, field
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
RTL_PATH = ROOT / "rtl" / "memory" / "sequential_recurrent_context_store.v"


def logical_context_id(branch: int | None, context: int, layer: int) -> int:
    if branch is None:
        assert context == 0
        return layer
    bases = (2, 10, 16)
    limits = (4, 3, 2)
    assert branch in range(3)
    assert context in range(limits[branch])
    assert layer in (0, 1)
    return bases[branch] + context * 2 + layer


@dataclass
class SequentialContextReference:
    mapping: list[int] = field(default_factory=lambda: list(range(20)))
    producer_slot: int = 20
    lists: list[list[int]] = field(default_factory=lambda: [[] for _ in range(21)])
    states: list[list[int] | None] = field(default_factory=lambda: [None] * 20)
    open_id: int | None = None
    row_tiles: int = 0
    next_state_index: int = 0
    new_state: list[int] = field(default_factory=list)
    old_tiles_read: set[int] = field(default_factory=set)
    new_list: list[int] = field(default_factory=list)
    finalized: bool = False

    def clear(self) -> None:
        self.mapping = list(range(20))
        self.producer_slot = 20
        self.lists = [[] for _ in range(21)]
        self.states = [None] * 20
        self.open_id = None

    def list_for(self, logical_id: int) -> list[int]:
        return list(self.lists[self.mapping[logical_id]])

    def state_tile(self, logical_id: int, tile: int) -> list[int]:
        assert logical_id in range(20) and tile in range(20)
        if self.states[logical_id] is None:
            value = [0] * 16
        else:
            value = self.states[logical_id][tile * 16 : tile * 16 + 16]
        if self.open_id == logical_id:
            self.old_tiles_read.add(tile)
        return value

    def open(self, logical_id: int, row_tiles: int) -> None:
        assert self.open_id is None
        assert logical_id in range(20)
        assert row_tiles in range(1, 21)
        self.open_id = logical_id
        self.row_tiles = row_tiles
        self.next_state_index = 0
        self.new_state = [0] * (row_tiles * 16)
        self.old_tiles_read = set()
        self.new_list = []
        self.finalized = False

    def write_state(self, index: int, value: int, last: bool) -> None:
        assert self.open_id is not None
        assert index == self.next_state_index
        assert index // 16 in self.old_tiles_read
        assert last == (index == self.row_tiles * 16 - 1)
        self.new_state[index] = value
        self.next_state_index += 1

    def active_command(self, index: int, write: bool, finalize: bool) -> None:
        assert self.open_id is not None and not self.finalized
        assert write or finalize
        assert index < self.row_tiles * 16
        if write:
            assert not self.new_list or index > self.new_list[-1]
            assert len(self.new_list) < 320
            self.new_list.append(index)
        if finalize:
            assert index == self.row_tiles * 16 - 1
            self.finalized = True

    def commit(self, barrier: bool) -> None:
        assert self.open_id is not None
        assert self.next_state_index == self.row_tiles * 16
        assert self.old_tiles_read == set(range(self.row_tiles))
        assert self.finalized and barrier
        logical_id = self.open_id
        displaced = self.mapping[logical_id]
        self.lists[self.producer_slot] = list(self.new_list)
        self.mapping[logical_id] = self.producer_slot
        self.producer_slot = displaced
        padded = list(self.new_state) + [0] * (320 - len(self.new_state))
        self.states[logical_id] = padded
        self.open_id = None


def run_frame(model: SequentialContextReference, logical_id: int, frame: int) -> tuple[list[int], list[int]]:
    row_tiles = 20 if logical_id < 2 else 14
    old_list = model.list_for(logical_id)
    model.open(logical_id, row_tiles)
    assert model.list_for(logical_id) == old_list

    produced = []
    values = []
    for tile in range(row_tiles):
        model.state_tile(logical_id, tile)
        for lane in range(16):
            index = tile * 16 + lane
            value = (logical_id * 17 + frame * 53 + index) % 255 + 1
            values.append(value)
            model.write_state(index, value, index == row_tiles * 16 - 1)
            active = (
                True
                if logical_id == 0 and frame == 0
                else index % 20 < 11
                if logical_id == 0 and frame == 1
                else False
                if logical_id == 19 and frame == 0
                else index % 4 == logical_id % 4
            )
            if active:
                produced.append(index)
                model.active_command(
                    index, True, index == row_tiles * 16 - 1
                )
            elif index == row_tiles * 16 - 1:
                model.active_command(index, False, True)
    model.commit(True)
    return values, produced


def test_context_identity_map_is_dense_and_unique():
    ids = [logical_context_id(None, 0, layer) for layer in range(2)]
    for branch, context_count in enumerate((4, 3, 2)):
        for context in range(context_count):
            for layer in range(2):
                ids.append(logical_context_id(branch, context, layer))
    assert ids == list(range(20))


def test_reference_slot_swaps_and_multiframe_state():
    model = SequentialContextReference()
    for logical_id in range(20):
        assert model.list_for(logical_id) == []
        assert model.state_tile(logical_id, 0) == [0] * 16
        values, active = run_frame(model, logical_id, 0)
        assert model.list_for(logical_id) == active
        assert model.states[logical_id][: len(values)] == values

    first_mapping = model.mapping[0]
    old_state = model.state_tile(0, 0)
    values, active = run_frame(model, 0, 1)
    assert old_state == list(range(1, 17))
    assert len(active) == 176
    assert model.mapping[0] != first_mapping
    assert model.list_for(0) == active
    assert model.states[0][: len(values)] == values


def test_reference_rejects_unsafe_order_and_commit():
    model = SequentialContextReference()
    model.open(0, 1)
    with pytest.raises(AssertionError):
        model.write_state(0, 1, False)
    model.state_tile(0, 0)
    model.write_state(0, 1, False)
    with pytest.raises(AssertionError):
        model.write_state(0, 2, False)
    model.active_command(3, True, False)
    with pytest.raises(AssertionError):
        model.active_command(3, True, False)
    with pytest.raises(AssertionError):
        model.commit(True)


def test_rtl_geometry_and_simplified_lifecycle_are_explicit():
    source = RTL_PATH.read_text(encoding="utf-8")
    assert "reg [8:0] active_mem0 [0:4095]" in source
    assert "reg [8:0] active_mem1 [0:4095]" in source
    assert "reg [63:0] state_lo_mem [0:511]" in source
    assert "reg [63:0] state_hi_mem [0:511]" in source
    assert source.count('ram_style = "block"') == 4
    assert "logical_to_slot_q" in source
    assert "producer_slot_q" in source
    for forbidden in (
        "generation_q",
        "binding_token",
        "content_handle",
        "refcount",
        "poison",
    ):
        assert forbidden not in source.lower()
    assert "reset_required = error_valid" in source


def test_storage_capacity_arithmetic():
    assert 21 * 320 * 9 == 60_480
    assert 2 * 4096 * 9 == 73_728
    assert 20 * 20 * 128 == 51_200
    assert 2 * 512 * 64 == 65_536
