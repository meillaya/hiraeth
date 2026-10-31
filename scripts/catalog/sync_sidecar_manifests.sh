#!/usr/bin/env bash
# Copy the governed provider manifests into the sidecar build context.
#
# The sidecar image is built from sidecar/ so it cannot read priv/. Secure mode
# refuses to start without these manifests, and tests/test_manifest_sync.py
# fails when the copies drift from the source of truth.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${ROOT}/priv/catalog_sources/provider_manifests"
TARGET="${ROOT}/sidecar/manifests"

[[ -d "${SOURCE}" ]] || { echo "ERROR: ${SOURCE} is missing" >&2; exit 1; }
[[ "${TARGET}" == "${ROOT}/sidecar/manifests" ]] || { echo "ERROR: refusing target ${TARGET}" >&2; exit 1; }

mkdir -p "${TARGET}"
find "${TARGET}" -maxdepth 1 -name '*.json' -delete
cp "${SOURCE}"/*.json "${TARGET}/"
echo "synced $(find "${TARGET}" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ') manifests to ${TARGET}"
