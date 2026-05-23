# ============================================================
# terraform.tfvars — Fill in your values
# ============================================================

# Source (existing AVD storage)
source_resource_group       = "AVD-image-Lab"
source_storage_account_name = "avdlabscripts001"
source_file_share_name      = "profiles"

# Target (new region storage)
target_resource_group       = "AVD-Target-Lab"
target_location             = "eastus"
target_storage_account_name = "avdtargetprofiles001"
file_share_name             = "profiles"
file_share_quota_gb         = 1024

# Network
enable_private_endpoint     = false
allowed_ip_ranges           = []

# AVD
avd_resource_group          = "AVD-image-Lab"
host_pool_name              = "avd-lab-hostpool"
session_host_principal_ids  = []

# General
environment                 = "lab"
subscription_id             = "your-subscription-id"
