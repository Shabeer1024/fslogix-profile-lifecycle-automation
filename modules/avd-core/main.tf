# =============================================================================
# AVD Core: Workspace + Host Pool + App Group + Registration Token
# =============================================================================

resource "azurerm_virtual_desktop_host_pool" "this" {
  name                     = var.host_pool_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  friendly_name            = var.host_pool_friendly_name
  description              = "Lab host pool for AVD testing"
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = var.host_pool_max_sessions
  preferred_app_group_type = "Desktop"
  validate_environment     = false
  start_vm_on_connect      = false
  tags                     = var.tags

  custom_rdp_properties = "audiocapturemode:i:1;audiomode:i:0;drivestoredirect:s:;redirectclipboard:i:1;redirectcomports:i:1;redirectprinters:i:1;redirectsmartcards:i:1;screen mode id:i:2;"
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.this.id
  expiration_date = timeadd(timestamp(), "48h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_virtual_desktop_workspace" "this" {
  name                = var.workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = var.workspace_friendly_name
  description         = "Lab workspace for AVD testing"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                = var.app_group_name
  location            = var.location
  resource_group_name = var.resource_group_name
  host_pool_id        = azurerm_virtual_desktop_host_pool.this.id
  type                = "Desktop"
  friendly_name       = "Lab Desktop"
  description         = "Full desktop access for the lab"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "this" {
  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}
