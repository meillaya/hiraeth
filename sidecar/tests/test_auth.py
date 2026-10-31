"""Tests for the sidecar request signature and server-side provider policy."""

from __future__ import annotations

import hashlib
import hmac
import json
import time
from pathlib import Path

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app import auth, provider_manifests
from app.main import app
from app.models import SidecarErrorCode


def _signature(secret: str, timestamp: str, body: bytes) -> str:
    message = f"{timestamp}.".encode() + body
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def _signed_headers(secret: str, body: bytes) -> dict[str, str]:
    timestamp = str(int(time.time()))

    return {
        "content-type": "application/json",
        auth.TIMESTAMP_HEADER: timestamp,
        auth.SIGNATURE_HEADER: _signature(secret, timestamp, body),
    }


def _write_manifest(directory: Path, provider: str, source_hosts: list[str]) -> None:
    (directory / f"{provider}.json").write_text(
        json.dumps(
            {
                "provider": provider,
                "source_hosts": source_hosts,
                "cover_hosts": source_hosts,
                "api": {"type": "shopify", "endpoint": f"https://{source_hosts[0]}/api"},
            }
        ),
        encoding="utf-8",
    )


@pytest.fixture(autouse=True)
def _clear_manifest_cache() -> None:
    provider_manifests.load_manifest.cache_clear()
    yield
    provider_manifests.load_manifest.cache_clear()


def test_unsigned_data_request_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given: a sidecar configured with a shared secret.
    monkeypatch.setenv(auth.TOKEN_ENV, "test-secret")

    # When: a caller posts without a signature.
    response = TestClient(app).post(
        "/fetch/",
        json={"provider": "test_press", "config": {}},
    )

    # Then: the request is rejected with the typed unauthorized envelope.
    assert response.status_code == 401
    assert response.json()["detail"]["code"] == SidecarErrorCode.UNAUTHORIZED.value


def test_signed_data_request_is_accepted(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given: a sidecar configured with a shared secret.
    secret = "test-secret"
    monkeypatch.setenv(auth.TOKEN_ENV, secret)
    body = json.dumps({"provider": "test_press", "config": {}}).encode()

    # When: Phoenix signs the raw body and timestamp.
    response = TestClient(app).post(
        "/fetch/",
        content=body,
        headers=_signed_headers(secret, body),
    )

    # Then: authentication passes and the handler's own validation runs.
    assert response.status_code != 401


def test_stale_signature_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given: a signed body with a timestamp well outside the allowed skew.
    secret = "test-secret"
    monkeypatch.setenv(auth.TOKEN_ENV, secret)
    body = json.dumps({"provider": "test_press", "config": {}}).encode()
    timestamp = str(int(time.time()) - auth.MAX_CLOCK_SKEW_SECONDS - 1)

    response = TestClient(app).post(
        "/fetch/",
        content=body,
        headers={
            "content-type": "application/json",
            auth.TIMESTAMP_HEADER: timestamp,
            auth.SIGNATURE_HEADER: _signature(secret, timestamp, body),
        },
    )

    # Then: replay outside the window is rejected.
    assert response.status_code == 401


def test_health_stays_public(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given: a sidecar with a shared secret.
    monkeypatch.setenv(auth.TOKEN_ENV, "test-secret")

    # When: the platform health probe calls without a signature.
    response = TestClient(app).get("/health/")

    # Then: the probe still answers.
    assert response.status_code == 200


def test_secure_mode_uses_the_server_manifest(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    # Given: secure mode and a manifest that allows one host.
    _write_manifest(tmp_path, "test_press", ["example.com"])
    monkeypatch.setenv(provider_manifests.SECURE_MODE_ENV, "1")
    monkeypatch.setenv(provider_manifests.MANIFESTS_DIR_ENV, str(tmp_path))
    monkeypatch.setenv(auth.TOKEN_ENV, "test-secret")

    # When: the caller tries to widen the allowlist in the request.
    config = provider_manifests.provider_config(
        "test_press",
        {"source_hosts": ["metadata.google.internal"]},
    )

    # Then: the server manifest wins.
    assert config["source_hosts"] == ["example.com"]


def test_secure_mode_rejects_an_unknown_provider(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    # Given: secure mode with one manifest installed.
    _write_manifest(tmp_path, "test_press", ["example.com"])
    monkeypatch.setenv(provider_manifests.SECURE_MODE_ENV, "1")
    monkeypatch.setenv(provider_manifests.MANIFESTS_DIR_ENV, str(tmp_path))

    # When/Then: naming a provider without a manifest is a typed rejection.
    with pytest.raises(HTTPException) as raised:
        provider_manifests.load_manifest("unknown_provider")

    assert raised.value.status_code == 422
    assert raised.value.detail["code"] == SidecarErrorCode.PROVIDER_UNKNOWN.value


def test_secure_mode_requires_a_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given: secure mode without a token.
    monkeypatch.setenv(provider_manifests.SECURE_MODE_ENV, "1")
    monkeypatch.delenv(auth.TOKEN_ENV, raising=False)

    # Then: startup validation fails with a named error.
    with pytest.raises(RuntimeError, match="HIRAETH_SIDECAR_TOKEN"):
        provider_manifests.validate_secure_configuration()
