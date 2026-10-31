"""The sidecar image ships its own manifest copies; they must match the source."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "priv" / "catalog_sources" / "provider_manifests"
SIDECAR_DIR = REPO_ROOT / "sidecar" / "manifests"


def test_sidecar_manifests_match_the_governed_source() -> None:
    # Given: the governed manifests under priv and their sidecar build copies.
    source_files = {path.name: path for path in SOURCE_DIR.glob("*.json")}
    sidecar_files = {path.name: path for path in SIDECAR_DIR.glob("*.json")}

    # Then: the copy is complete and byte-identical, so policy cannot drift.
    assert source_files.keys() == sidecar_files.keys()

    for name, source_path in source_files.items():
        assert sidecar_files[name].read_bytes() == source_path.read_bytes(), name
