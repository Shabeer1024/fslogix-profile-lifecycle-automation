# =============================================================================
# Automation Account + Hybrid Worker on Session Host
# =============================================================================

resource "azurerm_automation_account" "this" {
  name                = var.automation_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_automation_hybrid_runbook_worker_group" "this" {
  name                    = var.hybrid_worker_group_name
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
}

resource "random_uuid" "worker_id" {}

resource "azurerm_automation_hybrid_runbook_worker" "sh01" {
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  worker_group_name       = azurerm_automation_hybrid_runbook_worker_group.this.name
  vm_resource_id          = var.session_host_vm_id
  worker_id               = random_uuid.worker_id.result
}

# -----------------------------------------------------------------------------
# Install Hyper-V PowerShell module (provides Resize-VHD) on session host
# Using Run Command (not VM extension) to avoid the
# "one CustomScriptExtension per Windows VM" limit.
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_run_command" "install_hyperv" {
  name               = "install-hyperv-module"
  virtual_machine_id = var.session_host_vm_id
  location           = var.location

  source {
    script = <<-EOT
      $ErrorActionPreference = "Stop"
      try {
          Write-Host "Enabling Hyper-V Management PowerShell module"
          Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All -NoRestart
          Write-Host "Scheduling delayed reboot in 60 seconds to activate module"
          shutdown /r /t 60 /c "Hyper-V module activation reboot"
          exit 0
      } catch {
          Write-Error $_
          exit 1
      }
    EOT
  }

  # Run commands are one-shot setup operations. After the VM shuts down, Azure
  # times out on the instanceView GET during terraform plan. ignore_changes = all
  # tells Terraform to never re-read or re-run this resource after initial creation.
  lifecycle {
    ignore_changes = all
  }
}

# -----------------------------------------------------------------------------
# Install HybridWorkerForWindows extension on session host
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "hybrid_worker" {
  name                       = "HybridWorkerExtension"
  virtual_machine_id         = var.session_host_vm_id
  publisher                  = "Microsoft.Azure.Automation.HybridWorker"
  type                       = "HybridWorkerForWindows"
  type_handler_version       = "1.1"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    AutomationAccountURL = azurerm_automation_account.this.hybrid_service_url
  })

  depends_on = [
    azurerm_automation_hybrid_runbook_worker.sh01,
    azurerm_virtual_machine_run_command.install_hyperv
  ]

  timeouts {
    create = "30m"
  }
}
# =============================================================================
# Install Az.Storage + Az.Accounts on the Hybrid Worker
# Uses Run Command to avoid the one-CSE-per-VM limit
# =============================================================================
resource "azurerm_virtual_machine_run_command" "install_az_storage" {
  name               = "install-az-storage-module"
  virtual_machine_id = var.session_host_vm_id
  location           = var.location

  source {
    script = <<-EOT
      $ErrorActionPreference = "Stop"
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
      foreach ($mod in @("Az.Accounts", "Az.Storage")) {
          if (-not (Get-Module $mod -ListAvailable -ErrorAction SilentlyContinue)) {
              Install-Module -Name $mod -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
              Write-Host "$mod installed"
          } else {
              Write-Host "$mod already present"
          }
      }
    EOT
  }

  depends_on = [
    azurerm_virtual_machine_extension.hybrid_worker,
    azurerm_virtual_machine_run_command.install_hyperv
  ]

  lifecycle {
    ignore_changes = all
  }
}

# =============================================================================
# Automation Variables — shared config read by all lifecycle runbooks
# =============================================================================
resource "azurerm_automation_variable_string" "storage_account" {
  name                    = "FslogixStorageAccount"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  value                   = var.storage_account_name
}

resource "azurerm_automation_variable_string" "storage_key" {
  name                    = "FslogixStorageKey"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  value                   = var.storage_account_key
  encrypted               = true

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_automation_variable_string" "share_name" {
  name                    = "FslogixShareName"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  value                   = var.share_name
}

resource "azurerm_automation_variable_string" "archive_container" {
  name                    = "FslogixArchiveContainer"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  value                   = var.archive_container_name
}

resource "azurerm_automation_variable_string" "teams_webhook" {
  # Only created when a URL is actually provided — AzureRM rejects empty string values
  count                   = var.teams_webhook_url != "" ? 1 : 0
  name                    = "FslogixTeamsWebhook"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  value                   = var.teams_webhook_url
  encrypted               = true

  lifecycle {
    ignore_changes = [value]
  }
}

# =============================================================================
# FSLogix Auto-Grow Runbook + Webhook
# =============================================================================
resource "azurerm_automation_runbook" "fslogix_autogrow" {
  name                    = "FSLogix-AutoGrow"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  description             = "Auto-grows FSLogix profile VHDXes when usage exceeds 80%"
  runbook_type            = "PowerShell"

  content = file("${path.module}/scripts/fslogix-autogrow.ps1")
}

resource "azurerm_automation_webhook" "fslogix_autogrow_trigger" {
  name                    = "FSLogix-AutoGrow-Trigger"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  expiry_time             = timeadd(timestamp(), "8760h")
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.fslogix_autogrow.name

  run_on_worker_group     = azurerm_automation_hybrid_runbook_worker_group.this.name

  lifecycle {
    ignore_changes = [expiry_time]
  }
}

# =============================================================================
# Logic App Scheduler
# =============================================================================
resource "azurerm_logic_app_workflow" "fslogix_scheduler" {
  name                = "lapp-fslogix-autogrow"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_logic_app_trigger_recurrence" "hourly" {
  name         = "hourly-trigger"
  logic_app_id = azurerm_logic_app_workflow.fslogix_scheduler.id
  frequency    = "Hour"
  interval     = 1
}

resource "azurerm_logic_app_action_http" "call_runbook_webhook" {
  name         = "Call-Runbook-Webhook"
  logic_app_id = azurerm_logic_app_workflow.fslogix_scheduler.id
  method       = "POST"
  uri          = azurerm_automation_webhook.fslogix_autogrow_trigger.uri

  depends_on = [azurerm_logic_app_trigger_recurrence.hourly]
}

# =============================================================================
# Orphaned Profile Cleanup Runbook — fires weekly
# =============================================================================
resource "azurerm_automation_runbook" "orphan_cleanup" {
  name                    = "FSLogix-OrphanedProfileCleanup"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  description             = "Archives/deletes FSLogix profiles for deleted AD users. Archive at ${var.orphan_archive_days}d, delete at ${var.orphan_delete_days}d."
  runbook_type            = "PowerShell"

  content = file("${path.module}/scripts/fslogix-orphan-cleanup.ps1")

  depends_on = [azurerm_virtual_machine_run_command.install_az_storage]
}

resource "azurerm_automation_webhook" "orphan_cleanup_trigger" {
  name                    = "FSLogix-OrphanCleanup-Trigger"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  expiry_time             = timeadd(timestamp(), "8760h")
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.orphan_cleanup.name
  run_on_worker_group     = azurerm_automation_hybrid_runbook_worker_group.this.name

  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_logic_app_workflow" "orphan_scheduler" {
  name                = "lapp-fslogix-orphan-cleanup"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_logic_app_trigger_recurrence" "weekly" {
  name         = "weekly-trigger"
  logic_app_id = azurerm_logic_app_workflow.orphan_scheduler.id
  frequency    = "Week"
  interval     = 1
}

resource "azurerm_logic_app_action_http" "call_orphan_webhook" {
  name         = "Call-OrphanCleanup-Webhook"
  logic_app_id = azurerm_logic_app_workflow.orphan_scheduler.id
  method       = "POST"
  uri          = azurerm_automation_webhook.orphan_cleanup_trigger.uri

  depends_on = [azurerm_logic_app_trigger_recurrence.weekly]
}

# =============================================================================
# Stale Handle Cleanup Runbook — fires every 15 minutes
# =============================================================================
resource "azurerm_automation_runbook" "stale_handle" {
  name                    = "FSLogix-StaleHandleCleanup"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  description             = "Closes SMB handles on the FSLogix share held longer than ${var.stale_handle_hours}h with no active session."
  runbook_type            = "PowerShell"

  content = file("${path.module}/scripts/fslogix-stale-handle.ps1")

  depends_on = [azurerm_virtual_machine_run_command.install_az_storage]
}

resource "azurerm_automation_webhook" "stale_handle_trigger" {
  name                    = "FSLogix-StaleHandle-Trigger"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  expiry_time             = timeadd(timestamp(), "8760h")
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.stale_handle.name
  run_on_worker_group     = azurerm_automation_hybrid_runbook_worker_group.this.name

  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_logic_app_workflow" "stale_handle_scheduler" {
  name                = "lapp-fslogix-stale-handle"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_logic_app_trigger_recurrence" "every_15min" {
  name         = "every-15min-trigger"
  logic_app_id = azurerm_logic_app_workflow.stale_handle_scheduler.id
  frequency    = "Minute"
  interval     = 15
}

resource "azurerm_logic_app_action_http" "call_stale_handle_webhook" {
  name         = "Call-StaleHandle-Webhook"
  logic_app_id = azurerm_logic_app_workflow.stale_handle_scheduler.id
  method       = "POST"
  uri          = azurerm_automation_webhook.stale_handle_trigger.uri

  depends_on = [azurerm_logic_app_trigger_recurrence.every_15min]
}
