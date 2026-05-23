variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "storage_account_name" {
  description = "Globally unique, lowercase, 3-24 chars, alphanumeric"
  type        = string
}
variable "share_name" {
  type    = string
  default = "profiles"
}
variable "share_quota_gb" {
  type    = number
  default = 100
}
variable "fslogix_initial_size_mb" {
  type    = number
  default = 10240
}
variable "session_host_vm_id"   { type = string }
variable "session_host_vm_name" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}