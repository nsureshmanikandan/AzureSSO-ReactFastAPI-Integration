output "backend_env" {
  description = "Paste these two lines into backend/.env"
  value       = <<-EOT
    AZURE_TENANT_ID=${var.tenant_id}
    AZURE_API_CLIENT_ID=${azuread_application.app.client_id}
  EOT
}

output "frontend_env" {
  description = "Paste these four lines into frontend/.env.local"
  value       = <<-EOT
    VITE_AZURE_CLIENT_ID=${azuread_application.app.client_id}
    VITE_AZURE_TENANT_ID=${var.tenant_id}
    VITE_REDIRECT_URI=${var.redirect_uris[0]}
    VITE_API_SCOPE=${azuread_application_identifier_uri.app.identifier_uri}/access_as_user
  EOT
}

output "app_role_values" {
  description = "The 'roles' claim value each app role maps to - use these in require_role(\"...\") calls in backend routes"
  value       = { for k, v in local.app_roles : k => v.value }
}

output "role_group_object_ids" {
  description = "Object ID of each demo AD group - add your own test user as a member to pick up that role's claim"
  value       = local.role_group_object_ids
}
