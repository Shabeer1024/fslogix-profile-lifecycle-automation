# ============================================================
# FSLogix Profile Migration — Target Storage Infrastructure
# Provisions: Storage Account + File Share in target region
# ============================================================

# ── Resource Group ──────────────────────────────────────────
resource "azurerm_resource_group" "target" {
  name     = var.target_resource_group
  location = var.target_location

  tags = {
    environment = var.environment
    project     = "fslogix-migration"
    managed-by  = "terraform"
  }
}

# ── Target Storage Account ───────────────────────────────────
resource "azurerm_storage_account" "target" {
  name                     = var.target_storage_account_name
  resource_group_name      = azurerm_resource_group.target.name
  location                 = azurerm_resource_group.target.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "FileStorage"

  # Security
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true
  allow_nested_items_to_be_public = false

  # Large file share support for FSLogix VHDs
  large_file_share_enabled = true

  tags = {
    environment = var.environment
    project     = "fslogix-migration"
    role        = "fslogix-profiles"
  }
}

# ── FSLogix Profile File Share ───────────────────────────────
resource "azurerm_storage_share" "fslogix_profiles" {
  name               = var.file_share_name
  storage_account_id = azurerm_storage_account.target.id
  quota              = var.file_share_quota_gb

  metadata = {
    purpose = "fslogix-user-profiles"
    migrated-from = var.source_storage_account_name
  }
}

# ── Private Endpoint (optional — recommended for production) ─
resource "azurerm_private_endpoint" "storage" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "${var.target_storage_account_name}-pe"
  location            = azurerm_resource_group.target.location
  resource_group_name = azurerm_resource_group.target.name
  subnet_id           = var.target_subnet_id

  private_service_connection {
    name                           = "${var.target_storage_account_name}-psc"
    private_connection_resource_id = azurerm_storage_account.target.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  tags = {
    environment = var.environment
    project     = "fslogix-migration"
  }
}

# ── RBAC — Session Hosts access to target storage ────────────
resource "azurerm_role_assignment" "session_host_smb" {
  count                = length(var.session_host_principal_ids)
  scope                = azurerm_storage_account.target.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.session_host_principal_ids[count.index]
}

# ── Storage Account Network Rules ────────────────────────────
resource "azurerm_storage_account_network_rules" "target" {
  storage_account_id = azurerm_storage_account.target.id
  default_action     = var.enable_private_endpoint ? "Deny" : "Allow"
  bypass             = ["AzureServices"]

  ip_rules = var.allowed_ip_ranges
}
