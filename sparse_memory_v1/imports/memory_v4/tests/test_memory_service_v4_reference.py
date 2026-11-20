import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAYOUT_PATH = (
    ROOT / "outputs" / "memory" / "2026-09-03" / "v4" /
    "memory_layout_v4.json"
)
IMAGE_PATH = LAYOUT_PATH.with_name("parameters_v4.bin")
SERVICE_PATH = ROOT / "rtl" / "memory" / "memory_service.v"
MEMORY_PATH = ROOT / "rtl" / "memory" / "memory.v"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_sequential_v4_service_frozen_inputs_and_dependency_boundary():
    source = SERVICE_PATH.read_text(encoding="utf-8")

    assert sha256(MEMORY_PATH) == (
        "72435c38d85c7cbaaab25733c59912a52057b280e87c3b4d1b7ee52d7f5dab71"
    )
    assert sha256(IMAGE_PATH) == (
        "e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34"
    )
    assert 'include "memory/model_memory_v4_map.vh"' in source
    assert "model_memory_v4_table stage_table" in source
    assert "model_memory_v3_table" not in source
    assert re.search(r"\bmemory\s*#\s*\(", source)
    for excluded in (
        "parameter_weight_bank",
        "matrix0_raw_accumulator_scratch",
        "parameter_source_directory",
        "active_index_list_store",
    ):
        assert excluded not in source


def test_layout_fits_single_cache_and_full_stage_dma_is_independent_of_sparsity():
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    source = SERVICE_PATH.read_text(encoding="utf-8")

    assert layout["format_version"] == 4
    assert layout["stage_count"] == 12
    assert layout["cache_bytes"] == 262_144
    assert layout["maximum_stage_bytes"] == 219_360
    assert all(
        0 < stage["transfer_bytes"] <= layout["cache_bytes"]
        and stage["transfer_bytes"] % 8 == 0
        for stage in layout["stages"]
    )

    # The DMA byte count is captured solely from the generated table.  No
    # active count/list/bitmap is a service input or participates in loading.
    assert "load_byte_count_q <= table_transfer_bytes;" in source
    port_prefix = source.split(");", 1)[0]
    assert "active_count" not in port_prefix
    assert "active_list" not in port_prefix
    assert "bitmap" not in port_prefix


def test_global_lut_is_one_table_major_reset_epoch_payload():
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    image = IMAGE_PATH.read_bytes()
    lut = layout["global_sigmoid_lut"]

    assert lut["dram_byte_offset"] == 64
    assert lut["transfer_bytes"] == 2_040
    assert lut["table_count"] == 8
    assert lut["entries_per_table"] == 255
    assert lut["table_major"] is True

    payload = image[64 : 64 + 2_040]
    assert hashlib.sha256(payload).hexdigest() == lut["sha256"]
    assert [
        (ordinal // 255, ordinal % 255, payload[ordinal])
        for ordinal in range(2_040)
    ][-1][:2] == (7, 254)


def test_all_stage_descriptors_have_native_addressable_payloads():
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))

    for stage in layout["stages"]:
        assert stage["id"] in range(12)
        assert stage["dram_byte_offset"] % 64 == 0
        assert stage["transfer_bytes"] % 8 == 0
        assert stage["bram_words"] == stage["transfer_bytes"] // 8

        matrices = stage["matrices"]
        assert len(matrices) in (1, 2)
        for matrix in matrices:
            assert matrix["payload_bytes"] == (
                matrix["source_count"] * matrix["row_tiles"] * 16
            )
            first = matrix["local_word_offset"]
            last = (
                first + matrix["source_count"] * matrix["row_tiles"] * 2
            )
            assert 0 <= first < last <= stage["bram_words"]

        params = stage["parameters"]
        assert params["row_tiles"] == matrices[0]["row_tiles"]
        assert params["local_word_offset"] + (
            params["row_tiles"] * params["record_words"]
        ) <= stage["bram_words"]


def test_service_exposes_reset_only_fatal_and_held_response_protocol():
    source = SERVICE_PATH.read_text(encoding="utf-8")

    assert "CACHE_FATAL" in source
    assert "clear_error is a compatibility no-op" in source
    assert not re.search(r"if\s*\(clear_error\).*error_valid\s*<=\s*1'b0", source)
    assert "ADAPTER_WEIGHT_RESPONSE" in source
    assert "ADAPTER_PARAM_RESPONSE" in source
    assert "stage_release_id == active_stage_id" in source
    assert "weight_req_matrix &&" in source
    assert "selected_matrix_sources" in source
    assert "selected_matrix_tiles" in source
