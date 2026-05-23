variable "resource_group_name" {
  description = "Resource group to deploy networking into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnets. Key becomes snet-<key>."
  type = map(object({
    address_prefixes = list(string)
  }))
}

variable "nsg_name" {
  description = "Name of the shared NSG"
  type        = string
}

variable "admin_source_ip" {
  description = "Your public IP for RDP allow rule"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
