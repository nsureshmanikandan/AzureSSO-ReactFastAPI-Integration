# Running AzureSSO-ReactFastAPI-Integration Locally

Verified working end-to-end on 2026-08-13: 6/6 backend tests pass, backend
serves `/health` (200) and `/api/profile` (401 without a token), frontend
Vite dev server builds and serves (200).

## 1. Backend (FastAPI)

```bash
cd backend
python -m venv .venv

# Windows
.venv\Scripts\activate
# macOS/Linux
source .venv/bin/activate

pip install -r requirements.txt
cp .env.example .env
```

Local dev does **not** need real Azure AD values in `.env` yet — the
defaults are enough because `TRUST_APIM_HEADERS=False` means the backend
only checks the real JWT when a real `Authorization: Bearer <token>` header
is actually sent. Health checks and "no token" checks work with the
placeholder IDs as-is.

Run the server:
```bash
uvicorn app.main:app --reload --port 8000
```

Check it's alive (separate terminal):
```bash
curl http://localhost:8000/health
# {"status":"ok"}

curl -i http://localhost:8000/api/profile
# HTTP/1.1 401 Unauthorized - correct, no token was sent
```

### Running `test_auth.py` specifically

```bash
cd backend
.venv\Scripts\activate          # if not already active
python -m pytest tests/test_auth.py -v
```

Expected output — 6 passed:
```
tests/test_auth.py::test_valid_token_is_accepted PASSED
tests/test_auth.py::test_expired_token_is_rejected PASSED
tests/test_auth.py::test_wrong_audience_is_rejected PASSED
tests/test_auth.py::test_wrong_issuer_is_rejected PASSED
tests/test_auth.py::test_tampered_signature_is_rejected PASSED
tests/test_auth.py::test_unknown_kid_is_rejected PASSED
```

These tests do **not** call the real Microsoft/Entra ID network endpoint —
they generate a throwaway self-signed RSA keypair in-memory and swap in a
`FakeJWKSClient`, so they run offline and don't need any real tenant.

To run the whole backend test suite instead of just this one file:
```bash
python -m pytest -q
```

## 2. Frontend (React + MSAL)

```bash
cd frontend
npm install
cp .env.example .env.local
```

For local dev without a real Azure AD app registered yet, the frontend will
still start and render the login screen — clicking "Sign in with Microsoft"
will fail until `.env.local` has real `VITE_AZURE_CLIENT_ID` /
`VITE_AZURE_TENANT_ID` values (Section 4 of the master setup guide covers
creating those).

```bash
npm run dev
```
Open http://localhost:5173 (or whatever port Vite reports).

## 3. Common local issues

| Symptom | Cause | Fix |
|---|---|---|
| `curl: (7) Failed to connect` right after starting uvicorn | Server needs a second or two to finish startup | Wait ~2-3s after starting before curling |
| `[Errno 10048] only one usage of each socket address` | A previous `uvicorn`/`vite` instance is still bound to that port | Find and stop the old process, or use a different `--port` |
| `/api/profile` returns 401 even with a token | `AZURE_TENANT_ID`/`AZURE_API_CLIENT_ID` in `backend/.env` are still the placeholder zeros | Fill in real values once the App Registrations exist (Section 4-4.2 of the master guide) |
| Frontend build/dev fails with a top-level `await` error | Not applicable here - already fixed in `frontend/src/main.jsx` via the `bootstrap()` wrapper | N/A, just confirming the fix holds |

## Next: deploying to Azure

Once local run is confirmed (as above), the natural next step is standing
up real Azure resources - an APIM instance, a hosted backend (Container Apps
or App Service), and a hosted frontend (Static Web App or Storage+CDN) - and
re-running the same tests against the deployed, real endpoints. See the
companion `AZURE_DEPLOYMENT_GUIDE.md` (to be added) for that phase.
