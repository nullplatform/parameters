################################################################################
# Optional: Azure AD application + service principal for this provider, granted
# Key Vault access via Azure RBAC. Toggle with var.service_principal.enable.
# Outputs the client_id / tenant_id / client_secret so operators can wire them
# into the agent environment (AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_CLIENT_SECRET).
################################################################################

# Tenant the service principal is created in (the tenant tofu authenticates against).
data "azuread_client_config" "current" {}
