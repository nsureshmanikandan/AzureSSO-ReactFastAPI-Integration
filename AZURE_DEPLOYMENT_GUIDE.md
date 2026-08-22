# Deploying to Azure

Companion to [LOCAL_RUN_GUIDE.md](LOCAL_RUN_GUIDE.md) - this is the "next step"
that guide pointed to. Verified working end-to-end on 2026-08-22: real sign-in,
real token, APIM validation, roles claim, all confirmed live - not just planned.

## Architecture

```
Browser (React/MSAL)
    | loginRedirect -> Microsoft sign-in -> back to SPA
    | "Call protected API" -> acquireTokenSilent (api://<client-id>/access_as_user)
    v
Static Web App (frontend/dist)
    | Bearer <token>
    v
APIM gateway (apim-itp-demo-dev.azure-api.net)
    | api-base-policy.xml   - CORS + routing, ALL operations (incl. /health)
    | validate-jwt-policy.xml - ALSO applied, /api/profile operation ONLY
    |   -> validates signature/issuer/audience/expiry
    |   -> strips Authorization, injects X-User-Id / X-User-Name / X-User-Roles
    v
Container App (FastAPI, TRUST_APIM_HEADERS=True)
    -> trusts the injected headers, never sees the raw token
```

Three separate Terraform states, applied in this order, by a human -
nothing here is applied by CI:
1. `infra/terraform/` - the SSO app registration (Entra ID / Graph only)
2. `infra/terraform-hosting/` - Resource Group, ACR, Container Apps
   Environment + Container App, Static Web App, **APIM**
3. Application code - built and deployed by `.github/workflows/deploy.yml`
   (GitHub Actions) into the infra that already exists

## 1. SSO app registration

```bash
cd infra/terraform
terraform init
terraform apply
```

Creates one combined app registration (`corpapps-<env>-itp-backend-apim-spn`)
that plays both the SPA and API roles, 8 App Roles, and demo AD groups - see
the header comment on `resource "azuread_application" "app"` for what it
actually does.

**Known footgun, hit repeatedly during this deployment**: any update to this
resource (even changing an unrelated field like `display_name` or
`redirect_uris`) silently resets `identifierUris` and `requiredResourceAccess`
back to empty on the real app, even though Terraform's own state still claims
they exist. **Always run `terraform plan` again immediately after any apply
here** - if it shows `azuread_application_identifier_uri.app` or
`azuread_application_api_access.*` need recreating, `apply` again right away
before considering the change done.

Grab the outputs:
```bash
terraform output backend_env      # AZURE_TENANT_ID, AZURE_API_CLIENT_ID
terraform output frontend_env     # VITE_* values for the SPA
terraform output role_group_object_ids   # add yourself to one to get a role
```

## 2. Hosting infra (Resource Group, ACR, Container App, Static Web App, APIM)

```bash
cd infra/terraform-hosting
terraform init
terraform apply
```

Needs `azure_tenant_id` / `azure_api_client_id` (from step 1's `backend_env`)
in a `*.auto.tfvars` file. Takes **8-12 minutes total** - the Container Apps
Environment is a few minutes, APIM (Consumption SKU - fastest tier to
provision) is the slowest part at ~2-3 minutes.

Creates:
- `rg-itp-demo-dev`, an Azure Container Registry (Basic, admin-enabled)
- Container Apps Environment + Container App, starting on a placeholder
  image - the pipeline replaces it with the real backend image on first
  deploy
- A Static Web App (Free SKU) - Azure Static Web Apps is **not available in
  every region** (only `centralus`, `eastus2`, `westus2`, `westeurope`,
  `eastasia` as of this writing); it has its own `static_web_app_location`
  variable, separate from the general `location` variable, for this reason
- APIM (`apim-itp-demo-dev`), one API (`itp-backend-api`), two operations
  (`GET /health`, `GET /api/profile`), and two policies - see below

**Before first apply, register the resource providers** if this is a fresh
subscription (`Microsoft.App` is required for Container Apps and is not
registered by default on every subscription):
```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

**Known footgun**: once the CI/CD pipeline has deployed a real image via
`az containerapp update`, running `terraform apply` here again for an
unrelated reason (e.g. adding APIM) will revert the Container App back to
the placeholder image, because Terraform doesn't know about the
out-of-band `az cli` update. `main.tf` already has
`lifecycle { ignore_changes = [template[0].container[0].image] }` on the
Container App resource to prevent this - don't remove it.

### APIM policy structure - why it's split into two files

`apim/api-base-policy.xml` is applied at the **API level** (every
operation, including the public `/health`). `apim/validate-jwt-policy.xml`
is applied at the **operation level**, on `/api/profile` only. This split
exists because:
- Applying `validate-jwt` at the API level would also block the
  intentionally-public `/health` endpoint.
- Azure API Management Named Values **cannot be an empty string** - an
  earlier version of the policy hardcoded a `"/" + "{{api-path-prefix}}" +
  ...` rewrite-uri assuming an empty prefix was valid, which is both
  rejected by Terraform's own validation and would have produced a
  double-slash path (`//health`) that FastAPI/Starlette wouldn't route
  correctly even if it were allowed. There is no rewrite-uri in the current
  policy at all, since the operation URL templates already match the
  backend's real paths exactly.
- The API resource also needs `subscription_required = false` - Azure
  defaults this to `true`, which rejects every request with a
  "missing subscription key" error regardless of a valid bearer token,
  since this design has no APIM product/subscription concept at all
  (auth is JWT-only).

Grab the outputs:
```bash
terraform output -raw apim_gateway_url            # https://apim-itp-demo-dev.azure-api.net
terraform output -raw acr_login_server
terraform output -raw static_web_app_default_hostname
terraform output -raw static_web_app_api_key      # secret - SWA deployment token
```

## 3. Wire up the GitHub Actions pipeline (one-time)

This repo uses GitHub Actions (`.github/workflows/deploy.yml`), not Azure
DevOps - `az acr build` (ACR Tasks) is blocked on some subscriptions
(confirmed on this one), and Docker/WSL2 may not be installed locally
either. GitHub's hosted runners have Docker built in, so the workflow does
a plain `docker build` + `docker push` instead of `az acr build`.

1. **Create a service principal** scoped to the resource group, for the
   pipeline to authenticate to Azure:
   ```bash
   az ad sp create-for-rbac --name "sp-itp-demo-github-actions" \
     --role Contributor \
     --scopes /subscriptions/<sub-id>/resourceGroups/rg-itp-demo-dev
   ```
2. **Set GitHub repo secrets** (`gh secret set NAME --body "value" -R <repo>`
   - use `--body`, not a piped string; piping a plain string through
   PowerShell's stdin appends a trailing newline that silently corrupts the
   secret value, which is exactly what happened to `ACR_LOGIN_SERVER` and
   `SWA_DEPLOYMENT_TOKEN` the first time):

   | Secret | Value |
   |---|---|
   | `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` | from the service principal above |
   | `ACR_LOGIN_SERVER` | `terraform output -raw acr_login_server` |
   | `ACR_USERNAME` / `ACR_PASSWORD` | `az acr credential show --name <acr-name>` |
   | `SWA_DEPLOYMENT_TOKEN` | `terraform output -raw static_web_app_api_key` |

3. **Hardcoded values in `deploy.yml`'s frontend build step** (`VITE_*` env
   vars) need updating if you change tenant/client ID or hostnames - they
   aren't parameterized as secrets since they aren't sensitive.

## 4. Run it

Push to `main` touching `backend/`, `frontend/`, or the workflow file
itself, or trigger manually:
```bash
gh workflow run deploy.yml -R <owner>/<repo>
gh run watch <run-id> -R <owner>/<repo> --exit-status
```

It will: install backend deps + `pytest`, `docker build`/`push` to ACR,
`az containerapp update` with the new image, `npm ci && npm run build` for
the frontend with real Azure AD values baked in, then deploy `frontend/dist`
to the Static Web App via `Azure/static-web-apps-deploy@v1`.

**Known footgun**: that action's `app_location`/`output_location` pair only
works one way for a pre-built (`skip_app_build: true`) deploy - set
`app_location: frontend/dist` and `output_location: ""` (empty). The
reversed combination (`app_location: frontend`, `output_location: dist`)
silently uploads the raw source `index.html` (which references
`/src/main.jsx` for Vite's dev server) instead of the actual built bundle,
producing a blank page with a browser console error about MIME type
`application/octet-stream` on a module script.

## 5. Test it live

```bash
curl -i https://apim-itp-demo-dev.azure-api.net/health
# {"status":"ok"} - public, no token needed

curl -i https://apim-itp-demo-dev.azure-api.net/api/profile
# 401 "Unauthorized - invalid or missing token" - correct, no token sent
```

Open the Static Web App URL, sign in, click "Call protected API
(/api/profile)". The response's `trust_path` field tells you which code
path the backend actually took:
- `"trust_path": "apim_headers"` - request went through APIM, APIM
  validated the real token, backend trusted the injected headers. This is
  the only value you should see once APIM is in front.
- Anything else / a raw-JWT-validation error - means the request bypassed
  APIM and hit the Container App directly, or `TRUST_APIM_HEADERS` isn't
  actually `True` on the deployed Container App - verify with:
  ```bash
  az containerapp show --name ca-itp-backend-dev --resource-group rg-itp-demo-dev \
    --query "properties.template.containers[0].env[?name=='TRUST_APIM_HEADERS']"
  ```

To see a non-empty `roles` array, add yourself to one of the demo groups
first (`terraform output role_group_object_ids` in `infra/terraform`), then
**sign all the way out and back in** - MSAL caches the access token for its
full lifetime, so just reloading the page or clicking the button again
reuses the same stale token and won't pick up a new role/group assignment
or app-registration change (like the `name` optional claim) until the
cache is cleared by a fresh sign-in.

## Known bugs fixed during this deployment (for reference)

| Symptom | Cause | Fix |
|---|---|---|
| Blank page, "MIME type application/octet-stream" console error | SWA deploy uploaded raw source instead of the Vite build | `app_location: frontend/dist`, `output_location: ""` |
| `loginPopup` hangs, popup shows "This site can't be reached" on `login.microsoft.com/consumers/fido/get` | Corporate network blocks the passkey/FIDO broker endpoint that popup-based MSAL flows probe | Switched to `loginRedirect` / `logoutRedirect` |
| APIM apply reverts Container App to placeholder image | Terraform doesn't know the CI pipeline updated the image via `az cli` out-of-band | `lifecycle { ignore_changes = [template[0].container[0].image] }` |
| `/health` requires a token even though it's meant to be public | `validate-jwt` policy applied at API level affects every operation | Split into API-level base policy (no auth) + operation-level auth policy on `/api/profile` only |
| Every APIM request rejected with "missing subscription key" | `azurerm_api_management_api.subscription_required` defaults to `true` | Set `subscription_required = false` |
| Terraform apply error: `expected "value" to not be an empty string` on a Named Value | Azure API Management Named Values cannot be empty; the policy's path-prefix rewrite assumed an empty prefix was valid | Removed the rewrite-uri entirely - operation URL templates already match the backend paths exactly |
| `az acr build` fails: `TasksOperationsNotAllowed` | ACR Tasks blocked on this subscription (common on trial/student subscriptions) | Build with plain `docker build`/`push` on a GitHub Actions hosted runner instead |
| GitHub secret silently wrong value despite being set correctly | `"value" \| gh secret set NAME` pipes through PowerShell's stdin, which appends a trailing newline | Use `gh secret set NAME --body "value"` instead |
| `/api/profile` shows the opaque subject ID as `"name"` instead of the real display name | Access tokens for a custom API audience don't include a `name` claim by default (unlike ID tokens), and the policy never forwarded one | Added `optional_claims.access_token { name = "name" }` on the app registration + an `X-User-Name` header in the policy |
| Identifier URI / API permissions silently empty after an unrelated app registration update | Confirmed azuread provider behavior - see the footgun note in section 1 | Always `terraform plan` again immediately after any apply touching `azuread_application.app`, reapply if drift shown |
