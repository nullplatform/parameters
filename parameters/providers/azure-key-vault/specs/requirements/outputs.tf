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

output "federated_credential_id" {
  description = "Resource ID of the federated identity credential. Pass to the nullplatform agent module's azure_federated_credential_id so the agent Helm release waits until the credential exists. Empty when workload_identity.enable=false."
  value       = length(azurerm_federated_identity_credential.this) > 0 ? azurerm_federated_identity_credential.this[0].id : ""
}
