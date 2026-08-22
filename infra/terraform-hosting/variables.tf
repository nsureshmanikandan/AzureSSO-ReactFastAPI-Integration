variable "environment" {
  description = "Environment short name - used in resource names"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "static_web_app_location" {
  description = "Azure Static Web Apps is only available in a subset of regions - centralus, eastus2, westus2, westeurope, eastasia"
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  type    = string
  default = "rg-itp-demo-dev"
}

variable "container_registry_name_prefix" {
  description = "ACR name must be globally unique alphanumeric-only - a random suffix is appended to this prefix automatically"
  type        = string
  default     = "acritpdemo"
}

variable "static_web_app_name" {
  type    = string
  default = "swa-itp-demo-dev"
}

# --- Wired straight from infra/terraform's outputs (the SSO app registration) ---

variable "azure_tenant_id" {
  type = string
}

variable "azure_api_client_id" {
  type = string
}

variable "allowed_origins" {
  description = "CORS origins the backend should accept - add the Static Web App's hostname after first apply"
  type        = list(string)
  default     = ["http://localhost:5173"]
}
