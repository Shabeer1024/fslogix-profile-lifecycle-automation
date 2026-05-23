output "host_pool_id" {
  value = azurerm_virtual_desktop_host_pool.this.id
}

output "host_pool_name" {
  value = azurerm_virtual_desktop_host_pool.this.name
}

output "workspace_id" {
  value = azurerm_virtual_desktop_workspace.this.id
}

output "workspace_name" {
  value = azurerm_virtual_desktop_workspace.this.name
}

output "app_group_id" {
  value = azurerm_virtual_desktop_application_group.desktop.id
}

output "app_group_name" {
  value = azurerm_virtual_desktop_application_group.desktop.name
}

output "registration_token" {
  description = "Registration token for session hosts to join (sensitive, expires in 48h)"
  value       = azurerm_virtual_desktop_host_pool_registration_info.this.token
  sensitive   = true
}
