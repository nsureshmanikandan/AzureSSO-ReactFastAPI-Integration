resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_container_registry" "main" {
  name                = "${var.container_registry_name_prefix}${random_string.acr_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location
  sku                  = "Basic"
  admin_enabled        = true
}

resource "azurerm_container_app_environment" "main" {
  name                = "cae-itp-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location
}

# Starts on a public placeholder image - the pipeline updates the revision
# with the real backend image on every deploy after this first apply.
resource "azurerm_container_app" "backend" {
  name                          = "ca-itp-backend-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name           = azurerm_resource_group.main.name
  revision_mode                 = "Single"

  template {
    container {
      name   = "backend"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_TENANT_ID"
        value = var.azure_tenant_id
      }
      env {
        name  = "AZURE_API_CLIENT_ID"
        value = var.azure_api_client_id
      }
      env {
        name  = "TRUST_APIM_HEADERS"
        value = "True"
      }
      env {
        name  = "ALLOWED_ORIGINS"
        value = jsonencode(var.allowed_origins)
      }
    }
  }

  ingress {
    external_enabled = true
    target_port       = 8000
    traffic_weight {
      latest_revision = true
      percentage       = 100
    }
  }

  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  # The CI/CD pipeline (az containerapp update) owns the deployed image
  # after the first apply - without this, any unrelated `terraform apply`
  # here reverts the Container App back to this placeholder, undoing
  # whatever the pipeline last deployed. Confirmed live 2026-08-22: the
  # APIM apply below did exactly this.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

resource "azurerm_static_web_app" "frontend" {
  name                = var.static_web_app_name
  resource_group_name = azurerm_resource_group.main.name
  location             = var.static_web_app_location
  sku_tier             = "Free"
  sku_size             = "Free"
}
