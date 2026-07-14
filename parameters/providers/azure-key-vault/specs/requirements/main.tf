locals {
  sp_enabled = var.service_principal.enable

  # One role assignment per Key Vault, keyed by the vault resource ID so the
  # for_each is stable across plans.
  vault_ids = local.sp_enabled ? { for id in var.service_principal.key_vault_ids : id => id } : {}
}

resource "azuread_application" "this" {
  count        = local.sp_enabled ? 1 : 0
  display_name = var.service_principal.display_name
}

resource "azuread_service_principal" "this" {
  count     = local.sp_enabled ? 1 : 0
  client_id = azuread_application.this[0].client_id
}

resource "azuread_application_password" "this" {
  count          = local.sp_enabled ? 1 : 0
  application_id = azuread_application.this[0].id
  end_date       = var.service_principal.secret_end_date
}

resource "azurerm_role_assignment" "this" {
  for_each = local.vault_ids

  scope                = each.value
  role_definition_name = var.service_principal.role
  principal_id         = azuread_service_principal.this[0].object_id
}
