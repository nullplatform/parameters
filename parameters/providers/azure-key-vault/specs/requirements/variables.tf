variable "workload_identity" {
  description = <<-EOT
    Optionally create a user-assigned managed identity federated to the
    nullplatform agent's Kubernetes ServiceAccount (AKS Workload Identity), and
    grant it access to one or more Key Vaults via Azure RBAC. This is a
    secret-less credential: Azure injects short-lived tokens into the agent pod
    and rotates them automatically — nothing expires and nothing is written to
    state.
    Fields:
      enable                    — set true to create the managed identity,
                                  federated credential, and role assignments.
      name                      — name of the user-assigned managed identity
                                  (required when enable=true).
      resource_group_name       — resource group for the managed identity
                                  (required when enable=true).
      location                  — Azure region for the managed identity
                                  (required when enable=true).
      oidc_issuer_url           — the AKS cluster OIDC issuer URL (required when
                                  enable=true). Obtain with:
                                  az aks show -g <rg> -n <cluster> \
                                    --query oidcIssuerProfile.issuerUrl -o tsv
      service_account_namespace — Kubernetes namespace of the agent
                                  ServiceAccount (required when enable=true).
      service_account_name      — Kubernetes ServiceAccount name the agent runs
                                  as (required when enable=true).
      key_vault_ids             — resource IDs of the Key Vaults to grant access
                                  to, one role assignment per vault (>=1 required
                                  when enable=true). Example:
                                  "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>".
      role                      — RBAC role assigned on each vault. Default
                                  "Key Vault Secrets Officer" grants the secret
                                  get/list/set/delete/purge the agent needs.
    The client_id / tenant_id outputs annotate the agent's Kubernetes
    ServiceAccount (azure.workload.identity/client-id) and wire AZURE_TENANT_ID;
    the AKS workload-identity webhook injects AZURE_CLIENT_ID /
    AZURE_FEDERATED_TOKEN_FILE / AZURE_AUTHORITY_HOST into the pod.
  EOT
  type = object({
    enable                    = bool
    name                      = optional(string, "")
    resource_group_name       = optional(string, "")
    location                  = optional(string, "")
    oidc_issuer_url           = optional(string, "")
    service_account_namespace = optional(string, "")
    service_account_name      = optional(string, "")
    key_vault_ids             = optional(list(string), [])
    role                      = optional(string, "Key Vault Secrets Officer")
  })
  default = {
    enable = false
  }

  validation {
    condition     = !var.workload_identity.enable || var.workload_identity.name != ""
    error_message = "workload_identity.name is required when workload_identity.enable=true."
  }

  validation {
    condition     = !var.workload_identity.enable || var.workload_identity.resource_group_name != ""
    error_message = "workload_identity.resource_group_name is required when workload_identity.enable=true."
  }

  validation {
    condition     = !var.workload_identity.enable || var.workload_identity.location != ""
    error_message = "workload_identity.location is required when workload_identity.enable=true."
  }

  validation {
    condition     = !var.workload_identity.enable || var.workload_identity.oidc_issuer_url != ""
    error_message = "workload_identity.oidc_issuer_url is required when workload_identity.enable=true."
  }

  validation {
    condition     = !var.workload_identity.enable || var.workload_identity.service_account_namespace != ""
    error_message = "workload_identity.service_account_namespace is required when workload_identity.enable=true."
  }

  validation {
    condition     = !var.workload_identity.enable || var.workload_identity.service_account_name != ""
    error_message = "workload_identity.service_account_name is required when workload_identity.enable=true."
  }

  # NOTE: "at least one vault to scope to when enabled" is enforced as a
  # precondition in main.tf (terraform_data.validation), because the identity can
  # now be scoped either to var.workload_identity.key_vault_ids or to a vault
  # created here via var.key_vault.enable — a cross-variable check that a single
  # variable validation block cannot express on required_version >= 1.5.0.
  validation {
    condition = !var.workload_identity.enable || alltrue([
      for id in var.workload_identity.key_vault_ids :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", id))
    ])
    error_message = "Each workload_identity.key_vault_ids entry must be a full Key Vault resource ID (/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>), so the role assignment is scoped to the vault and not a broader scope."
  }
}

variable "key_vault" {
  description = <<-EOT
    Optionally create the Azure Key Vault this provider stores parameters in.
    Independent of var.workload_identity: you can create only the vault, only the
    managed identity, or both. When both are enabled the created vault is added
    to the identity's RBAC scope automatically (no need to wire a computed id).
    The vault is created with the Azure RBAC authorization model
    (enable_rbac_authorization = true), which this provider requires.
    IMPORTANT: key_vault.name MUST match the runtime provider config `vault_name`
    (and AZURE_KEY_VAULT_NAME) — that coupling is by name, not by reference.
    Fields:
      enable                        — set true to create the Key Vault.
      name                          — vault name (required when enable=true; must
                                      equal the runtime vault_name).
      resource_group_name           — resource group for the vault (required when enable=true).
      location                      — Azure region for the vault (required when enable=true).
      sku_name                      — "standard" (default) or "premium".
      purge_protection_enabled      — default true (hardened; blocks permanent
                                      delete during the soft-delete window).
      soft_delete_retention_days    — default 90.
      public_network_access_enabled — default true. Set false for private-only
                                      access (requires the agent to reach the
                                      vault over a private endpoint).
      network_acls                  — optional firewall rules (default_action,
                                      bypass, ip_rules, virtual_network_subnet_ids).
      tags                          — optional resource tags.
  EOT
  type = object({
    enable                        = bool
    name                          = optional(string, "")
    resource_group_name           = optional(string, "")
    location                      = optional(string, "")
    sku_name                      = optional(string, "standard")
    purge_protection_enabled      = optional(bool, true)
    soft_delete_retention_days    = optional(number, 90)
    public_network_access_enabled = optional(bool, true)
    network_acls = optional(object({
      default_action             = optional(string, "Allow")
      bypass                     = optional(string, "AzureServices")
      ip_rules                   = optional(list(string), [])
      virtual_network_subnet_ids = optional(list(string), [])
    }))
    tags = optional(map(string), {})
  })
  default = {
    enable = false
  }

  validation {
    condition     = !var.key_vault.enable || var.key_vault.name != ""
    error_message = "key_vault.name is required when key_vault.enable=true (and must match the runtime vault_name)."
  }

  validation {
    condition     = !var.key_vault.enable || var.key_vault.resource_group_name != ""
    error_message = "key_vault.resource_group_name is required when key_vault.enable=true."
  }

  validation {
    condition     = !var.key_vault.enable || var.key_vault.location != ""
    error_message = "key_vault.location is required when key_vault.enable=true."
  }

  validation {
    condition     = contains(["standard", "premium"], var.key_vault.sku_name)
    error_message = "key_vault.sku_name must be \"standard\" or \"premium\"."
  }
}
