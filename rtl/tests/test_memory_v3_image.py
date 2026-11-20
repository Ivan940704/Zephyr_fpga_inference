import hashlib
import json
from pathlib import Path
import struct
from tempfile import TemporaryDirectory

import pytest

from rtl.tools.generate_memory_v3 import (
    BUS_BYTES,
    CACHE_BYTES,
    FORMAT_VERSION,
    IMAGE_HEADER_BYTES,
    IMAGE_MAGIC,
    LANES,
    OPERATOR_EXECUTION_ORDER,
    ROOT,
    STAGE_ALIGNMENT,
    build_image,
    build_weight_readback_vectors,
    emit_header,
    emit_readback_table,
    emit_table,
    field_source_index,
    lowered_value,
    pack_source_major_matrix,
    tensor_bytes,
    tensor_values,
    write_artifacts,
)


MANIFEST_PATH = ROOT / "upstream" / "parameters" / "manifest.json"
SNAPSHOT_ROOT = ROOT / "outputs" / "memory" / "2026-09-01" / "v3"
HEADER_PATH = ROOT / "rtl" / "memory" / "model_memory_v3_map.vh"
TABLE_PATH = ROOT / "rtl" / "memory" / "model_memory_v3_table.v"
READBACK_TABLE_PATH = (
    ROOT / "rtl" / "memory" / "model_memory_v3_readback_table.v"
)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def signed_value(encoded: int, width: int) -> int:
    sign = 1 << (width - 1)
    return encoded - (1 << width) if encoded & sign else encoded


def load_source():
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    blob = (MANIFEST_PATH.parent / manifest["storage"]["file"]).read_bytes()
    return manifest, blob


def test_v3_snapshot_is_deterministic_and_self_consistent():
    image, layout, golden = build_image(MANIFEST_PATH)

    assert image == (SNAPSHOT_ROOT / "parameters_v3.bin").read_bytes()
    assert layout == json.loads(
        (SNAPSHOT_ROOT / "memory_layout_v3.json").read_text(encoding="utf-8")
    )
    assert golden == json.loads(
        (SNAPSHOT_ROOT / "memory_golden_v3.json").read_text(encoding="utf-8")
    )
    assert emit_header(layout) == HEADER_PATH.read_text(encoding="utf-8")
    assert emit_table(layout) == TABLE_PATH.read_text(encoding="utf-8")
    assert emit_readback_table(golden) == READBACK_TABLE_PATH.read_text(
        encoding="utf-8"
    )

    assert layout["format_version"] == FORMAT_VERSION
    assert layout["stage_count"] == len(OPERATOR_EXECUTION_ORDER)
    assert layout["image_sha256"] == sha256(image)
    assert layout["maximum_stage_bytes"] <= CACHE_BYTES
    assert [stage["name"] for stage in layout["stages"]] == OPERATOR_EXECUTION_ORDER
    assert layout["weight_physical_order"] == [
        "operator",
        "matrix",
        "source_index",
        "row_tile",
        "lane",
    ]

    magic, version, stages, lanes, bus_bytes, stage_alignment, reserved = struct.unpack(
        "<8sIIIIII", image[:32]
    )
    assert magic == IMAGE_MAGIC
    assert version == FORMAT_VERSION
    assert stages == len(OPERATOR_EXECUTION_ORDER)
    assert lanes == LANES
    assert bus_bytes == BUS_BYTES
    assert stage_alignment == STAGE_ALIGNMENT
    assert reserved == 0
    assert image[32:IMAGE_HEADER_BYTES].hex() == layout["source_manifest_sha256"]

    previous_end = IMAGE_HEADER_BYTES
    for stage in layout["stages"]:
        assert stage["dram_byte_offset"] % STAGE_ALIGNMENT == 0
        assert stage["transfer_bytes"] % BUS_BYTES == 0
        assert stage["bram_words"] == stage["transfer_bytes"] // BUS_BYTES
        assert stage["transfer_bytes"] <= CACHE_BYTES
        assert stage["dram_byte_offset"] >= previous_end
        start = stage["dram_byte_offset"]
        end = start + stage["transfer_bytes"]
        assert stage["stage_sha256"] == sha256(image[start:end])
        previous_end = end

    assert previous_end == len(image)
    checks = golden["dense_reference_checks"]
    assert checks["all_matrix_values_compared"] is True
    assert checks["all_shared_gate_duplicate_values_compared"] is True
    assert checks["all_parameter_values_range_checked_and_repacked"] is True
    assert checks["matrix_values_verified"] > 1_800_000
    assert checks["parameter_values_verified"] > 35_000
    assert checks["lut_values_verified"] == 8 * 255


def test_every_v3_weight_lane_matches_the_dense_row_major_source():
    manifest, blob = load_source()
    image = (SNAPSHOT_ROOT / "parameters_v3.bin").read_bytes()
    layout = json.loads(
        (SNAPSHOT_ROOT / "memory_layout_v3.json").read_text(encoding="utf-8")
    )

    compared = 0
    duplicate_compared = 0
    padding_compared = 0
    for stage in layout["stages"]:
        operator = manifest["operators"][stage["name"]]
        for matrix in stage["matrices"]:
            tensor = operator["tensors"][matrix["name"]]
            raw = tensor_bytes(blob, tensor, matrix["name"])
            source_rows, source_count = map(int, tensor["shape"])
            output_rows = matrix["output_rows"]
            matrix_start = (
                stage["dram_byte_offset"] + matrix["local_byte_offset"]
            )
            for source_index in range(source_count):
                for row_tile in range(matrix["row_tiles"]):
                    for lane in range(LANES):
                        row = row_tile * LANES + lane
                        packed_index = (
                            matrix_start
                            + source_index * matrix["source_stride_bytes"]
                            + row_tile * LANES
                            + lane
                        )
                        expected = raw[row * source_count + source_index] if row < output_rows else 0
                        assert image[packed_index] == expected
                        if row < output_rows:
                            compared += 1
                            if matrix["shared_gate_halves_verified"]:
                                duplicate_index = (output_rows + row) * source_count + source_index
                                assert raw[duplicate_index] == expected
                                duplicate_compared += 1
                        else:
                            padding_compared += 1

            assert compared >= matrix["verified_source_values"]
            assert source_rows == output_rows * (
                2 if matrix["shared_gate_halves_verified"] else 1
            )

    golden = json.loads(
        (SNAPSHOT_ROOT / "memory_golden_v3.json").read_text(encoding="utf-8")
    )["dense_reference_checks"]
    assert compared + duplicate_compared == golden["matrix_values_verified"]
    assert padding_compared >= 0


def test_every_parameter_field_and_padding_byte_matches_source_values():
    manifest, blob = load_source()
    image = (SNAPSHOT_ROOT / "parameters_v3.bin").read_bytes()
    layout = json.loads(
        (SNAPSHOT_ROOT / "memory_layout_v3.json").read_text(encoding="utf-8")
    )

    checked = 0
    for stage in layout["stages"]:
        operator = manifest["operators"][stage["name"]]
        params = stage["parameters"]
        values = {
            field["source_tensor"]: tensor_values(
                blob,
                operator["tensors"][field["source_tensor"]],
                field["source_tensor"],
            )
            for field in params["fields"]
        }
        hidden_size = params["row_tiles"] * LANES
        start = stage["dram_byte_offset"] + params["local_byte_offset"]
        for tile in range(params["row_tiles"]):
            record_start = start + tile * params["record_bytes"]
            response_end = record_start + params["response_bytes"]
            record_end = record_start + params["record_bytes"]
            word = int.from_bytes(image[record_start:response_end], "little")
            assert image[response_end:record_end] == bytes(
                params["record_padding_bytes"]
            )
            for field in params["fields"]:
                mask = (1 << field["lane_width"]) - 1
                for lane in range(LANES):
                    channel = tile * LANES + lane
                    source_index = field_source_index(
                        field["source_selector"], hidden_size, channel
                    )
                    expected = int(values[field["source_tensor"]][source_index])
                    encoded = (word >> (field["lsb"] + lane * field["lane_width"])) & mask
                    actual = (
                        signed_value(encoded, field["lane_width"])
                        if field["signed"]
                        else encoded
                    )
                    assert actual == expected
                    checked += 1

        if stage["lut"]["present"]:
            lut = tensor_bytes(blob, operator["tensors"]["sigmoid_lut"], "sigmoid_lut")
            lut_start = stage["dram_byte_offset"] + stage["lut"]["local_byte_offset"]
            assert image[lut_start : lut_start + 255] == lut

    golden = json.loads(
        (SNAPSHOT_ROOT / "memory_golden_v3.json").read_text(encoding="utf-8")
    )["dense_reference_checks"]
    assert checked == golden["parameter_values_verified"]


def test_generator_rebuilds_the_complete_versioned_artifact_set():
    image, layout, golden = build_image(MANIFEST_PATH)
    with TemporaryDirectory() as directory:
        temporary = Path(directory)
        output_dir = temporary / "v3"
        header = temporary / "rtl" / "model_memory_v3_map.vh"
        table = temporary / "rtl" / "model_memory_v3_table.v"
        readback_table = temporary / "rtl" / "model_memory_v3_readback_table.v"
        paths = write_artifacts(
            image=image,
            layout=layout,
            golden=golden,
            output_dir=output_dir,
            output_vh=header,
            output_table=table,
            output_readback_table=readback_table,
        )
        expected = {
            "parameters_v3.bin": SNAPSHOT_ROOT / "parameters_v3.bin",
            "memory_layout_v3.json": SNAPSHOT_ROOT / "memory_layout_v3.json",
            "memory_golden_v3.json": SNAPSHOT_ROOT / "memory_golden_v3.json",
            "model_memory_v3_map.vh": HEADER_PATH,
            "model_memory_v3_table.v": TABLE_PATH,
            "model_memory_v3_readback_table.v": READBACK_TABLE_PATH,
            "parameters_v3.sha256": SNAPSHOT_ROOT / "parameters_v3.sha256",
        }
        assert {path.name for path in paths} == set(expected)
        for path in paths:
            assert path.read_bytes() == expected[path.name].read_bytes()

        for line in (output_dir / "parameters_v3.sha256").read_text().splitlines():
            digest, name = line.split("  ", 1)
            matching = [path for path in paths if path.name == Path(name).name]
            assert len(matching) == 1
            assert sha256(matching[0].read_bytes()) == digest


def test_frozen_weight_readback_vectors_match_image_byte_for_byte():
    image, layout, golden = build_image(MANIFEST_PATH)
    vectors = golden["weight_readback_vectors"]["vectors"]

    assert vectors == build_weight_readback_vectors(image, layout)
    assert len(vectors) == 13
    assert [vector["stage"] for vector in vectors].count(2) == 5
    assert [vector["stage"] for vector in vectors].count(1) == 8
    assert {vector["matrix"] for vector in vectors if vector["stage"] == 1} == {
        0,
        1,
    }

    for vector in vectors:
        start = vector["image_byte_offset"]
        payload = image[start : start + LANES]
        assert len(payload) == LANES
        assert payload.hex() == vector["expected_lane_bytes_hex"]
        assert int.from_bytes(payload, "little") == int(
            vector["expected_u128_le_hex"], 16
        )
        assert vector["expected_words_le"] == [
            int.from_bytes(payload[word : word + 4], "little")
            for word in range(0, LANES, 4)
        ]

    assert [vector["expected_lane_bytes_hex"] for vector in vectors] == [
        "28eefdf613ffe50e15ecf4ea0a02f115",
        "31b5bcd61b312c2b37fce131e8c36329",
        "f0defffa1000d03f240604fff519d222",
        "ede4f92a2811f6d72ced02fa0aeed30d",
        "1606e30215effbeb073612f1020d1e07",
        "040813eaf5fcef1b13004b03e8ef39f2",
        "1409e1cc0503f8e70221fcfa0330fe2c",
        "e51408fbf0f00416080d07febe060d00",
        "36fcd8dfe20ff810fb15fbe3fdd705f8",
        "81fe0dd11606d408e7faf6fbe7301028",
        "05810cf60319013e0007e500d248be11",
        "02ff112de8fad30dde1713e62811e2e8",
        "08e8fae4f706ffe8f609d8e8f1130d7f",
    ]


def test_lowering_and_shared_gate_checks_fail_closed():
    assert lowered_value(-(1 << 31), 32, True, "multiplier") == 1 << 31
    assert lowered_value((1 << 31) - 1, 32, True, "multiplier") == (1 << 31) - 1
    assert lowered_value(63, 6, False, "shift") == 63

    with pytest.raises(ValueError, match="signed 32-bit"):
        lowered_value(1 << 31, 32, True, "multiplier")
    with pytest.raises(ValueError, match="unsigned 6-bit"):
        lowered_value(64, 6, False, "shift")
    with pytest.raises(ValueError, match="unsigned 6-bit"):
        lowered_value(-1, 6, False, "shift")

    with pytest.raises(ValueError, match="gate halves differ"):
        pack_source_major_matrix(
            b"\x01\x02\x01\x03",
            source_rows=2,
            output_rows=1,
            source_count=2,
            shared_gate_halves=True,
            tensor_name="weight_q",
        )
