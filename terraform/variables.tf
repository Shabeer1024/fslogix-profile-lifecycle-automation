# ============================================================
# Variables — FSLogix Migration Target Storage
# ============================================================

# ── Source (existing) ────────────────────────────────────────
variable "source_resource_group" {
  type        = string
  description = "Source resource group name"
}

variable "source_storage_account_name" {
  type        = string
  description = "Source storage account name (where profiles currently live)"
}

variable "source_file_share_name" {
  type        = string
  description = "Source file share name"
  default     = "profiles"
}

# ── Target (new) ─────────────────────────────────────────────
variable "target_resource_group" {
  type        = string
  description = "Target resource group name"
}

variable "target_location" {
  type        = string
  description = "Target Azure region"
  default     = "eastus"
}

variable "target_storage_account_name" {
  type        = string
  description = "Target storage account name (must be globally unique)"
}

variable "file_share_name" {
  type        = string
  description = "FSLogix profile file share name"
  default     = "profiles"
}

variable "file_share_quota_gb" {
  type        = number
  description = "File share size in GB"
  default     = 1024
}

# ── Network ──────────────────────────────────────────────────
variable "enable_private_endpoint" {
  type        = bool
  description = "Enable private endpoint for storage"
  default     = false
}

variable "target_subnet_id" {
  type        = string
  description = "Subnet ID for private endpoint (required if enable_private_endpoint = true)"
  default     = ""
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "IP ranges allowed to access storage"
  default     = []
}

# ── RBAC ─────────────────────────────────────────────────────
variable "session_host_principal_ids" {
  type        = list(string)
  description = "Managed identity principal IDs of AVD session hosts"
  default     = []
}

# ── AVD ──────────────────────────────────────────────────────
variable "avd_resource_group" {
  type        = string
  description = "AVD host pool resource group"
}

variable "host_pool_name" {
  type        = string
  description = "AVD host pool name"
}

# ── General ──────────────────────────────────────────────────
variable "environment" {
  type        = string
  description = "Environment name"
  default     = "lab"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}
