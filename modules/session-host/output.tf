output "vm_id" {
  value = azurerm_windows_virtual_machine.sh.id
}

output "vm_name" {
  value = azurerm_windows_virtual_machine.sh.name
}

output "private_ip_address" {
  value = azurerm_network_interface.sh.private_ip_address
}
