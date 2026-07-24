resource "azurerm_user_assigned_identity" "this" {
  count               = var.workload_identity.enable ? 1 : 0
  name                = var.workload_identity.name
  resource_group_name = var.workload_identity.resource_group_name
  location            = var.workload_identity.location
}

resource "azurerm_federated_identity_credential" "this" {
  count               = var.workload_identity.enable ? 1 : 0
  name                = "${var.workload_identity.name}-fic"
  resource_group_name = var.workload_identity.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.workload_identity.oidc_issuer_url
  subject             = "system:serviceaccount:${var.workload_identity.service_account_namespace}:${var.workload_identity.service_account_name}"
}

resource "azurerm_role_assignment" "this" {
  for_each = local.vault_ids

  scope                = each.value
  role_definition_name = var.workload_identity.role
  principal_id         = azurerm_user_assigned_identity.this[0].principal_id
}
