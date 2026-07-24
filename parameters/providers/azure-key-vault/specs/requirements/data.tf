################################################################################
# Optional: user-assigned managed identity federated to the agent's Kubernetes
# ServiceAccount (AKS Workload Identity), granted Key Vault access via Azure
# RBAC. Toggle with var.workload_identity.enable. Secret-less: Azure injects and
# rotates short-lived tokens in the agent pod. Outputs the client_id / tenant_id
# so operators can annotate the ServiceAccount and wire AZURE_TENANT_ID.
################################################################################

# Tenant tofu authenticates against (the managed identity lives in this tenant).
data "azurerm_client_config" "current" {}
