# Azure Key Vault requirements: migrate from service principal + client secret to AKS Workload Identity

Date: 2026-07-24
Provider: `parameters/providers/azure-key-vault/`
Status: approved design, pending implementation plan

## Problem

The `specs/requirements/` tofu module provisions an Azure AD application + service
principal and mints a **client secret** (`azuread_application_password`) that the
nullplatform agent uses to authenticate to Azure Key Vault. A client secret is the
Azure analog of an AWS IAM *user access key*: it is a static credential that

- expires (`secret_end_date`, default ~2 years) and must be rotated,
- is written to tofu state in plaintext, and
- is passed to `az login --password` on argv, briefly visible in the process table.

The agent runs **inside Azure on AKS**, so the correct analog of an AWS IAM *role*
is a **Managed Identity** consumed via **AKS Workload Identity** — a federated,
secret-less credential. The platform injects short-lived tokens and rotates them
automatically; there is no secret to expire, rotate, store in state, or leak.

## Decision

Replace the service-principal + client-secret model with a **User-Assigned Managed
Identity federated to the agent's Kubernetes ServiceAccount** (AKS Workload
Identity). The `service_principal` path is removed entirely (not kept as a toggle).

The `specs/install/` module does not consume the `specs/requirements/` outputs, so
it is unaffected.

## Design

### 1. `specs/requirements/main.tf` — resources

Remove `azuread_application`, `azuread_service_principal`, `azuread_application_password`.
Add a user-assigned managed identity and a federated identity credential. Keep the
`azurerm_role_assignment` unchanged except for the principal source.

```hcl
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
```

### 2. `specs/requirements/variables.tf` — variable `workload_identity`

Replaces `service_principal`. Fields:

| Field                        | Type            | Notes                                                              |
|------------------------------|-----------------|--------------------------------------------------------------------|
| `enable`                     | bool            | Toggle the whole block.                                            |
| `name`                       | string          | Name of the user-assigned managed identity. Required when enabled. |
| `resource_group_name`        | string          | RG for the managed identity. Required when enabled.                |
| `location`                   | string          | Azure region for the managed identity. Required when enabled.      |
| `oidc_issuer_url`            | string          | AKS cluster OIDC issuer URL. Required when enabled. Obtain with `az aks show -g <rg> -n <cluster> --query oidcIssuerProfile.issuerUrl -o tsv`. |
| `service_account_namespace`  | string          | K8s namespace of the agent ServiceAccount. Required when enabled.  |
| `service_account_name`       | string          | K8s ServiceAccount name of the agent. Required when enabled.       |
| `key_vault_ids`              | list(string)    | One role assignment per vault. >=1 required when enabled.          |
| `role`                       | string          | Default `Key Vault Secrets Officer`.                               |

Removed fields: `display_name`, `secret_end_date` (no app registration, no secret).

Validations (mirroring the existing style): when `enable=true`, require
`name`, `resource_group_name`, `location`, `oidc_issuer_url`,
`service_account_namespace`, `service_account_name` non-empty and
`length(key_vault_ids) > 0`.

### 3. `specs/requirements/locals.tf`

`vault_ids` keys off `var.workload_identity.enable` / `.key_vault_ids` instead of
`var.service_principal.*`.

### 4. `specs/requirements/data.tf`

Replace `data "azuread_client_config" "current"` with
`data "azurerm_client_config" "current"` for `tenant_id`. Update the header comment
to describe the workload-identity model.

### 5. `specs/requirements/outputs.tf`

- `client_id` → `azurerm_user_assigned_identity.this[0].client_id` — annotate the
  agent's K8s ServiceAccount with `azure.workload.identity/client-id: <client_id>`.
- `tenant_id` → `data.azurerm_client_config.current.tenant_id`.
- `principal_id` → `azurerm_user_assigned_identity.this[0].principal_id` (the RBAC
  principal). Replaces the old `object_id` output.
- **Remove** `client_secret` (no secret exists).

Each returns `""` when `enable=false`, consistent with the current module.

### 6. `specs/requirements/versions.tf`

Remove the `azuread` required_provider and its empty `provider "azuread" {}` block.
Keep `azurerm`.

### 7. `specs/requirements/terraform.tfvars.example`

Rewrite for the `workload_identity` object with realistic placeholder values for
`name`, `resource_group_name`, `location`, `oidc_issuer_url`,
`service_account_namespace`, `service_account_name`, `key_vault_ids`.

### 8. `setup` script

Replace the client-secret login branch with the federated-token branch. AKS
Workload Identity injects `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_FEDERATED_TOKEN_FILE`, `AZURE_AUTHORITY_HOST` into the pod. The Azure CLI
consumes the federated token via `--federated-token` (not `--password`):

```bash
if [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ] && [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ]; then
  if ! az account show >/dev/null 2>&1; then
    if ! az login --service-principal \
          --username "$AZURE_CLIENT_ID" \
          --tenant "$AZURE_TENANT_ID" \
          --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")" \
          --allow-no-subscriptions >/dev/null 2>&1; then
      log error "❌ Azure workload-identity login failed"
      # ...actionable causes/fixes...
      exit 1
    fi
  fi
fi
```

No secret ever appears on argv or in state. Update the header comment accordingly.

### 9. Docs

- `docs/azure-rbac.md`: update the "Provisioning the identity" section (outputs
  table drops `client_secret`, adds `principal_id`; env-var mapping becomes
  `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` + the injected `AZURE_FEDERATED_TOKEN_FILE`),
  and the "Security notes" (remove "State holds a live secret" and "Secret on the
  CLI process line"; state that the module is now secret-less by construction).
  Note the operator step of annotating/labeling the K8s ServiceAccount + pod for
  Workload Identity.
- `docs/architecture.md`: update the auth line (line ~90) from
  `AZURE_CLIENT_ID/AZURE_CLIENT_SECRET/AZURE_TENANT_ID` to the workload-identity
  env vars.

### 10. CHANGELOG.md

Under `[Unreleased] > Changed`, add: migrate the Azure Key Vault
`specs/requirements/` identity from a service principal + client secret to an AKS
Workload Identity (user-assigned managed identity federated to the agent's
Kubernetes ServiceAccount), eliminating the expiring secret. Update the existing
`[Unreleased] > Added` line that mentions the service principal to reflect the
managed-identity model.

## Out of scope / non-goals

- App Service / VM (non-AKS) managed identity variants.
- Keeping the service-principal path as an alternative toggle (explicitly removed).
- The K8s ServiceAccount annotation/label and pod deployment — outside this tofu
  module; documented as an operator step.

## Testing / verification

- `tofu init && tofu validate` in `specs/requirements/`.
- `tofu plan` with `enable=false` (no resources) and with a fully populated
  `workload_identity` block using placeholder values (plan-only; do not apply).
- `bash -n setup` and a `shellcheck` pass; confirm the `az login --federated-token`
  invocation shape against the Azure CLI docs.
- Run the repo `quality-gate` skill after implementation.
