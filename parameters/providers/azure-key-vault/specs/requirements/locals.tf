locals {
  # Vault created by this module (if any), folded into the identity's RBAC scope.
  created_vault_ids = var.key_vault.enable ? [azurerm_key_vault.this[0].id] : []

  # One role assignment per vault the identity should reach: caller-supplied
  # external ids plus any vault created here. Empty (no assignments) when the
  # managed identity is disabled.
  vault_ids = var.workload_identity.enable ? {
    for id in concat(var.workload_identity.key_vault_ids, local.created_vault_ids) : id => id
  } : {}
}
