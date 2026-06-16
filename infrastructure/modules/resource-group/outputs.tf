# MODULE OUTPUTS
output "id" {
  value       = azurerm_resource_group.this.id
  description = "Resource group ID."
}

output "resource_group_name" {
  value       = azurerm_resource_group.this.name
  description = "Resource group name (consumed by all other units)."
}

output "location" {
  value       = azurerm_resource_group.this.location
  description = "Resource group location."
}
