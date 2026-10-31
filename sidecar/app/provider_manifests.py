"""Server-side provider policy for the private sidecar.

In secure mode the manifest on disk decides what a provider may reach. The
request names the provider and nothing else; the caller cannot widen the host
allowlist. Development keeps accepting inline adapter configuration so fixture
tests can exercise adapters without installing manifests.
"""

import json
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Final

from app.models import JsonObject, SidecarErrorCode, sidecar_http_error

MANIFESTS_DIR_ENV: Final = "HIRAETH_PROVIDER_MANIFESTS_DIR"
SECURE_MODE_ENV: Final = "HIRAETH_SIDECAR_REQUIRE_SECURE"
_PROVIDER_SLUG: Final = re.compile(r"^[a-z0-9_]+$")


def secure_mode() -> bool:
    """Return true when the sidecar must own provider policy."""
    return os.getenv(SECURE_MODE_ENV) == "1"


def manifests_dir() -> Path:
    """Resolve the manifest directory without depending on the process cwd."""
    configured = os.getenv(MANIFESTS_DIR_ENV)
    if configured:
        return Path(configured)

    repo_manifests = (
        Path(__file__).resolve().parents[2] / "priv" / "catalog_sources" / "provider_manifests"
    )
    if repo_manifests.is_dir():
        return repo_manifests

    return Path(__file__).resolve().parents[1] / "manifests"


def provider_config(provider: str, request_config: JsonObject) -> JsonObject:
    """Return the manifest the sidecar will act on for a provider."""
    if secure_mode():
        return {**load_manifest(provider), "provider": provider}

    return {**request_config, "provider": provider}


@lru_cache(maxsize=64)
def load_manifest(provider: str) -> JsonObject:
    """Load and validate one checked-in provider manifest."""
    if not _PROVIDER_SLUG.fullmatch(provider):
        raise sidecar_http_error(
            422,
            SidecarErrorCode.PROVIDER_UNKNOWN,
            "Provider slug is invalid",
        )

    path = manifests_dir() / f"{provider}.json"

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise sidecar_http_error(
            422,
            SidecarErrorCode.PROVIDER_UNKNOWN,
            f"No server-side manifest for provider {provider}",
        ) from error
    except (OSError, json.JSONDecodeError) as error:
        raise sidecar_http_error(
            500,
            SidecarErrorCode.INTERNAL_ERROR,
            f"Server-side manifest for provider {provider} is unreadable",
        ) from error

    if not isinstance(data, dict):
        raise sidecar_http_error(
            500,
            SidecarErrorCode.INTERNAL_ERROR,
            f"Server-side manifest for provider {provider} is not an object",
        )

    return data


def validate_secure_configuration() -> None:
    """Fail fast when secure mode is declared without its policy or secret."""
    if not secure_mode():
        return

    if not os.getenv("HIRAETH_SIDECAR_TOKEN"):
        raise RuntimeError("HIRAETH_SIDECAR_TOKEN is required when secure mode is enabled")

    directory = manifests_dir()
    if not directory.is_dir() or not any(directory.glob("*.json")):
        raise RuntimeError(
            f"no provider manifests found in {directory}; set HIRAETH_PROVIDER_MANIFESTS_DIR"
        )
