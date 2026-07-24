################################################################################
# Optional: create the Azure Key Vault this provider stores parameters in.
# Toggled independently of the managed identity via var.key_vault.enable.
# Created with the Azure RBAC authorization model (enable_rbac_authorization =
# true), which this provider requires — see docs/azure-rbac.md. The vault name
# MUST match the runtime provider config `vault_name` (coupling is by name).
################################################################################

resource "azurerm_key_vault" "this" {
  count = var.key_vault.enable ? 1 : 0

  name                = var.key_vault.name
  resource_group_name = var.key_vault.resource_group_name
  location            = var.key_vault.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault.sku_name

  # Required by this provider: RBAC data-plane authorization, not access policies.
  rbac_authorization_enabled = true

  # Hardened defaults (overridable via var.key_vault).
  purge_protection_enabled      = var.key_vault.purge_protection_enabled
  soft_delete_retention_days    = var.key_vault.soft_delete_retention_days
  public_network_access_enabled = var.key_vault.public_network_access_enabled

  tags = var.key_vault.tags

  dynamic "network_acls" {
    for_each = var.key_vault.network_acls != null ? [var.key_vault.network_acls] : []
    content {
      default_action             = network_acls.value.default_action
      bypass                     = network_acls.value.bypass
      ip_rules                   = network_acls.value.ip_rules
      virtual_network_subnet_ids = network_acls.value.virtual_network_subnet_ids
    }
  }
}
