"""Tests for token validation, against a self-signed test keypair - no real
Azure tenant, no network calls. This proves the validation LOGIC is correct
(signature check, expiry check, audience check, issuer check) independently
of whether your real Entra ID app registrations are set up yet.
"""
from __future__ import annotations

import time

import pytest
from jose import jwt as jose_jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

from app.auth import JWKSClient, validate_token
from app.config import settings
from fastapi import HTTPException


TEST_KID = "test-key-1"


def _generate_test_keypair():
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_key = private_key.public_key()

    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()

    public_numbers = public_key.public_numbers()
    jwk = {
        "kty": "RSA",
        "kid": TEST_KID,
        "use": "sig",
        "alg": "RS256",
        "n": _int_to_b64url(public_numbers.n),
        "e": _int_to_b64url(public_numbers.e),
    }
    return private_pem, jwk


def _int_to_b64url(value: int) -> str:
    import base64

    byte_length = (value.bit_length() + 7) // 8
    raw = value.to_bytes(byte_length, "big")
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


@pytest.fixture(scope="module")
def keypair():
    return _generate_test_keypair()


class FakeJWKSClient(JWKSClient):
    """A JWKSClient that returns our test key instead of calling Microsoft."""

    def __init__(self, jwk: dict) -> None:
        super().__init__(jwks_uri="unused://test")
        self._jwk = jwk

    def get_keys(self) -> list[dict]:
        return [self._jwk]


def _make_token(private_pem: str, *, exp_offset_s: int = 3600, audience: str | None = None, issuer: str | None = None) -> str:
    now = int(time.time())
    claims = {
        "sub": "user-123",
        "name": "Test User",
        "roles": ["Requestor"],
        "iat": now,
        "exp": now + exp_offset_s,
        "aud": audience if audience is not None else settings.expected_audience,
        "iss": issuer if issuer is not None else settings.issuer,
    }
    return jose_jwt.encode(claims, private_pem, algorithm="RS256", headers={"kid": TEST_KID})


def test_valid_token_is_accepted(keypair):
    private_pem, jwk = keypair
    token = _make_token(private_pem)
    client = FakeJWKSClient(jwk)

    claims = validate_token(token, jwks_client=client)

    assert claims["sub"] == "user-123"
    assert claims["name"] == "Test User"
    assert claims["roles"] == ["Requestor"]


def test_expired_token_is_rejected(keypair):
    private_pem, jwk = keypair
    token = _make_token(private_pem, exp_offset_s=-60)  # expired 60s ago
    client = FakeJWKSClient(jwk)

    with pytest.raises(HTTPException) as exc_info:
        validate_token(token, jwks_client=client)
    assert exc_info.value.status_code == 401


def test_wrong_audience_is_rejected(keypair):
    private_pem, jwk = keypair
    token = _make_token(private_pem, audience="some-other-api-client-id")
    client = FakeJWKSClient(jwk)

    with pytest.raises(HTTPException) as exc_info:
        validate_token(token, jwks_client=client)
    assert exc_info.value.status_code == 401


def test_wrong_issuer_is_rejected(keypair):
    private_pem, jwk = keypair
    token = _make_token(private_pem, issuer="https://login.microsoftonline.com/some-other-tenant/v2.0")
    client = FakeJWKSClient(jwk)

    with pytest.raises(HTTPException) as exc_info:
        validate_token(token, jwks_client=client)
    assert exc_info.value.status_code == 401


def test_tampered_signature_is_rejected(keypair):
    private_pem, jwk = keypair
    token = _make_token(private_pem)
    tampered = token[:-4] + ("AAAA" if not token.endswith("AAAA") else "BBBB")
    client = FakeJWKSClient(jwk)

    with pytest.raises(HTTPException) as exc_info:
        validate_token(tampered, jwks_client=client)
    assert exc_info.value.status_code == 401


def test_unknown_kid_is_rejected(keypair):
    private_pem, jwk = keypair
    # Sign with a kid that won't be found in the (empty) key set.
    now = int(time.time())
    claims = {"sub": "x", "iat": now, "exp": now + 3600, "aud": settings.expected_audience, "iss": settings.issuer}
    token = jose_jwt.encode(claims, private_pem, algorithm="RS256", headers={"kid": "no-such-key"})
    client = FakeJWKSClient(jwk)  # only has TEST_KID, not "no-such-key"

    with pytest.raises(HTTPException) as exc_info:
        validate_token(token, jwks_client=client)
    assert exc_info.value.status_code == 401
