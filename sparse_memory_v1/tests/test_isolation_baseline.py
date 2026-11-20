from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "imports" / "fixtures" / "v4"
sys.path.insert(0, str(ROOT / "scripts"))

from run_dense_baseline import reproduce  # noqa: E402


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_import_manifest_and_no_symlinks():
    entries = []
    for raw in (ROOT / "IMPORT_SHA256SUMS").read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        expected, relative = raw.split(maxsplit=1)
        target = ROOT / relative.lstrip(" *")
        assert target.is_file()
        assert sha256(target) == expected
        entries.append(target)
    assert len(entries) >= 40
    assert not [path for path in ROOT.rglob("*") if path.is_symlink()]


def test_compile_allowlist_is_self_contained_and_explicit():
    entries = []
    for raw in (ROOT / "compile_dense_baseline.f").read_text(encoding="utf-8").splitlines():
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        target = (ROOT / entry).resolve()
        target.relative_to(ROOT.resolve())
        assert target.is_file()
        entries.append(entry)
    assert entries
    assert all("*" not in entry and "../" not in entry for entry in entries)


def test_v4_dense_traffic_baseline():
    layout = json.loads((FIXTURE / "memory_layout_v4.json").read_text(encoding="utf-8"))
    image = FIXTURE / "parameters_v4.bin"
    assert image.stat().st_size == layout["image_bytes"] == 1_053_056
    assert sha256(image) == layout["image_sha256"]
    assert sum(stage["transfer_bytes"] for stage in layout["stages"]) == 1_050_544
    assert layout["global_sigmoid_lut"]["transfer_bytes"] == 2_040

    parameter_bytes = sum(stage["parameters"]["payload_bytes"] for stage in layout["stages"])
    dense_matrix_bytes = sum(
        stage["matrices"][0]["payload_bytes"]
        for stage in layout["stages"]
        if stage["id"] in (0, 3, 6, 9)
    )
    assert parameter_bytes == 94_448
    assert dense_matrix_bytes == 87_232
    assert parameter_bytes + dense_matrix_bytes == 181_680
    assert 1_050_544 - 181_680 == 868_864


def test_dense_import_runner_reproduces_all_stage_hashes():
    report = reproduce()
    assert report["result"] == "PASS"
    assert len(report["stages"]) == 12
    assert report["dense_bytes_per_frame"] == 1_050_544
