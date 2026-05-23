variable "resource_group_name" {
  description = "Resource group to deploy AVD into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "workspace_name" {
  description = "AVD workspace name"
  type        = string
  default     = "ws-avd-lab"
}

variable "workspace_friendly_name" {
  description = "AVD workspace display name"
  type        = string
  default     = "AVD Lab Workspace"
}

variable "host_pool_name" {
  description = "AVD host pool name"
  type        = string
  default     = "hp-avd-lab"
}

variable "host_pool_friendly_name" {
  description = "Host pool display name"
  type        = string
  default     = "AVD Lab Host Pool"
}

variable "host_pool_max_sessions" {
  description = "Max concurrent sessions per host"
  type        = number
  default     = 10
}

variable "app_group_name" {
  description = "AVD desktop application group name"
  type        = string
  default     = "ag-desktop-lab"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
