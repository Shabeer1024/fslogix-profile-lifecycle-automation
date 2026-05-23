# AVD FSLogix Lifecycle Automation

End-to-end automation for FSLogix profile management on Azure Virtual Desktop — infrastructure provisioning, autogrow, profile migration, and orphan cleanup in one repository.

---

## What's Inside

| Folder | Purpose |
|---|---|
| `avd-infra/` | Terraform — full AVD + FSLogix lab (VNet, DC, session hosts, storage, autogrow runbook) |
| `terraform/` | Terraform — target storage account provisioned during migration |
| `scripts/` | PowerShell — migration, verification, and orphan cleanup |
| `.github/workflows/` | GitHub Actions — automated pipelines |

---

## Automation Workflows

### 1. FSLogix Profile Migration (`fslogix-migration.yml`)
Triggered manually via `workflow_dispatch`.

| Job | What it does |
|---|---|
| Terraform Provision | Creates target Azure File Share storage |
| AzCopy Migration | Copies all VHDX profiles from source → target |
| Verify Migration | File count, size, and VHD presence checks |
| Update FSLogix Path | Pushes new UNC path to all AVD session hosts via Run Command |

### 2. Orphan Profile Cleanup (`orphan-profile-cleanup.yml`)
Runs automatically every **Sunday at 02:00 UTC** or manually.

| Logic | Action |
|---|---|
| Folder matches `username_S-1-5-21-*` | Extract SID, cross-reference against Entra ID |
| SID not in Entra ID + profile > 90 days old | Archive to cool-tier storage via AzCopy |
| SID not in Entra ID + profile > 180 days old | Delete with full audit log |
| Entra ID lookup fails | Skip — no false deletions |
| Summary | Teams notification + CSV audit artifact (retained 365 days) |

---

## AVD Infrastructure (`avd-infra/`)

Terraform modules:

| Module | Resources |
|---|---|
| `resourcegroup` | Azure Resource Group |
| `vnet` | Virtual Network + Subnets |
| `dc` | Domain Controller VM (AD DS) |
| `session-host` | AVD Session Host VMs |
| `avd-core` | Host Pool, App Group, Workspace |
| `fslogix-storage` | Storage Account + Azure File Share for profiles |
| `fslogix-automation` | Azure Automation Account + weekly autogrow runbook |

---

## Required GitHub Secrets

### Existing (Azure credentials)
| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal app ID |
| `AZURE_CLIENT_SECRET` | Service principal secret |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_CREDENTIALS` | Full JSON creds for `azure/login@v1` |

### Migration workflow
| Secret | Description |
|---|---|
| `SOURCE_STORAGE_ACCOUNT` | Source storage account name |
| `SOURCE_STORAGE_KEY` | Source storage account key |
| `SOURCE_SHARE_NAME` | Source file share name |
| `TARGET_STORAGE_KEY` | Key for Terraform-provisioned target storage |
| `AVD_RESOURCE_GROUP` | Resource group containing the host pool |
| `AVD_HOST_POOL_NAME` | Name of the AVD host pool |
| `TF_STATE_RG` | Resource group for Terraform remote state |
| `TF_STATE_SA` | Storage account for Terraform remote state |

### Orphan cleanup workflow (additional)
| Secret | Description |
|---|---|
| `ARCHIVE_STORAGE_ACCOUNT` | Cool-tier storage account for archived profiles |
| `ARCHIVE_STORAGE_KEY` | Key for archive storage account |
| `ARCHIVE_SHARE_NAME` | Archive file share name (e.g. `fslogix-archive`) |
| `TEAMS_WEBHOOK_URL` | Teams incoming webhook URL for notifications |

### Service principal permission (orphan cleanup)
Add **Microsoft Graph → `User.Read.All`** to the service principal so the SID → Entra ID lookup works.

> For on-premises AD only (no Azure AD sync), replace the Graph API call in `scripts/orphan-profile-cleanup.ps1` with `Get-ADObject` and use a self-hosted domain-joined runner.

---

## Quick Start

### Deploy AVD Infrastructure
```bash
cd avd-infra
terraform init
terraform plan -out=main.tfplan
terraform apply main.tfplan
```

### Run Profile Migration
Go to **Actions → FSLogix Profile Migration → Run workflow**
- Set `dry_run: true` first to preview, then `false` to execute.

### Run Orphan Cleanup Manually
Go to **Actions → FSLogix Orphan Profile Cleanup → Run workflow**
- Always start with `dry_run: true` to review what would be cleaned.
