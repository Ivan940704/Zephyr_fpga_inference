import json
import sys
from types import SimpleNamespace
import wave
from pathlib import Path

import numpy as np
import pytest

from software.evaluation.ptq_audio_metrics import (
    SAMPLE_RATE,
    _optional_scores,
    aggregate,
    discover_triplets,
    evaluate,
    si_sdr_db,
    snr_db,
)


def write_pcm16(path: Path, values: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(np.rint(values * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())


def make_dataset(root: Path, count: int = 2) -> None:
    time_axis = np.arange(1600, dtype=np.float64) / SAMPLE_RATE
    for file_id in range(count):
        clean = 0.2 * np.sin(2.0 * np.pi * (220 + file_id * 40) * time_axis)
        noise = 0.04 * np.sin(2.0 * np.pi * 1900 * time_axis + file_id)
        noisy = clean + noise
        write_pcm16(root / "clean" / f"clean_fileid_{file_id}.wav", clean)
        write_pcm16(root / "noise" / f"noise_fileid_{file_id}.wav", noise)
        write_pcm16(
            root / "noisy" / f"synthetic_snr10_fileid_{file_id}.wav", noisy
        )


def test_discover_triplets_requires_exact_contiguous_ids(tmp_path):
    make_dataset(tmp_path, 2)
    triplets = discover_triplets(tmp_path, expected_count=2)
    assert [triplet.file_id for triplet in triplets] == [0, 1]
    with pytest.raises(ValueError, match="expected 3 triplets"):
        discover_triplets(tmp_path, expected_count=3)


def test_discovery_matches_by_id_not_lexicographic_filename_order(tmp_path):
    make_dataset(tmp_path, 2)
    original = tmp_path / "noisy" / "synthetic_snr10_fileid_0.wav"
    original.rename(tmp_path / "noisy" / "z_last_fileid_0.wav")
    assert [item.file_id for item in discover_triplets(tmp_path, 2)] == [0, 1]


def test_metrics_improve_for_an_estimate_closer_to_reference():
    reference = np.asarray([0.2, -0.3, 0.4, -0.1, 0.25], dtype=np.float64)
    noisy = reference + np.asarray([0.1, -0.08, 0.07, 0.09, -0.1])
    enhanced = reference + 0.1 * (noisy - reference)
    assert snr_db(reference, enhanced) > snr_db(reference, noisy)
    assert si_sdr_db(reference, enhanced) > si_sdr_db(reference, noisy)


def test_clip_level_bootstrap_is_deterministic():
    first = aggregate([1.0, 2.0, 3.0], resamples=250)
    second = aggregate([1.0, 2.0, 3.0], resamples=250)
    assert first == second
    assert first["count"] == 3
    assert first["mean"] == pytest.approx(2.0)


def test_optional_metric_failure_is_recorded_without_substitution(monkeypatch):
    def failing_stoi(*_args, **_kwargs):
        raise ValueError("silent clip")

    monkeypatch.setitem(sys.modules, "pystoi", SimpleNamespace(stoi=failing_stoi))
    monkeypatch.setitem(sys.modules, "pesq", SimpleNamespace(pesq=lambda *_args: 3.25))
    availability = {
        "stoi": {"status": "AVAILABLE"},
        "pesq": {"status": "AVAILABLE"},
    }
    scores = _optional_scores(np.ones(64), np.ones(64), availability)
    assert scores["stoi"] is None
    assert scores["pesq"] == pytest.approx(3.25)
    assert scores["errors"]["stoi"] == "ValueError: silent clip"


def test_inventory_and_enhanced_summary_keep_provenance(tmp_path):
    dataset = tmp_path / "dataset"
    enhanced_root = tmp_path / "enhanced"
    make_dataset(dataset, 2)
    for file_id in range(2):
        clean_path = dataset / "clean" / f"clean_fileid_{file_id}.wav"
        with wave.open(str(clean_path), "rb") as handle:
            payload = handle.readframes(handle.getnframes())
        clean = np.frombuffer(payload, dtype="<i2").astype(np.float64) / 32768.0
        write_pcm16(enhanced_root / f"fileid_{file_id:03d}" / "enhanced.wav", clean)
        metrics = {"status": "PASS", "frames": 10, "end_to_end_rtf": 0.75}
        (enhanced_root / f"fileid_{file_id:03d}" / "metrics.json").write_text(
            json.dumps(metrics), encoding="utf-8"
        )

    inventory = evaluate(
        dataset, enhanced_root=None, expected_count=2, resamples=250
    )
    assert inventory["status"] == "READY"
    assert inventory["triplets"] == 2
    assert set(inventory["records"][0]["files"]) == {"clean", "noise", "noisy"}
    assert all("/" not in item["files"]["clean"]["name"] for item in inventory["records"])

    result = evaluate(
        dataset, enhanced_root=enhanced_root, expected_count=2, resamples=250
    )
    assert result["status"] == "PASS"
    assert result["summary"]["snr_delta_db"]["count"] == 2
    assert result["summary"]["snr_regression_ratio"] == 0.0
    assert result["records"][0]["board_metrics"]["end_to_end_rtf"] == 0.75
