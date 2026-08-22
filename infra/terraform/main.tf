locals {
  graph_app_id = "00000003-0000-0000-c000-000000000000"

  graph_scopes = {
    openid         = "37f7f235-527c-4136-accd-4a02d197296e"
    profile        = "14dad69e-099b-42c9-810b-d002981feec1"
    email          = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"
    offline_access = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"
    "User.Read"    = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
  }

  # Mirrors the real corp app's App roles blade (Tax Admin, IG Member,
  # Tax Member, Technical User, DevOps Team, Business Requestor, IG Admin,
  # GenerateToken) so the "roles" claim this backend reads (app/auth.py) is
  # populated the same way here as in the real ITP app.
  app_roles = {
    generate_token     = { display_name = "GenerateToken", description = "Gives applications the ability to generate tokens.", value = "GenerateToken", allowed_member_types = ["Application"] }
    tax_admin          = { display_name = "Tax Admin", description = "Tax department admin", value = "TaxAdmin", allowed_member_types = ["User"] }
    ig_admin           = { display_name = "IG Admin", description = "Information Governance admin", value = "IGAdmin", allowed_member_types = ["User"] }
    tax_member         = { display_name = "Tax Member", description = "Tax SME", value = "Tax.SME", allowed_member_types = ["User"] }
    ig_member          = { display_name = "IG Member", description = "IG SME", value = "IG.SME", allowed_member_types = ["User"] }
    business_requestor = { display_name = "Business Requestor", description = "Raises and submits business requests", value = "Requestor", allowed_member_types = ["User"] }
    technical_user     = { display_name = "Technical User", description = "Full app access regardless of other roles", value = "TechnicalUser", allowed_member_types = ["User"] }
    devops_team        = { display_name = "DevOps Team", description = "Same screens as Technical User; no admin actions", value = "DevOpsTeam", allowed_member_types = ["User"] }
  }
}

# Stable IDs, independent of app recreation.
resource "random_uuid" "access_as_user" {}
resource "random_uuid" "app_role" {
  for_each = local.app_roles
}

# --- Single combined SPA + API app registration -------------------------
# Matches the real corp architecture: one app registration plays both the
# SPA role (single_page_application block) and the API resource-server role
# (api block + its own required_resource_access to itself), instead of two
# separate registrations.
#
# KNOWN PROVIDER FOOTGUN - confirmed live 2026-08-21: any update to THIS
# resource (even something as unrelated as display_name or redirect_uris)
# causes the azuread provider to silently reset identifierUris and
# requiredResourceAccess back to empty on the real app, even though this
# resource never references either attribute. Terraform's own state for
# azuread_application_identifier_uri.app / azuread_application_api_access.*
# does NOT notice - it still shows them as present until the next `plan`
# does a live refresh and discovers the drift.
# Rule: after ANY apply that touches azuread_application.app, immediately
# run `terraform plan` again. If it shows the identifier_uri/api_access
# resources need re-creating, `terraform apply` again right away before
# treating the change as done. Do not skip this - a pipeline that only
# applies once per run will silently ship an app with no exposed API/
# permissions.
resource "azuread_application" "app" {
  display_name     = "corpapps-${var.environment}-itp-backend-apim-spn"
  sign_in_audience = "AzureADMyOrg"

  single_page_application {
    redirect_uris = var.redirect_uris
  }

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                          = random_uuid.access_as_user.result
      admin_consent_description   = "Allow the app to call its own API on behalf of the signed-in user."
      admin_consent_display_name  = "Access AzureSSO-Demo-App"
      enabled                     = true
      type                        = "User"
      user_consent_description    = "Allow the app to call its own API on your behalf."
      user_consent_display_name   = "Access AzureSSO-Demo-App"
      value                       = "access_as_user"
    }
  }

  dynamic "app_role" {
    for_each = local.app_roles
    content {
      id                    = random_uuid.app_role[app_role.key].result
      allowed_member_types  = app_role.value.allowed_member_types
      display_name          = app_role.value.display_name
      description           = app_role.value.description
      value                  = app_role.value.value
    }
  }

  # Access tokens for a custom API audience don't include "name" by default
  # the way ID tokens do - without this, APIM's X-User-Name extraction (and
  # anything else reading the "name" claim off the access token) gets
  # nothing back, regardless of Graph "profile" scope consent.
  optional_claims {
    access_token {
      name = "name"
    }
  }
}

# Application ID URI - api://<client_id> by default, or a custom domain URI
# (var.identifier_uri_override) matching how the real corp apps are set up.
# Separate resource since it needs the client_id that only exists after
# azuread_application.app is created.
resource "azuread_application_identifier_uri" "app" {
  application_id = azuread_application.app.id
  identifier_uri  = var.identifier_uri_override != "" ? var.identifier_uri_override : "api://${azuread_application.app.client_id}"
}

resource "azuread_service_principal" "app" {
  client_id = azuread_application.app.client_id
}

# The app requesting a token for itself (SPA -> its own exposed API scope).
# Split into its own resource because the client_id is only known after
# azuread_application.app is created - referencing it from inside that same
# resource's required_resource_access would be a self-reference cycle.
resource "azuread_application_api_access" "self" {
  application_id = azuread_application.app.id
  api_client_id   = azuread_application.app.client_id
  scope_ids       = [random_uuid.access_as_user.result]
}

resource "azuread_application_api_access" "graph" {
  application_id = azuread_application.app.id
  api_client_id   = local.graph_app_id
  scope_ids       = values(local.graph_scopes)
}

# --- AD groups, one per user-assignable role (not generate_token, which is
#     Application-only and has no group) -----------------------------------

locals {
  group_roles = { for k, v in local.app_roles : k => v if !contains(v.allowed_member_types, "Application") }
}

resource "azuread_group" "role_groups" {
  for_each = var.create_ad_groups ? var.ad_groups : {}

  display_name     = each.value
  security_enabled = true
  description      = "ITP demo role group - ${each.key}"
}

data "azuread_group" "role_groups" {
  for_each = var.create_ad_groups ? {} : var.ad_groups

  display_name = each.value
}

locals {
  role_group_object_ids = var.create_ad_groups ? {
    for k, v in azuread_group.role_groups : k => v.object_id
    } : {
    for k, v in data.azuread_group.role_groups : k => v.object_id
  }
}

resource "azuread_app_role_assignment" "role_groups" {
  for_each = local.group_roles

  app_role_id          = random_uuid.app_role[each.key].result
  principal_object_id  = local.role_group_object_ids[each.key]
  resource_object_id   = azuread_service_principal.app.object_id
}

# --- Admin consent (sandbox tenant - safe to automate) -------------------

data "azuread_service_principal" "graph" {
  client_id = local.graph_app_id
}

resource "azuread_service_principal_delegated_permission_grant" "graph_consent" {
  count = var.grant_admin_consent ? 1 : 0

  service_principal_object_id           = azuread_service_principal.app.id
  resource_service_principal_object_id  = data.azuread_service_principal.graph.object_id
  claim_values                           = keys(local.graph_scopes)
}

resource "azuread_service_principal_delegated_permission_grant" "self_consent" {
  count = var.grant_admin_consent ? 1 : 0

  service_principal_object_id           = azuread_service_principal.app.id
  resource_service_principal_object_id  = azuread_service_principal.app.id
  claim_values                           = ["access_as_user"]
}
