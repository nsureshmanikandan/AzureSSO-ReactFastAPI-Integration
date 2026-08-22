output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "container_app_name" {
  value = azurerm_container_app.backend.name
}

output "container_app_fqdn" {
  value = azurerm_container_app.backend.ingress[0].fqdn
}

output "static_web_app_name" {
  value = azurerm_static_web_app.frontend.name
}

output "static_web_app_default_hostname" {
  value = azurerm_static_web_app.frontend.default_host_name
}

output "static_web_app_api_key" {
  value     = azurerm_static_web_app.frontend.api_key
  sensitive = true
}
