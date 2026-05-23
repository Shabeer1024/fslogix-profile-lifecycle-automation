variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the DC NIC will be attached"
  type        = string
}

variable "virtual_network_id" {
  description = "Full resource ID of the VNet (for DNS server update)"
  type        = string
}

variable "vm_name" {
  description = "Name of the DC VM and computer name"
  type        = string
  default     = "dc01"

  validation {
    condition     = length(var.vm_name) <= 15
    error_message = "Windows computer name must be 15 characters or less."
  }
}

variable "vm_size" {
  description = "Azure VM SKU"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Local administrator username"
  type        = string
  default     = "labadmin"
}

variable "admin_password" {
  description = "Local administrator password"
  type        = string
  sensitive   = true
}

variable "private_ip_address" {
  description = "Static private IP for the DC"
  type        = string
  default     = "10.0.1.4"
}

variable "domain_name" {
  description = "AD DS domain name"
  type        = string
  default     = "lab.local"
}

variable "safe_mode_password" {
  description = "DSRM password"
  type        = string
  sensitive   = true
}

variable "auto_shutdown_time" {
  description = "Daily auto-shutdown time HHMM"
  type        = string
  default     = "2300"
}

variable "auto_shutdown_timezone" {
  description = "Windows timezone ID"
  type        = string
  default     = "India Standard Time"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
