# Azure RBAC

Minimum Azure permissions for `parameters/providers/azure-key-vault/`. The agent
authenticates as a service principal (or managed identity) and operates on
secrets in a specific Key Vault. Scope the role assignment to the vault so the
identity cannot reach any secret outside this provider's domain.

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
  --assignee "<service-principal-object-id>" \
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

The `specs/requirements/` tofu module can create the Azure AD application +
service principal, mint a client secret, and assign `Key Vault Secrets Officer`
over one or more vaults. Set `service_principal.enable = true` and pass the vault
resource IDs. Its outputs map directly onto the agent's environment:

| Output          | Agent env var         |
|-----------------|-----------------------|
| `client_id`     | `AZURE_CLIENT_ID`     |
| `client_secret` | `AZURE_CLIENT_SECRET` |
| `tenant_id`     | `AZURE_TENANT_ID`     |

The `setup` script performs an explicit `az login --service-principal` from these
env vars — the Azure CLI, unlike the Azure SDKs, does not read them automatically.

Applying this module requires the tofu caller to have directory permissions to
create app registrations and `Owner` / `User Access Administrator` on the vault
scope to create role assignments, plus a subscription (`ARM_SUBSCRIPTION_ID`) for
the `azurerm` provider.
