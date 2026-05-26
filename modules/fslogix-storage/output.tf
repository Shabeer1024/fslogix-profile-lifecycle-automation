output "storage_account_name" { value = azurerm_storage_account.this.name }
output "storage_account_id" { value = azurerm_storage_account.this.id }
output "share_name" { value = azurerm_storage_share.profiles.name }
output "share_unc" { value = "\\\\${azurerm_storage_account.this.name}.file.core.windows.net\\${azurerm_storage_share.profiles.name}" }
output "share_quota_gb" { value = azurerm_storage_share.profiles.quota }
output "archive_container_name" { value = azurerm_storage_container.archive.name }
output "primary_access_key" {
  value     = azurerm_storage_account.this.primary_access_key
  sensitive = true
}