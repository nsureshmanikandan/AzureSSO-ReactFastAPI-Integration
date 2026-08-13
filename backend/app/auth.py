"""Two ways this backend can trust a caller, matching the CTC architecture's
defense-in-depth identity pattern:

  1. APIM validate-jwt already checked the token at the gateway and forwards
     X-User-Id / X-User-Roles headers, with the raw Authorization header
     stripped (see apim/validate-jwt-policy.xml). The backend just reads
     those headers. This is the production path once APIM is in front.

  2. No APIM in the path yet (local dev, or you want the backend to double-
     check independently) - the backend validates the Bearer JWT itself
     against Entra ID's public signing keys (JWKS). This is the
     `validate_token()` / `get_current_user()` path below.

Both paths produce the same `CurrentUser` shape, so route handlers never
need to know or care which one is active.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Optional

import httpx
from fastapi import Depends, Header, HTTPException, Request
from jose import jwt
from jose.exceptions import JOSEError

from app.config import settings


@dataclass
class CurrentUser:
    subject: str                       # "sub" claim - stable unique user id
    name: Optional[str] = None
    roles: list[str] = field(default_factory=list)
    raw_claims: dict[str, Any] = field(default_factory=dict)


class JWKSClient:
    """Fetches and caches Entra ID's public signing keys.

    Cached for `ttl_seconds` so we're not round-tripping to Microsoft on
    every single request - keys rotate rarely, a short cache is plenty.
    Constructed as an instance (not a bare module-level cache) specifically
    so tests can substitute a fake one instead of hitting the real network.
    """

    def __init__(self, jwks_uri: str, ttl_seconds: int = 3600) -> None:
        self._jwks_uri = jwks_uri
        self._ttl_seconds = ttl_seconds
        self._cached_keys: Optional[list[dict]] = None
        self._cached_at: float = 0.0

    def get_keys(self) -> list[dict]:
        now = time.monotonic()
        if self._cached_keys is None or (now - self._cached_at) > self._ttl_seconds:
            response = httpx.get(self._jwks_uri, timeout=5.0)
            response.raise_for_status()
            self._cached_keys = response.json()["keys"]
            self._cached_at = now
        return self._cached_keys

    def find_key(self, kid: str) -> Optional[dict]:
        for key in self.get_keys():
            if key.get("kid") == kid:
                return key
        # Key not found - could be legitimate rotation. Force one refetch
        # before giving up, in case our cache is simply stale.
        self._cached_keys = None
        for key in self.get_keys():
            if key.get("kid") == kid:
                return key
        return None


_jwks_client = JWKSClient(settings.jwks_uri)


def get_jwks_client() -> JWKSClient:
    """Overridden in tests via dependency injection / monkeypatching to
    avoid real network calls to Microsoft's endpoint."""
    return _jwks_client


def validate_token(token: str, jwks_client: Optional[JWKSClient] = None) -> dict:
    """Validate an Entra ID-issued access token. Returns the decoded claims.

    Raises HTTPException(401) on anything wrong - expired, wrong audience,
    wrong issuer, bad signature, unknown key ID. Never returns partial trust.
    """
    client = jwks_client or get_jwks_client()

    try:
        unverified_header = jwt.get_unverified_header(token)
    except JOSEError as exc:
        raise HTTPException(status_code=401, detail=f"malformed token: {exc}") from exc

    kid = unverified_header.get("kid")
    if not kid:
        raise HTTPException(status_code=401, detail="token header missing 'kid'")

    try:
        signing_key = client.find_key(kid)
    except httpx.HTTPError as exc:
        # A failed JWKS fetch (bad tenant ID, network issue, Microsoft outage)
        # must still return a clean HTTPException - letting it propagate as a
        # raw exception skips the CORS middleware entirely, which then shows
        # up in the browser as a misleading "blocked by CORS policy" error
        # instead of the real cause.
        raise HTTPException(status_code=401, detail=f"unable to fetch signing keys: {exc}") from exc
    if signing_key is None:
        raise HTTPException(status_code=401, detail="signing key not found for this token")

    try:
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            # Issuer AND audience are both checked manually below instead of
            # via jose's built-in single-string checks. Azure AD legitimately
            # issues either v1.0 (sts.windows.net issuer, api://<id> audience)
            # or v2.0 (login.microsoftonline.com/.../v2.0 issuer, bare <id>
            # audience) format tokens for the same real tenant/app, depending
            # on whether a token was requested by a different client or by
            # the app requesting a token for itself - one combined app
            # playing both the SPA and API roles, as configured here.
            options={"verify_at_hash": False, "verify_iss": False, "verify_aud": False},
        )
    except JOSEError as exc:
        unverified = jwt.get_unverified_claims(token)
        raise HTTPException(
            status_code=401,
            detail=f"token validation failed: {exc} | token had iss={unverified.get('iss')!r} aud={unverified.get('aud')!r}",
        ) from exc

    if claims.get("iss") not in settings.valid_issuers:
        raise HTTPException(
            status_code=401,
            detail=(
                f"token validation failed: Invalid issuer | "
                f"expected one of {sorted(settings.valid_issuers)!r} | "
                f"token had iss={claims.get('iss')!r}"
            ),
        )

    if claims.get("aud") not in settings.valid_audiences:
        raise HTTPException(
            status_code=401,
            detail=(
                f"token validation failed: Invalid audience | "
                f"expected one of {sorted(settings.valid_audiences)!r} | "
                f"token had aud={claims.get('aud')!r}"
            ),
        )

    return claims


def _claims_to_user(claims: dict) -> CurrentUser:
    roles = claims.get("roles", [])
    return CurrentUser(
        subject=claims.get("sub", ""),
        name=claims.get("name"),
        roles=roles if isinstance(roles, list) else [roles],
        raw_claims=claims,
    )


async def get_current_user(
    request: Request,
    authorization: Optional[str] = Header(default=None),
    x_user_id: Optional[str] = Header(default=None, alias="X-User-Id"),
    x_user_roles: Optional[str] = Header(default=None, alias="X-User-Roles"),
) -> CurrentUser:
    """FastAPI dependency - use as `user: CurrentUser = Depends(get_current_user)`."""

    if settings.trust_apim_headers:
        # Path 1: APIM already validated the token and stripped the raw
        # Authorization header. If X-User-Id is missing here, either APIM
        # isn't actually in front of this request, or its policy isn't
        # configured to inject it - fail closed, don't guess.
        if not x_user_id:
            raise HTTPException(
                status_code=401,
                detail="trust_apim_headers=True but X-User-Id header is missing - "
                "check the APIM validate-jwt policy is applied and forwarding it",
            )
        roles = x_user_roles.split(",") if x_user_roles else []
        return CurrentUser(subject=x_user_id, name=x_user_id, roles=roles, raw_claims={})

    # Path 2: validate the raw bearer token ourselves.
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing Authorization: Bearer <token> header")
    token = authorization.split(" ", 1)[1]
    claims = validate_token(token)
    return _claims_to_user(claims)


def require_role(role: str):
    """Route dependency factory: `Depends(require_role("Admin"))`.

    Chains onto get_current_user via Depends() so it still works whichever
    trust path (APIM headers vs raw JWT) is active - this only adds a role
    check on top, it doesn't duplicate the identity logic above.
    """

    async def _check(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if role not in user.roles:
            raise HTTPException(status_code=403, detail=f"requires role '{role}'")
        return user

    return _check
