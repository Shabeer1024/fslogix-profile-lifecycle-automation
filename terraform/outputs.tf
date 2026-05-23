# ============================================================
# Outputs — passed to GitHub Actions pipeline
# ============================================================

output "target_storage_account_name" {
  value       = azurerm_storage_account.target.name
  description = "Target storage account name"
}

output "target_storage_account_id" {
  value       = azurerm_storage_account.target.id
  description = "Target storage account resource ID"
}

output "target_file_share_name" {
  value       = azurerm_storage_share.fslogix_profiles.name
  description = "Target file share name"
}

output "target_file_share_url" {
  value       = "\\\\${azurerm_storage_account.target.name}.file.core.windows.net\\${azurerm_storage_share.fslogix_profiles.name}"
  description = "UNC path for FSLogix registry configuration"
}

output "target_storage_primary_endpoint" {
  value       = azurerm_storage_account.target.primary_file_endpoint
  description = "Primary file endpoint for AzCopy"
}

output "target_resource_group" {
  value       = azurerm_resource_group.target.name
  description = "Target resource group name"
}
