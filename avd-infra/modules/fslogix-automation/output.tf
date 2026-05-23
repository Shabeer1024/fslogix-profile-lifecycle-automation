output "automation_account_name" {
  value = azurerm_automation_account.this.name
}

output "automation_account_id" {
  value = azurerm_automation_account.this.id
}

output "automation_account_identity_principal_id" {
  value = azurerm_automation_account.this.identity[0].principal_id
}

output "hybrid_worker_group_name" {
  value = azurerm_automation_hybrid_runbook_worker_group.this.name
}

output "hybrid_service_url" {
  value = azurerm_automation_account.this.hybrid_service_url
}

output "runbook_name" {
  value = azurerm_automation_runbook.fslogix_autogrow.name
}

output "webhook_uri" {
  description = "Webhook URL used by Phase 4 Logic App to trigger the runbook"
  value       = azurerm_automation_webhook.fslogix_autogrow_trigger.uri
  sensitive   = true
}

output "logic_app_name" {
  value = azurerm_logic_app_workflow.fslogix_scheduler.name
}

output "logic_app_id" {
  value = azurerm_logic_app_workflow.fslogix_scheduler.id
}
