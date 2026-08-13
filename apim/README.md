# APIM Configuration — Exact Steps

For the Infra / Platform team wiring FastAPI behind Azure API Management.

## Prerequisites

- An existing APIM instance (any tier that supports policies — Developer tier is fine for testing)
- The API App Registration already created (see the main setup guide, Step 2) — you need its **tenant ID** and **Application (client) ID**

## Steps

1. **Create the Named Values** (do this before applying the policy):
   - Azure Portal → your APIM instance → **Named values** (left nav, under APIs) → **+ Add**
   - Name: `tenant-id`, Value: your Entra ID tenant ID → **Save**
   - Name: `api-audience`, Value: the API App Registration's **Application ID URI**, copied verbatim from Azure Portal → App registrations → your API app → **Expose an API** → **Save**
     - Do NOT assume this is `api://<client-id>` — some orgs configure a custom URI instead (e.g. `https://<tenant>.onmicrosoft.com/<custom-spn-name>`). Copy whatever is actually shown in the portal, or every token will fail audience validation even with the correct tenant/client ID.
   - Name: `api-client-id`, Value: the same API App Registration's **bare Application (client) ID GUID** (no `api://` prefix) → **Save**
     - Needed because Azure AD issues two different token *versions* for the same app depending on who's requesting the token: v1.0 tokens carry the full Application ID URI as `aud`, v2.0 tokens carry the bare GUID. The policy's `<audiences>` block lists both so neither legitimate token format gets rejected — see the comment in `validate-jwt-policy.xml` for the full explanation (found via live testing, not theoretical).

2. **Import or select your API:**
   - APIM instance → **APIs** → either **+ Add API → HTTP** (point it at your FastAPI backend's base URL) or select your API if already imported
   - Set the **Web service URL** to where FastAPI actually runs (e.g. `https://ctc-orchestrator.azurecontainerapps.io` or your AKS ingress)

3. **Apply the policy:**
   - Select your API → **Design** tab → find the **Inbound processing** box → click the **</>** (code editor) icon
   - Replace the contents with `validate-jwt-policy.xml` from this folder
   - Click **Save**

4. **Confirm CORS origin matches your SPA:**
   - In the policy's `<cors>` section, confirm `http://localhost:5173` (dev) and your real production SPA URL are both listed under `<allowed-origins>`

5. **Test it:**
   ```bash
   # Should fail with 401 - no token
   curl -i https://<your-apim-name>.azure-api.net/<api-path>/api/profile

   # Should succeed - real token from the React app's login
   curl -i https://<your-apim-name>.azure-api.net/<api-path>/api/profile \
     -H "Authorization: Bearer <token from browser dev tools>"
   ```

6. **Point the React app at APIM instead of FastAPI directly:**
   - In `frontend/.env.local`, set `VITE_API_BASE_URL=https://<your-apim-name>.azure-api.net/<api-path>`

7. **Switch the backend to trust APIM's headers:**
   - In `backend/.env`, set `TRUST_APIM_HEADERS=True`
   - This tells FastAPI to read `X-User-Id` / `X-User-Roles` (injected by the policy) instead of re-validating the raw JWT itself — the token was already checked at the gateway.

## Why strip the Authorization header?

The policy's `<set-header name="Authorization" exists-action="delete" />` step means FastAPI **never sees the original bearer token** once APIM is in front — only the two derived headers. This is deliberate: it keeps the raw token from being logged or handled by anything downstream of the gateway, and it's why `TRUST_APIM_HEADERS=True` is safe — FastAPI is trusting APIM's validation, not re-trusting a token it can't even see.

## Common mistakes

- **Forgetting to create the Named Values first** — the policy will fail to save/apply with an error referencing `tenant-id`, `api-audience`, or `api-client-id` if they don't exist yet.
- **Audience mismatch** — `api-audience` must be the API app's *exact* Application ID URI from the "Expose an API" blade, matching what MSAL requested via `apiScopes` in the frontend (`authConfig.js`) and what `backend/.env`'s `AZURE_API_AUDIENCE` expects. A common mistake is assuming it's `api://<client-id>` when the org actually configured a custom URI (e.g. `https://<tenant>.onmicrosoft.com/<custom-spn-name>`) — copy the value from the portal, don't construct it.
- **CORS origin without protocol/port** — `localhost:5173` will not match; it must be `http://localhost:5173` exactly.
- **Rejecting a legitimate token because only one issuer/audience format was allowed** — a one-combined-registration app (SPA + API in the same registration, as used for this project) gets issued v1.0-format tokens (`sts.windows.net` issuer, URI-form audience) when it requests a token for itself, and v2.0-format tokens (`login.microsoftonline.com/.../v2.0` issuer, bare-GUID audience) otherwise. The policy's `<issuers>`/`<audiences>` blocks list both forms deliberately — don't "simplify" this down to one of each, or half of otherwise-valid logins will start failing with 401 at the gateway.
