# Azure Key Vault Workload Identity Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Azure Key Vault `specs/requirements/` service-principal + client-secret credential with an AKS Workload Identity (user-assigned managed identity federated to the agent's Kubernetes ServiceAccount), eliminating the expiring secret.

**Architecture:** The `specs/requirements/` tofu module drops all `azuread_*` resources and provisions an `azurerm_user_assigned_identity` + `azurerm_federated_identity_credential`, keeping the existing per-vault `azurerm_role_assignment`. The `tenant_id` comes from `data.azurerm_client_config`. The agent `setup` script logs in with `az login --federated-token` (no secret on argv). Docs and CHANGELOG are updated. The `specs/install/` module is untouched (it does not consume these outputs).

**Tech Stack:** OpenTofu (`azurerm` provider >= 3.0), Bash, Azure CLI.

## Global Constraints

- Use **tofu** (open source), never `terraform`, for all CLI invocations.
- `required_version = ">= 1.5.0"`; pin `azurerm` at `>= 3.0`.
- Resource names use `snake_case`; the single instance is named `this`.
- Preserve the operator's in-progress file organization: `locals` live in `locals.tf` (not `main.tf`); every file ends with a trailing newline.
- The variable is renamed `service_principal` → `workload_identity` everywhere; no service-principal path remains.
- Commit messages: single line, conventional prefix, < 72 chars, no body, no Claude attribution.
- Do NOT touch `specs/install/` or anything under `.terraform/`.

---

### Task 1: Rewrite the `specs/requirements/` tofu module

Rename `service_principal` → `workload_identity` and swap the azuread app/SP/password for a federated user-assigned managed identity. All seven files in this module change together — `tofu validate` only passes when they are mutually consistent, so this is one task with one validation cycle.

**Files:**
- Modify: `parameters/providers/azure-key-vault/specs/requirements/variables.tf`
- Modify: `parameters/providers/azure-key-vault/specs/requirements/main.tf`
- Modify: `parameters/providers/azure-key-vault/specs/requirements/locals.tf`
- Modify: `parameters/providers/azure-key-vault/specs/requirements/data.tf`
- Modify: `parameters/providers/azure-key-vault/specs/requirements/versions.tf`
- Modify: `parameters/providers/azure-key-vault/specs/requirements/outputs.tf`
- Modify: `parameters/providers/azure-key-vault/specs/requirements/terraform.tfvars.example`
- Test: `tofu validate` / `tofu fmt` (no unit-test framework in this module)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: outputs `client_id`, `principal_id`, `tenant_id` (all `string`); variable `workload_identity` with fields `enable`, `name`, `resource_group_name`, `location`, `oidc_issuer_url`, `service_account_namespace`, `service_account_name`, `key_vault_ids`, `role`. Task 3 docs reference these names.

- [ ] **Step 1: Replace `variables.tf` with the `workload_identity` variable**

```hcl
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
```

- [ ] **Step 2: Replace `main.tf` with the managed-identity resources**

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

- [ ] **Step 3: Replace `locals.tf` (keep locals in their own file, add trailing newline)**

```hcl
locals {
  vault_ids = var.workload_identity.enable ? { for id in var.workload_identity.key_vault_ids : id => id } : {}
}
```

- [ ] **Step 4: Replace `data.tf` (tenant from azurerm, updated header)**

```hcl
################################################################################
# Optional: user-assigned managed identity federated to the agent's Kubernetes
# ServiceAccount (AKS Workload Identity), granted Key Vault access via Azure
# RBAC. Toggle with var.workload_identity.enable. Secret-less: Azure injects and
# rotates short-lived tokens in the agent pod. Outputs the client_id / tenant_id
# so operators can annotate the ServiceAccount and wire AZURE_TENANT_ID.
################################################################################

# Tenant tofu authenticates against (the managed identity lives in this tenant).
data "azurerm_client_config" "current" {}
```

- [ ] **Step 5: Replace `versions.tf` (drop the azuread provider)**

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

- [ ] **Step 6: Replace `outputs.tf` (drop `client_secret`, add `principal_id`)**

```hcl
output "client_id" {
  description = "Client ID of the user-assigned managed identity. Annotate the agent's Kubernetes ServiceAccount with azure.workload.identity/client-id. Empty when workload_identity.enable=false."
  value       = length(azurerm_user_assigned_identity.this) > 0 ? azurerm_user_assigned_identity.this[0].client_id : ""
}

output "principal_id" {
  description = "Principal (object) ID of the managed identity — the RBAC role assignment principal. Empty when workload_identity.enable=false."
  value       = length(azurerm_user_assigned_identity.this) > 0 ? azurerm_user_assigned_identity.this[0].principal_id : ""
}

output "tenant_id" {
  description = "Tenant ID the managed identity belongs to. Wire into the agent as AZURE_TENANT_ID."
  value       = data.azurerm_client_config.current.tenant_id
}
```

- [ ] **Step 7: Replace `terraform.tfvars.example`**

```hcl
workload_identity = {
  enable                    = true
  name                      = "nullplatform-agent-azure-key-vault"
  resource_group_name       = "acme-prod"
  location                  = "eastus"
  oidc_issuer_url           = "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
  service_account_namespace = "nullplatform"
  service_account_name      = "nullplatform-agent"
  key_vault_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-prod/providers/Microsoft.KeyVault/vaults/acme-prod-billing-kv",
  ]
  # role = "Key Vault Secrets Officer"  # default
}
```

- [ ] **Step 8: Format and validate the module (offline)**

```bash
cd parameters/providers/azure-key-vault/specs/requirements
tofu fmt
rm -rf .terraform
tofu init -backend=false
tofu validate
```
Expected: `tofu validate` prints `Success! The configuration is valid.` No reference to `azuread`, `service_principal`, `client_secret`, `display_name`, or `secret_end_date` remains (`grep -rn 'azuread\|service_principal\|client_secret\|display_name\|secret_end_date' .` returns nothing outside `.terraform/`).

- [ ] **Step 9: Verify the disabled path plans to zero resources**

```bash
tofu plan -backend=false -var 'workload_identity={enable=false}'
```
Expected: `No changes. Your infrastructure matches the configuration.` (or "0 to add") — with `enable=false` no managed identity, credential, or role assignment is created. (A populated-block `plan` needs real Azure credentials; skip unless `ARM_SUBSCRIPTION_ID` and a login are available.)

- [ ] **Step 10: Commit**

```bash
cd /Users/federico.maleh/nullplatform/apps/parameters-provider
git add parameters/providers/azure-key-vault/specs/requirements/
git commit -m "feat: migrate azure-key-vault requirements to AKS workload identity"
```

---

### Task 2: Switch the agent `setup` script to federated-token login

**Files:**
- Modify: `parameters/providers/azure-key-vault/setup:35-63`
- Test: `bash -n setup` + `shellcheck setup`

**Interfaces:**
- Consumes: the workload-identity env vars injected by the AKS webhook (`AZURE_FEDERATED_TOKEN_FILE`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Replace the header comment about auth (lines ~8-13)**

Replace the paragraph beginning "Auth comes from the Azure CLI's credential chain..." with:

```bash
# Auth comes from the Azure CLI's credential chain (managed identity, prior
# `az login`). Under AKS Workload Identity the pod receives a projected
# ServiceAccount token at AZURE_FEDERATED_TOKEN_FILE (plus AZURE_CLIENT_ID /
# AZURE_TENANT_ID); this script exchanges it for an Azure session with
# `az login --federated-token`. No client secret is involved.
```

- [ ] **Step 2: Replace the login branch (current lines 35-63)**

```bash
# Workload-identity login (optional; see the header note above). Skipped when a
# session already exists (managed identity via IMDS or a prior `az login`).
#
# The federated token is a short-lived, projected ServiceAccount token — not a
# secret — so `az login --federated-token` carries no rotating credential and
# nothing sensitive lands in state. This is the secret-less replacement for the
# old `--password` service-principal login. See docs/azure-rbac.md.
if [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ] && [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ]; then
  if ! az account show >/dev/null 2>&1; then
    if ! az login --service-principal \
          --username "$AZURE_CLIENT_ID" \
          --tenant "$AZURE_TENANT_ID" \
          --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")" \
          --allow-no-subscriptions >/dev/null 2>&1; then
      log error "❌ Azure workload-identity login failed"
      log error ""
      log error "💡 Possible causes:"
      log error "   • AZURE_CLIENT_ID / AZURE_TENANT_ID do not match the managed identity"
      log error "   • The federated credential subject does not match this pod's ServiceAccount"
      log error "   • The ServiceAccount is missing the azure.workload.identity/client-id annotation"
      log error ""
      log error "🔧 How to fix:"
      log error "   • Verify client_id / tenant_id from the specs/requirements outputs"
      log error "   • Confirm the federated credential subject is system:serviceaccount:<ns>:<sa>"
      log error "   • Ensure the pod is labeled azure.workload.identity/use: \"true\""
      exit 1
    fi
  fi
fi
```

- [ ] **Step 3: Syntax + lint check**

```bash
cd parameters/providers/azure-key-vault
bash -n setup
shellcheck setup   # skip if shellcheck is not installed
```
Expected: no output from `bash -n`; shellcheck reports no new errors. Confirm no `--password` / `AZURE_CLIENT_SECRET` reference remains: `grep -n 'password\|CLIENT_SECRET' setup` returns nothing.

- [ ] **Step 4: Commit**

```bash
cd /Users/federico.maleh/nullplatform/apps/parameters-provider
git add parameters/providers/azure-key-vault/setup
git commit -m "feat: authenticate azure-key-vault setup via workload-identity token"
```

---

### Task 3: Update docs and CHANGELOG

**Files:**
- Modify: `parameters/providers/azure-key-vault/docs/azure-rbac.md`
- Modify: `parameters/providers/azure-key-vault/docs/architecture.md:~90`
- Modify: `CHANGELOG.md`
- Test: manual read-through (docs only)

**Interfaces:**
- Consumes: output names from Task 1 (`client_id`, `principal_id`, `tenant_id`) and the login mechanism from Task 2.
- Produces: nothing.

- [ ] **Step 1: Update `docs/azure-rbac.md` "Provisioning the identity" section**

Replace the section body (currently lines ~51-70) so it describes the managed identity. Key edits:
- Opening: "The `specs/requirements/` tofu module can create a **user-assigned managed identity** federated to the agent's Kubernetes ServiceAccount (AKS Workload Identity) and assign `Key Vault Secrets Officer` over one or more vaults. Set `workload_identity.enable = true`."
- Replace the outputs table with:

```markdown
| Output         | Purpose                                                              |
|----------------|----------------------------------------------------------------------|
| `client_id`    | Annotate the agent ServiceAccount: `azure.workload.identity/client-id` |
| `tenant_id`    | Agent env var `AZURE_TENANT_ID`                                      |
| `principal_id` | The RBAC principal (informational)                                  |
```

- Replace the `az login --service-principal` note with: "The AKS workload-identity webhook injects `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_FEDERATED_TOKEN_FILE` / `AZURE_AUTHORITY_HOST` into the pod once its ServiceAccount is annotated with the `client_id` and the pod is labeled `azure.workload.identity/use: \"true\"`. The `setup` script exchanges the projected token with `az login --federated-token` — no secret."
- Update the "requires the tofu caller to have..." paragraph: the caller needs `Owner`/`User Access Administrator` on the vault scope (role assignments) and Contributor on the managed identity's resource group; app-registration directory permissions are **no longer required**.

- [ ] **Step 2: Rewrite the "Security notes" bullets in `docs/azure-rbac.md`**

Remove the "State holds a live secret" and "Secret on the CLI process line" bullets. Replace with:

```markdown
- **No secret by construction.** The managed identity has no client secret:
  Azure issues short-lived tokens to the agent pod and rotates them
  automatically. Nothing expires, and no credential is written to tofu state.
  This is the recommended Azure equivalent of an AWS IAM role.
- **Federation is scoped to one ServiceAccount.** The federated credential
  subject is `system:serviceaccount:<namespace>:<name>`; only that pod identity
  in that AKS cluster can assume the managed identity.
- **Least privilege.** Assign only `Key Vault Secrets Officer` scoped per vault
  (as this module does). Do not grant vault-management roles.
```

- [ ] **Step 3: Update the intro line of `docs/azure-rbac.md`**

Change "The agent authenticates as a service principal (or managed identity)..." to "The agent authenticates as an AKS workload identity (a user-assigned managed identity federated to its Kubernetes ServiceAccount)...".

- [ ] **Step 4: Update `docs/architecture.md` (~line 90)**

Change the auth line from `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` to: "`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_FEDERATED_TOKEN_FILE` env vars are present (injected by the AKS workload-identity webhook)". Confirm with `grep -n AZURE_CLIENT_SECRET docs/architecture.md` returning nothing afterward.

- [ ] **Step 5: Update `CHANGELOG.md` under `[Unreleased]`**

Edit the existing `Added` bullet that mentions "provisions an Azure AD service principal and grants it the Key Vault Secrets Officer RBAC role" to read "provisions a user-assigned managed identity (AKS Workload Identity) and grants it the Key Vault Secrets Officer RBAC role." Edit the `setup` bullet to: "Azure Key Vault `setup` authenticates the Azure CLI via AKS workload-identity federated token when `AZURE_FEDERATED_TOKEN_FILE` / `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` are present." Add under `Changed`:

```markdown
- Migrate the Azure Key Vault `specs/requirements/` identity from a service principal + client secret to an AKS Workload Identity (user-assigned managed identity federated to the agent's Kubernetes ServiceAccount), removing the expiring secret and the secret in tofu state.
```

- [ ] **Step 6: Commit**

```bash
cd /Users/federico.maleh/nullplatform/apps/parameters-provider
git add parameters/providers/azure-key-vault/docs/azure-rbac.md parameters/providers/azure-key-vault/docs/architecture.md CHANGELOG.md
git commit -m "docs: document azure-key-vault workload identity migration"
```

---

### Task 4: Quality gate

- [ ] **Step 1: Run the repo quality-gate skill**

Invoke the `quality-gate` skill over the branch changes (code review, security audit, simplification, test coverage). Address any findings, then re-run until clean.

---

## Self-Review

**Spec coverage:** Every spec section maps to a task — module resources/variables/outputs/data/versions/tfvars (Task 1, steps 1-7), setup script (Task 2), docs azure-rbac + architecture + CHANGELOG (Task 3), verification/quality-gate (Task 1 steps 8-9, Task 4). No gaps.

**Placeholder scan:** No TBD/TODO; every code step shows full file or block content; error-handling text is spelled out verbatim in Task 2.

**Type consistency:** Output names (`client_id`, `principal_id`, `tenant_id`) and variable field names are identical across Task 1, Task 3, and the design doc. Federated-credential `subject` string format matches the `setup` script's expected ServiceAccount and the doc's stated subject. `oidc_issuer_url` is a direct input in both the variable and the tfvars example.
