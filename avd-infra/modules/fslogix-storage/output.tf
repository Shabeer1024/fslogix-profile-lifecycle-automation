output "storage_account_name" { value = azurerm_storage_account.this.name }
output "storage_account_id"   { value = azurerm_storage_account.this.id }
output "share_name"           { value = azurerm_storage_share.profiles.name }
output "share_unc"            { value = "\\\\${azurerm_storage_account.this.name}.file.core.windows.net\\${azurerm_storage_share.profiles.name}" }
output "share_quota_gb"       { value = azurerm_storage_share.profiles.quota }