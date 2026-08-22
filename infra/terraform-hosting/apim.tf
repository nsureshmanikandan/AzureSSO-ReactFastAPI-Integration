# APIM in front of the Container App, applying the org's real validate-jwt
# pattern (apim/validate-jwt-policy.xml) instead of the backend trusting a
# raw bearer token directly. Consumption SKU - cheapest/fastest tier to
# provision for a demo (still several minutes, unlike Developer/Premium
# which take 30-45 min).

resource "azurerm_api_management" "main" {
  name                = "apim-itp-demo-${var.environment}"
  location             = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name       = "ITP Demo"
  publisher_email      = "n.sureshmanikandan@accenture.com"
  sku_name             = "Consumption_0"
}

resource "azurerm_api_management_backend" "itp_backend" {
  name                = "itp-backend"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol             = "http"
  url                  = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
}

resource "azurerm_api_management_api" "backend" {
  name                = "itp-backend-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name         = "ITP Backend API"
  path                 = ""
  protocols            = ["https"]
  service_url          = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
  revision             = "1"

  # No APIM product/subscription concept in this design - auth is JWT-only.
  # Defaults to true, which would otherwise reject every request with
  # "missing subscription key" regardless of a valid bearer token.
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "health" {
  operation_id        = "get-health"
  api_name             = azurerm_api_management_api.backend.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name         = "Health check"
  method               = "GET"
  url_template         = "/health"
}

resource "azurerm_api_management_api_operation" "profile" {
  operation_id        = "get-profile"
  api_name             = azurerm_api_management_api.backend.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name         = "Get profile"
  method               = "GET"
  url_template         = "/api/profile"
}

# Named Values referenced by apim/validate-jwt-policy.xml - see that file's
# header comment for what each one means and why both v1/v2 forms are used.
resource "azurerm_api_management_named_value" "tenant_id" {
  name                = "tenant-id"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name         = "tenant-id"
  value                = var.azure_tenant_id
}

resource "azurerm_api_management_named_value" "api_audience" {
  name                = "api-audience"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name         = "api-audience"
  value                = "api://${var.azure_api_client_id}"
}

resource "azurerm_api_management_named_value" "api_client_id" {
  name                = "api-client-id"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name         = "api-client-id"
  value                = var.azure_api_client_id
}

resource "azurerm_api_management_named_value" "backend_id" {
  name                = "backend-id"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name         = "backend-id"
  value                = azurerm_api_management_backend.itp_backend.name
}

# Applies to EVERY operation, including the public /health one - CORS and
# backend routing only, no auth.
resource "azurerm_api_management_api_policy" "backend" {
  api_name             = azurerm_api_management_api.backend.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  xml_content          = file("${path.module}/../../apim/api-base-policy.xml")

  depends_on = [
    azurerm_api_management_named_value.backend_id,
  ]
}

# Only /api/profile requires a validated token - attached at the operation
# level (not the API level) so /health stays public.
resource "azurerm_api_management_api_operation_policy" "profile_auth" {
  operation_id        = azurerm_api_management_api_operation.profile.operation_id
  api_name             = azurerm_api_management_api.backend.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  xml_content          = file("${path.module}/../../apim/validate-jwt-policy.xml")

  depends_on = [
    azurerm_api_management_api_policy.backend,
    azurerm_api_management_named_value.tenant_id,
    azurerm_api_management_named_value.api_audience,
    azurerm_api_management_named_value.api_client_id,
    azurerm_api_management_named_value.backend_id,
  ]
}
