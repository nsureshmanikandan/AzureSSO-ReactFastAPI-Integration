"""Sample FastAPI backend for the React + Entra ID (Azure AD) SSO walkthrough.

Two protected endpoints show both trust paths:
  GET /api/profile  - works with either trust path (whichever is on in .env)
  GET /health       - public, no auth, for load balancer / APIM health probes

Run locally (no APIM in front): trust_apim_headers=False in .env, call this
directly from React on http://localhost:8000, with a real Bearer token from
MSAL - see frontend/README.md.
"""
from __future__ import annotations

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.auth import CurrentUser, get_current_user
from app.config import settings

app = FastAPI(
    title="CTC Sample API - Azure AD SSO Integration",
    description="Minimal working backend for the React + MSAL + APIM + FastAPI SSO setup guide.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    """Public - no token required. APIM / your load balancer should hit this."""
    return {"status": "ok"}


@app.get("/api/profile")
async def profile(user: CurrentUser = Depends(get_current_user)):
    """Protected - requires a valid Entra ID token (or trusted APIM headers).

    This is the endpoint the React sample app calls after login - if you see
    your name/roles come back here, the whole chain (MSAL -> APIM ->
    FastAPI) is wired correctly end to end.
    """
    return {
        "subject": user.subject,
        "name": user.name,
        "roles": user.roles,
        "trust_path": "apim_headers" if settings.trust_apim_headers else "direct_jwt_validation",
    }
