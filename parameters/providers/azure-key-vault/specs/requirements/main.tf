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

################################################################################
# Wiring example: connect this module's outputs to the nullplatform agent.
#
# The agent (github.com/nullplatform/tofu-modules//nullplatform/agent) runs on
# AKS and authenticates to Azure via Workload Identity using the managed
# identity created above. This block is COMMENTED OUT on purpose — uncommenting
# it would deploy an agent. It is here only as a copy-paste reference.
#
# Key rule: the agent's Kubernetes namespace + ServiceAccount name MUST match
# the values passed to var.workload_identity here (service_account_namespace /
# service_account_name), because the federated credential's subject is
# "system:serviceaccount:<namespace>:<name>". A mismatch fails the token
# exchange at runtime (AADSTS70021), not at plan/apply time.
#
# If the agent is deployed from a separate stack (the usual case), source the
# three values below via terraform_remote_state or tfvars instead of the
# module.* references shown here.
#
# module "agent" {
#   source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref=vX.Y.Z"
#
#   cloud_provider = "azure"
#
#   # --- Workload Identity wiring (from this module's outputs) ---
#   azure_use_workload_identity   = true # secret-less; no azure_client_secret
#   azure_client_id               = module.azure_key_vault_requirements.client_id
#   azure_tenant_id               = module.azure_key_vault_requirements.tenant_id
#   azure_federated_credential_id = module.azure_key_vault_requirements.federated_credential_id # orders the release after the credential
#
#   # --- Must match var.workload_identity.service_account_* passed here ---
#   namespace            = "nullplatform"       # == var.workload_identity.service_account_namespace
#   service_account_name = "nullplatform-agent" # == var.workload_identity.service_account_name
#
#   # --- Plus the agent module's other required inputs ---
#   api_key               = var.np_api_key
#   cluster_name          = "your-aks-cluster"
#   nrn                   = "organization=...:account=...:namespace=..."
#   tags_selectors        = { key = "value" }
#   image_tag             = "your-image-tag"
#   azure_subscription_id = "your-subscription-id"
#   azure_resource_group  = var.workload_identity.resource_group_name
#   # private_gateway_name / private_hosted_zone_rg / public_gateway_name as required
# }
################################################################################
