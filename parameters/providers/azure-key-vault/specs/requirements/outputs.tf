output "client_id" {
  description = "Client ID of the user-assigned managed identity. Annotate the agent's Kubernetes ServiceAccount with azure.workload.identity/client-id. Empty when workload_identity.enable=false."
  value       = length(azurerm_user_assigned_identity.this) > 0 ? azurerm_user_assigned_identity.this[0].client_id : ""
}

output "principal_id" {
  description = "Principal (object) ID of the managed identity — the RBAC role assignment principal. Empty when workload_identity.enable=false."
  value       = length(azurerm_user_assigned_identity.this) > 0 ? azurerm_user_assigned_identity.this[0].principal_id : ""
}

output "tenant_id" {
  description = "Tenant ID the managed identity belongs to. Wire into the agent as AZURE_TENANT_ID."
  value       = data.azurerm_client_config.current.tenant_id
}
