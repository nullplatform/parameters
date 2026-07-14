output "client_id" {
  description = "Application (client) ID of the created service principal. Wire into the agent as AZURE_CLIENT_ID. Empty when service_principal.enable=false."
  value       = length(azuread_application.this) > 0 ? azuread_application.this[0].client_id : ""
}

output "object_id" {
  description = "Object ID of the created service principal (the RBAC role assignment principal). Empty when service_principal.enable=false."
  value       = length(azuread_service_principal.this) > 0 ? azuread_service_principal.this[0].object_id : ""
}

output "tenant_id" {
  description = "Tenant ID the service principal belongs to. Wire into the agent as AZURE_TENANT_ID."
  value       = data.azuread_client_config.current.tenant_id
}

output "client_secret" {
  description = "Client secret for the service principal. Wire into the agent as AZURE_CLIENT_SECRET. Empty when service_principal.enable=false."
  value       = length(azuread_application_password.this) > 0 ? azuread_application_password.this[0].value : ""
  sensitive   = true
}
