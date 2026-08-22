terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state on purpose - this is a personal/sandbox tenant for local dev,
  # not the shared ITP landscape. No remote backend needed.
}

provider "azuread" {
  tenant_id = var.tenant_id
}
