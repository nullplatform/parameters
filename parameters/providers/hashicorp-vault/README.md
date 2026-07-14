# HashiCorp Vault parameters provider

Stores nullplatform parameter values in HashiCorp Vault KV v2, using Vault's
native versioning. See [`docs/architecture.md`](./docs/architecture.md) for the
full lifecycle, storage layout, and versioning model.

## Configuration

Provider config (from the nullplatform provider specification):

| Field                  | Required            | Description                                                                 |
|------------------------|---------------------|-----------------------------------------------------------------------------|
| `setup.address`        | yes                 | Vault HTTP(S) endpoint, e.g. `https://vault.example.com:8200`.               |
| `setup.namespace`      | no (default `secret/data/nullplatform`) | KV v2 mount + path prefix parameters are stored under. |
| `setup.auth_mode`      | yes (default `userpass`) | Authentication mode: `userpass` or `kubernetes`.                       |
| `setup.kubernetes_role`| when `kubernetes`   | Vault Kubernetes auth role bound to the agent's ServiceAccount.              |

The KV path prefix defaults to `secret/data/nullplatform` and is configurable via
`setup.namespace` (or the `VAULT_PATH_PREFIX` env var). It must include the KV v2
`data/` segment. The auth mounts are fixed to Vault's defaults (`auth/userpass`,
`auth/kubernetes`).

> **Note:** the Vault policy examples below grant access to the default
> `secret/data/nullplatform/*` (and `secret/metadata/nullplatform/*`) paths. If you
> set a custom `setup.namespace`, adjust the policy paths to match it — the KV mount
> and the `metadata/` counterpart of your configured `data/` path.

## Authentication

`setup` exchanges the configured credentials/identity for a short-lived Vault
client token and exports it as `VAULT_TOKEN`; `store` / `retrieve` / `delete` then
use it via the `X-Vault-Token` header.

### Mode: `userpass`

The agent logs in with a username and password. Both are **sensitive** and are
read from environment variables in the agent runtime — never from provider config:

| Env var          | Description                       |
|------------------|-----------------------------------|
| `VAULT_USERNAME` | Vault `userpass` username.        |
| `VAULT_PASSWORD` | Vault `userpass` password.        |

Vault setup:

```sh
# Enable userpass (once per Vault)
vault auth enable userpass

# Policy granting read/write on the nullplatform namespace
vault policy write nullplatform-parameters - <<'EOF'
path "secret/data/nullplatform/*"     { capabilities = ["create", "update", "read"] }
path "secret/metadata/nullplatform/*" { capabilities = ["read", "delete", "list"] }
EOF

# Create the user and bind the policy
vault write auth/userpass/users/<username> \
  password="<password>" \
  token_policies="nullplatform-parameters"
```

Set `VAULT_USERNAME` / `VAULT_PASSWORD` in the agent Helm installation (as secret
env vars).

### Mode: `kubernetes`

The agent authenticates with its **Kubernetes ServiceAccount identity** — there
are no secrets to configure. It reads the projected ServiceAccount token (default
path `/var/run/secrets/kubernetes.io/serviceaccount/token`, overridable via
`VAULT_K8S_JWT_PATH`) and exchanges it for a Vault token bound to `kubernetes_role`.

#### 1. Vault setup

```sh
# Enable the kubernetes auth method (once per Vault)
vault auth enable kubernetes

# Point Vault at the cluster's API server. When Vault runs inside the cluster it
# can use its own ServiceAccount token and the in-cluster CA:
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# Policy granting read/write on the nullplatform namespace
vault policy write nullplatform-parameters - <<'EOF'
path "secret/data/nullplatform/*"     { capabilities = ["create", "update", "read"] }
path "secret/metadata/nullplatform/*" { capabilities = ["read", "delete", "list"] }
EOF

# Role binding the agent's ServiceAccount (name + namespace) to the policy.
# The role name here must match setup.kubernetes_role.
vault write auth/kubernetes/role/nullplatform-agent \
  bound_service_account_names="<agent-serviceaccount>" \
  bound_service_account_namespaces="<agent-namespace>" \
  token_policies="nullplatform-parameters" \
  ttl="1h"
```

#### 2. Cluster setup

The in-cluster resources Vault's kubernetes auth needs are provisioned by the
Terraform module in [`specs/requirements/`](./specs/requirements/) — it applies
`.yaml` templates for the agent ServiceAccount and the token-reviewer
ServiceAccount + its `system:auth-delegator` ClusterRoleBinding:

```sh
cd specs/requirements
cp terraform.tfvars.example terraform.tfvars   # edit agent namespace + SA name
tofu init && tofu apply
```

> The manifests are applied with `kubernetes_manifest`, which reaches the cluster
> API at **plan** time (server-side dry-run), not just apply. Make sure the target
> cluster is reachable and pin the context with `kube_config_context` — this module
> creates a cluster-wide `ClusterRoleBinding`.

Its outputs (`agent_service_account`, `token_reviewer_service_account`) give the
names/namespaces to plug into the Vault role bindings and the `token_reviewer_jwt`
above. The agent pod must run with that ServiceAccount and mount its token
(`serviceAccountName: <agent-serviceaccount>`, `automountServiceAccountToken: true`).

Then set `setup.auth_mode = kubernetes` and `setup.kubernetes_role = nullplatform-agent`
in the provider config (see [`specs/install/`](./specs/install/)). No credential
env vars are needed in this mode.

## Installation

The provider specification and per-instance configs are installed with the
Terraform in [`specs/install/`](./specs/install/), which builds on the shared
`parameter_storage_definition` / `parameter_storage_configuration` modules
(same structure as the AWS providers). For the `kubernetes` auth mode, apply
[`specs/requirements/`](./specs/requirements/) first (see above).

## Troubleshooting

`setup` fails fast with actionable messages when the address or credentials are
missing, and when the login endpoint returns no token (wrong credentials, role
not bound to the ServiceAccount, or the auth method not enabled). Re-read the
error output — it names the exact env var / config field / Vault command to check.
