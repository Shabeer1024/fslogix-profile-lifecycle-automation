variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "automation_account_name" {
  type    = string
  default = "aa-fslogix-avdlab"
}

variable "hybrid_worker_group_name" {
  type    = string
  default = "hwg-fslogix"
}

variable "session_host_vm_id" { type = string }
variable "session_host_vm_name" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

# =============================================================================
# Storage wiring — passed from fslogix-storage module outputs
# =============================================================================
variable "storage_account_name" { type = string }

variable "storage_account_key" {
  type      = string
  sensitive = true
}

variable "share_name" {
  type    = string
  default = "profiles"
}

variable "archive_container_name" {
  type    = string
  default = "archive-profiles"
}

# =============================================================================
# Lifecycle automation config
# =============================================================================
variable "teams_webhook_url" {
  description = "Teams Incoming Webhook URL for runbook notifications. Leave empty to disable."
  type        = string
  default     = ""
  sensitive   = true
}

variable "orphan_archive_days" {
  description = "Days after last activity before an orphaned profile is archived to blob (Cool tier)"
  type        = number
  default     = 90
}

variable "orphan_delete_days" {
  description = "Days after last activity before an orphaned profile is permanently deleted"
  type        = number
  default     = 180
}

variable "stale_handle_hours" {
  description = "Hours an SMB handle must be held before it is eligible for forced closure"
  type        = number
  default     = 2
}
