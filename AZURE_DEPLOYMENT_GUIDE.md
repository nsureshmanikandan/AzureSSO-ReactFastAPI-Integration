# Deploying to Azure

Companion to [LOCAL_RUN_GUIDE.md](LOCAL_RUN_GUIDE.md) - this is the "next step"
that guide pointed to. Two layers, provisioned separately on purpose:

1. **Infra** (`infra/terraform-hosting/`) - Resource Group, Azure Container
   Registry, Container Apps Environment + Container App (backend), Static
   Web App (frontend). Provisioned once, by a human, ahead of time.
2. **Code** (`pipelines/azure-pipelines.yml`) - builds and deploys the
   backend image and frontend bundle into infra that already exists. Runs
   on every push to `main` that touches `backend/` or `frontend/`.

The SSO app registration itself (`infra/terraform/`) is a third, separate
piece - already covered by its own setup. This guide assumes that's done
and you have its outputs (`terraform output backend_env` / `frontend_env`).

## 1. Provision the hosting infra (one-time)

```bash
cd infra/terraform-hosting
terraform init
terraform apply
```

You'll be asked for `azure_tenant_id` and `azure_api_client_id` if they
aren't already in a `*.auto.tfvars` file - use the values from
`infra/terraform`'s `backend_env` output.

This takes **5-10 minutes**, mostly the Container Apps Environment. It
creates:
- `rg-itp-demo-dev` (Resource Group)
- An Azure Container Registry (Basic SKU, admin access enabled for the
  pipeline to push to)
- A Container Apps Environment + a Container App running a placeholder
  image (`mcr.microsoft.com/azuredocs/containerapps-helloworld`) - the
  pipeline replaces this with the real backend image on first deploy
- A Static Web App (Free SKU) for the frontend

Grab the outputs you'll need for the pipeline and for testing:
```bash
terraform output -raw acr_login_server
terraform output azurerm_container_app.backend  # or: az containerapp show ...
terraform output -raw static_web_app_default_hostname
terraform output -raw static_web_app_api_key      # secret - the SWA deployment token
```

(If `outputs.tf` doesn't have these yet, add them - see the end of this
file for the exact block.)

## 2. Wire up the Azure DevOps pipeline (one-time)

1. **Service connection**: Project Settings -> Service connections -> New
   -> Azure Resource Manager, scoped to the resource group
   `rg-itp-demo-dev`. Name it anything - you'll reference that name as the
   `azureServiceConnection` pipeline variable.
2. **Create the pipeline**: Pipelines -> New pipeline -> point it at
   `pipelines/azure-pipelines.yml` in this repo.
3. **Pipeline variables** (Edit -> Variables), matching the comment block
   at the top of `azure-pipelines.yml`:

   | Variable | Value | Secret? |
   |---|---|---|
   | `azureServiceConnection` | the service connection name from step 1 | no |
   | `resourceGroupName` | `rg-itp-demo-dev` | no |
   | `acrLoginServer` | `terraform output -raw acr_login_server` | no |
   | `containerAppName` | `ca-itp-backend-dev` | no |
   | `swaDeploymentToken` | `terraform output -raw static_web_app_api_key` | **yes** |
   | `viteAzureClientId` | `infra/terraform`'s `frontend_env` -> `VITE_AZURE_CLIENT_ID` | no |
   | `viteAzureTenantId` | same output -> `VITE_AZURE_TENANT_ID` | no |
   | `viteRedirectUri` | your real hosted SPA URL, e.g. `https://<swa-hostname>/` | no |
   | `viteApiScope` | same output -> `VITE_API_SCOPE` | no |
   | `apiBaseUrl` | `https://<containerAppName>.<region>.azurecontainerapps.io` (get exact FQDN via `az containerapp show -n ca-itp-backend-dev -g rg-itp-demo-dev --query properties.configuration.ingress.fqdn -o tsv`) | no |

4. **Add the hosted redirect URI to the app registration** - the SPA is
   now served from the Static Web App's real URL, not just
   `localhost:5173`. Add it in `infra/terraform`'s `redirect_uris` variable
   and re-apply (see the drift warning comment in `main.tf` - plan again
   right after to confirm nothing else got reset).
5. **Add the SWA origin to CORS** - update `allowed_origins` in
   `infra/terraform-hosting`'s tfvars and `terraform apply` again (this
   updates the Container App's `ALLOWED_ORIGINS` env var).

## 3. Run it

Push to `main` (touching `backend/` or `frontend/`), or run the pipeline
manually. It will:
- Install backend deps, run `pytest`
- `az acr build` (builds the Docker image *in* ACR - no local Docker
  needed on the agent)
- `az containerapp update` with the new image
- `npm ci && npm run build` for the frontend, with the real Azure AD
  values baked in as Vite env vars
- Deploy the built `frontend/dist` to the Static Web App

## 4. Test it live

```bash
curl -i https://<containerAppName>.<region>.azurecontainerapps.io/health
# {"status":"ok"}
```

Open `https://<swa-hostname>/`, sign in with Microsoft, confirm
`/api/profile` returns your name and the `roles` claim from whichever demo
AD group (`terraform output role_group_object_ids`) you added yourself to.

## 5. Not yet wired: APIM

The `apim/` folder's `validate-jwt-policy.xml` is not deployed by this
guide - right now the frontend calls the Container App directly
(`TRUST_APIM_HEADERS=False`, same as local dev). Putting APIM in front
(Consumption SKU is the fastest/cheapest tier to provision for testing) is
a follow-up phase: stand up the APIM instance, import the Container App as
its backend, create the Named Values (`tenant-id`, `api-audience`,
`api-client-id`, `backend-id`) per `apim/README.md`, apply the policy, then
flip `TRUST_APIM_HEADERS=True` and point the frontend's `VITE_API_BASE_URL`
at the APIM gateway URL instead of the Container App's FQDN directly.
