"""HMAC request authentication for the private sidecar.

Phoenix signs the raw JSON body with a shared secret. The signature covers the
body and a timestamp, so a captured request cannot be replayed later and a
caller cannot change the provider or its configuration in flight.
"""

import hashlib
import hmac
import os
import time
from typing import Final

from fastapi import Request
from starlette.responses import JSONResponse, Response

TOKEN_ENV: Final = "HIRAETH_SIDECAR_TOKEN"
TIMESTAMP_HEADER: Final = "x-hiraeth-timestamp"
SIGNATURE_HEADER: Final = "x-hiraeth-signature"
MAX_CLOCK_SKEW_SECONDS: Final = 300
_PUBLIC_PATHS: Final = {"/health", "/health/"}


def sign(secret: str, timestamp: str, body: bytes) -> str:
    """Return the lowercase hex HMAC for a timestamped body."""
    message = f"{timestamp}.".encode() + body
    return hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()


def _unauthorized() -> JSONResponse:
    return JSONResponse(
        status_code=401,
        content={
            "detail": {
                "code": "unauthorized",
                "message": "Sidecar request signature is missing or invalid",
            }
        },
    )


async def verify_signature(request: Request, call_next) -> Response:
    """Reject data requests that are not signed by the Phoenix service."""
    if request.method == "OPTIONS" or request.url.path in _PUBLIC_PATHS:
        return await call_next(request)

    secret = os.getenv(TOKEN_ENV)
    if not secret:
        return await call_next(request)

    timestamp = request.headers.get(TIMESTAMP_HEADER)
    signature = request.headers.get(SIGNATURE_HEADER)

    if not timestamp or not signature:
        return _unauthorized()

    try:
        signed_at = int(timestamp)
    except ValueError:
        return _unauthorized()

    if abs(int(time.time()) - signed_at) > MAX_CLOCK_SKEW_SECONDS:
        return _unauthorized()

    body = await request.body()
    expected = sign(secret, timestamp, body)

    if not hmac.compare_digest(expected, signature.lower()):
        return _unauthorized()

    return await call_next(request)
