variable "service_principal" {
  description = <<-EOT
    Optionally create the Azure AD application + service principal the nullplatform
    agent uses to authenticate to Azure, and grant it access to one or more Key
    Vaults via Azure RBAC.
    Fields:
      enable          — set true to create the application, service principal, client
                        secret, and role assignments.
      display_name    — display name of the Azure AD application (required when enable=true).
      key_vault_ids   — resource IDs of the Key Vaults to grant access to, one role
                        assignment per vault (required when enable=true). Example:
                        "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>".
      role            — RBAC role assigned on each vault. Default "Key Vault Secrets Officer"
                        grants the secret get/list/set/delete/purge the agent needs.
      secret_end_date — RFC3339 expiry for the client secret (e.g. "2027-01-01T00:00:00Z").
                        Null uses the azuread provider default (2 years).
    The client_id / tenant_id / client_secret outputs are wired into the agent
    environment as AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_CLIENT_SECRET.
  EOT
  type = object({
    enable          = bool
    display_name    = optional(string, "")
    key_vault_ids   = optional(list(string), [])
    role            = optional(string, "Key Vault Secrets Officer")
    secret_end_date = optional(string, null)
  })
  default = {
    enable = false
  }

  validation {
    condition     = !var.service_principal.enable || var.service_principal.display_name != ""
    error_message = "service_principal.display_name is required when service_principal.enable=true."
  }

  validation {
    condition     = !var.service_principal.enable || length(var.service_principal.key_vault_ids) > 0
    error_message = "service_principal.key_vault_ids must have at least one entry when service_principal.enable=true."
  }
}
