variable "resource_group_name" { type = string }
variable "location"            { type = string }

variable "automation_account_name" {
  type    = string
  default = "aa-fslogix-avdlab"
}

variable "hybrid_worker_group_name" {
  type    = string
  default = "hwg-fslogix"
}

variable "session_host_vm_id"   { type = string }
variable "session_host_vm_name" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
