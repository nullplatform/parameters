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
  validation {
    condition     = !var.workload_identity.enable || length(var.workload_identity.key_vault_ids) > 0
    error_message = "workload_identity.key_vault_ids must have at least one entry when workload_identity.enable=true."
  }
}
