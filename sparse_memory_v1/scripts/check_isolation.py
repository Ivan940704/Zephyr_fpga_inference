#!/usr/bin/env python3
"""Fail closed when the sparse-memory isolation boundary is violated."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
PREFIX = "sparse_memory_v1/"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def import_entries() -> list[tuple[str, Path]]:
    entries: list[tuple[str, Path]] = []
    manifest = ROOT / "IMPORT_SHA256SUMS"
    for number, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        expected, relative = raw.split(maxsplit=1)
        relative = relative.lstrip(" *")
        target = ROOT / relative
        if not target.is_file():
            raise AssertionError(f"missing import at line {number}: {relative}")
        entries.append((expected, target))
    return entries


def check_imports() -> None:
    for expected, target in import_entries():
        actual = sha256(target)
        if actual != expected:
            raise AssertionError(f"import hash mismatch: {target.relative_to(ROOT)}")


def check_no_symlinks() -> None:
    links = [path for path in ROOT.rglob("*") if path.is_symlink()]
    if links:
        raise AssertionError("symlinks are forbidden: " + ", ".join(map(str, links)))


def check_compile_allowlists() -> None:
    for manifest in ROOT.glob("compile_*.f"):
        for number, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
            entry = raw.strip()
            if not entry or entry.startswith("#"):
                continue
            resolved = (ROOT / entry).resolve()
            try:
                resolved.relative_to(ROOT.resolve())
            except ValueError as error:
                raise AssertionError(f"external compile path {manifest.name}:{number}") from error
            if not resolved.is_file():
                raise AssertionError(f"missing compile source {manifest.name}:{number}: {entry}")


def check_staged_paths() -> None:
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        cwd=REPO,
        check=True,
        text=True,
        capture_output=True,
    )
    bad = [path for path in result.stdout.splitlines() if path and not path.startswith(PREFIX)]
    if bad:
        raise AssertionError("staged paths escape sparse boundary: " + ", ".join(bad))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--staged", action="store_true", help="also validate staged Git paths")
    args = parser.parse_args()
    check_no_symlinks()
    check_imports()
    check_compile_allowlists()
    if args.staged:
        check_staged_paths()
    print(f"SPARSE_MEMORY_ISOLATION_PASS imports={len(import_entries())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

