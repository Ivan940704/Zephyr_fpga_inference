import json
from pathlib import Path
from tempfile import TemporaryDirectory

from rtl.tools.generate_axi_memory_image import (
    OPERATOR_EXECUTION_ORDER,
    SHARED_GATE_TENSORS,
    build_layout,
    emit_verilog,
    pack_stage,
)


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "upstream" / "parameters" / "manifest.json"
SNAPSHOT_ROOT = ROOT / "outputs" / "memory" / "2026-09-01"


def test_axi_image_is_aligned_and_packs_shared_gsu_gate_weights_once():
    manifest_path = MANIFEST_PATH
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source = (manifest_path.parent / manifest["storage"]["file"]).read_bytes()

    image, layout = build_layout(
        manifest_path=manifest_path,
        bus_bytes=8,
        stage_alignment=64,
    )

    assert len(image) == layout["image_bytes"]
    assert [stage["name"] for stage in layout["stages"]] == OPERATOR_EXECUTION_ORDER
    assert layout["format_version"] == 2
    assert layout["shared_gate_weight_packing"] is True
    assert layout["unlowered_parameters_in_image"] is False
    assert "known_unlowered" not in layout

    shared_stage_count = 0
    shared_tensor_count = 0
    payload_bytes_saved = 0
    for stage in layout["stages"]:
        assert stage["dram_byte_offset"] % 64 == 0
        assert stage["transfer_bytes"] % 8 == 0
        assert stage["bram_words"] == stage["transfer_bytes"] // 8

        source_tensors = manifest["operators"][stage["name"]]["tensors"]
        stage_saved = 0
        if stage["shared_gate_weight_packing"]:
            shared_stage_count += 1
        for tensor_name, packed in stage["tensors"].items():
            original = source_tensors[tensor_name]
            source_start = original["offset"]
            source_end = source_start + original["nbytes"]
            image_start = stage["dram_byte_offset"] + packed["local_byte_offset"]
            image_end = image_start + packed["nbytes"]
            source_payload = source[source_start:source_end]
            image_payload = image[image_start:image_end]

            assert packed["source_offset"] == source_start
            assert packed["source_nbytes"] == original["nbytes"]
            assert packed["source_shape"] == original["shape"]

            if packed.get("gate_shared"):
                shared_tensor_count += 1
                assert tensor_name in SHARED_GATE_TENSORS
                assert packed["gate_count"] == 2
                assert packed["nbytes"] * 2 == original["nbytes"]
                assert packed["shape"][0] * 2 == original["shape"][0]
                assert source_payload[: packed["nbytes"]] == source_payload[packed["nbytes"] :]
                assert image_payload == source_payload[: packed["nbytes"]]
                stage_saved += packed["nbytes"]
            else:
                assert image_payload == source_payload

        assert stage["packed_bytes_saved"] == stage_saved
        assert stage["source_payload_bytes"] - stage["payload_bytes"] == stage_saved
        payload_bytes_saved += stage_saved

    assert shared_stage_count == 8
    assert shared_tensor_count == 8 * len(SHARED_GATE_TENSORS)
    assert layout["payload_bytes_saved"] == payload_bytes_saved
    assert layout["maximum_stage_bytes"] < 470_040
    assert layout["maximum_stage_bytes"] <= 256 * 1024
    assert image == (SNAPSHOT_ROOT / "parameters_axi.bin").read_bytes()

    snapshot_layout = json.loads(
        (SNAPSHOT_ROOT / "memory_layout.json").read_text(encoding="utf-8")
    )
    assert Path(layout["source_manifest"]).resolve() == (
        ROOT / snapshot_layout["source_manifest"]
    ).resolve()
    layout_without_path = dict(layout)
    snapshot_without_path = dict(snapshot_layout)
    layout_without_path.pop("source_manifest")
    snapshot_without_path.pop("source_manifest")
    assert layout_without_path == snapshot_without_path

    with TemporaryDirectory() as directory:
        header_path = Path(directory) / "model_memory_map.vh"
        emit_verilog(layout, header_path)
        header = header_path.read_text(encoding="utf-8")
        assert "`define MODEL_SHARED_GATE_WEIGHT_PACKING 1" in header
        assert "_WEIGHT_IH_Q_GATE_SHARED 1" in header
        assert "_WEIGHT_HH_Q_GATE_SHARED 1" in header


def test_shared_gate_packing_rejects_nonidentical_halves():
    tensors = {
        "weight_ih_q": {
            "offset": 0,
            "nbytes": 4,
            "dtype": "int8",
            "shape": [2, 2],
        }
    }
    try:
        pack_stage(b"abac", tensors, share_gsu_gate_weights=True)
    except ValueError as error:
        assert "does not contain identical halves" in str(error)
    else:
        raise AssertionError("nonidentical shared-gate halves were silently packed")
