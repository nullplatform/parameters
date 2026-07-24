# Azure RBAC

Minimum Azure permissions for `parameters/providers/azure-key-vault/`. The agent
authenticates as an AKS workload identity (a user-assigned managed identity
federated to its Kubernetes ServiceAccount) and operates on secrets in a specific
Key Vault. Scope the role assignment to the vault so the identity cannot reach any
secret outside this provider's domain.

This provider assumes the vault uses the **Azure RBAC** authorization model
(`enable_rbac_authorization = true`), not the legacy access-policy model.

---

## Required data actions

| Data action                                          | Used by    | Why                                                    |
|------------------------------------------------------|------------|--------------------------------------------------------|
| `Microsoft.KeyVault/vaults/secrets/setSecret/action` | `store`    | Creates the secret / adds a new version                |
| `Microsoft.KeyVault/vaults/secrets/getSecret/action` | `retrieve` | Reads the current (or a specific historical) version   |
| `Microsoft.KeyVault/vaults/secrets/delete`           | `delete`   | Soft-deletes the secret                                |
| `Microsoft.KeyVault/vaults/secrets/purge/action`     | `delete`   | Purges the soft-deleted secret to release the name     |

---

## Recommended role

The built-in **`Key Vault Secrets Officer`** role covers every data action above
(get, list, set, delete, recover, backup, restore, purge). Assign it scoped to
the vault:

```bash
az role assignment create \
  --assignee "<managed-identity-principal-id>" \
  --role "Key Vault Secrets Officer" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault-name>"
```

`Key Vault Secrets User` is **not** enough — it grants only get/list, so `store`
and `delete` would fail. Do not grant vault-management roles (e.g.
`Key Vault Administrator`); the agent only needs the secrets data plane.

### Purge

`delete` does a best-effort `az keyvault secret purge` after the soft-delete. The
`purge/action` is included in `Key Vault Secrets Officer`. If you deliberately
withhold purge, the provider downgrades the purge failure to a warning and the
secret remains in the soft-delete window until Azure auto-cleans it at retention
expiry (see `architecture.md`).

---

## Provisioning the identity (`specs/requirements/`)

The `specs/requirements/` tofu module can create a **user-assigned managed
identity** federated to the agent's Kubernetes ServiceAccount (AKS Workload
Identity) and assign `Key Vault Secrets Officer` over one or more vaults. Set
`workload_identity.enable = true` and pass the managed-identity name, resource
group, location, the AKS cluster `oidc_issuer_url`, the agent ServiceAccount
namespace/name, and the vault resource IDs. Its outputs are used as follows:

| Output         | Purpose                                                                  |
|----------------|--------------------------------------------------------------------------|
| `client_id`    | Annotate the agent ServiceAccount: `azure.workload.identity/client-id`   |
| `tenant_id`    | Agent env var `AZURE_TENANT_ID`                                          |
| `principal_id` | The RBAC principal the role assignment targets (informational)          |

Once the ServiceAccount is annotated with the `client_id` and the pod is labeled
`azure.workload.identity/use: "true"`, the AKS workload-identity webhook injects
`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_FEDERATED_TOKEN_FILE` /
`AZURE_AUTHORITY_HOST` into the pod. The `setup` script exchanges the projected
token with `az login --federated-token` — no long-lived client secret is ever
handled or written to state. The federated token itself is still bearer
credential material for its short validity window, and az CLI has no
file-reference form of `--federated-token`, so it briefly appears on that
process's argv (visible via `ps` / `/proc/<pid>/cmdline` to anything sharing
the pod's PID namespace) — the same residual exposure the old `--password`
service-principal login had. See "Security notes" below.

### Creating the vault (optional)

The same module can also create the Key Vault itself — set `key_vault.enable = true`
and pass `name`, `resource_group_name`, and `location`. It is created with the
Azure RBAC authorization model (`rbac_authorization_enabled = true`, which this
provider requires) and hardened defaults (purge protection on, 90-day soft-delete,
public network access overridable). The `key_vault` and `workload_identity` blocks
are **independent toggles** — create only the vault, only the identity, or both;
when both are enabled the created vault is added to the identity's RBAC scope
automatically. **`key_vault.name` MUST match the runtime provider config
`vault_name`** (and `AZURE_KEY_VAULT_NAME`) — the two are coupled by name, not by
reference, so a mismatch means the agent authenticates but reads the wrong vault.

Applying this module requires the tofu caller to have `Contributor` on the managed
identity's resource group (and on the vault's resource group when
`key_vault.enable = true`) and `Owner` / `User Access Administrator` on the vault
scope to create role assignments, plus a subscription (`ARM_SUBSCRIPTION_ID`) for
the `azurerm` provider. App-registration directory permissions are no longer
required.

---

## Security notes

- **No long-lived secret by construction.** The managed identity has no client
  secret: Azure issues short-lived tokens to the agent pod and rotates them
  automatically. Nothing expires, and no credential is written to tofu state.
  This is the recommended Azure equivalent of an AWS IAM role. The projected
  federated token the `setup` script exchanges is still short-lived bearer
  material and briefly appears on the `az login` process's argv (az CLI has
  no file-reference option for `--federated-token`) — treat pod PID-namespace
  isolation and host-level process-list access as part of this control, and
  do not enable `shareProcessNamespace` on the agent pod.
- **Federation is scoped to one ServiceAccount.** The federated credential
  subject is `system:serviceaccount:<namespace>:<name>`; only that pod identity
  in that AKS cluster can assume the managed identity.
- **Least privilege.** Assign only `Key Vault Secrets Officer` scoped per vault
  (as this module does). Do not grant vault-management roles.
