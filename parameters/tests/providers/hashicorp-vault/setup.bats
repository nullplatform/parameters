#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/hashicorp-vault/setup
#
# setup authenticates against Vault (userpass or kubernetes) and exports the
# derived short-lived token as VAULT_TOKEN. curl (the login call) is mocked.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/hashicorp-vault/setup"

  # Mock curl — logs args, returns a login response with a client_token by default.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'EOF'
#!/bin/bash
echo "ARGS: $@" >> "$CURL_LOG"
# The request body is fed via stdin (--data @-); capture it so tests can assert on it.
if [ ! -t 0 ]; then echo "STDIN: $(cat)" >> "$CURL_LOG"; fi
if [ "${MOCK_CURL_EXIT:-0}" -ne 0 ]; then exit "$MOCK_CURL_EXIT"; fi
if [ -n "${MOCK_LOGIN_BODY:-}" ]; then
  printf '%s' "$MOCK_LOGIN_BODY"
else
  printf '%s' '{"auth":{"client_token":"hvs.derived-token"}}'
fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  # A readable ServiceAccount token file for kubernetes-mode tests.
  export SA_TOKEN_FILE="$BATS_TEST_TMPDIR/sa-token"
  printf 'eyJhbGc.k8s-jwt.sig' > "$SA_TOKEN_FILE"

  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"
}

teardown() {
  unset VAULT_ADDR VAULT_AUTH_MODE VAULT_TOKEN VAULT_PATH_PREFIX PROVIDER_CONFIG \
        VAULT_USERNAME VAULT_PASSWORD VAULT_K8S_ROLE VAULT_K8S_JWT_PATH \
        MOCK_LOGIN_BODY MOCK_CURL_EXIT
}

# --- Address / common -------------------------------------------------------

@test "vault setup: fails when VAULT_ADDR is missing" {
  unset VAULT_ADDR
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault address not configured"
}

@test "vault setup: address from PROVIDER_CONFIG" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export PROVIDER_CONFIG='{"setup":{"address":"https://cfg-vault.example.com"}}'

  run bash -c "$DEPS; source $SCRIPT && echo ADDR=\$VAULT_ADDR"

  assert_equal "$status" "0"
  assert_contains "$output" "ADDR=https://cfg-vault.example.com"
}

@test "vault setup: path_prefix defaults to secret/data/nullplatform when unset" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=secret/data/nullplatform"
}

@test "vault setup: path_prefix from PROVIDER_CONFIG (.setup.namespace)" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"secret/data/team-x"}}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=secret/data/team-x"
}

@test "vault setup: path_prefix from VAULT_PATH_PREFIX env var" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export VAULT_PATH_PREFIX="secret/data/from-env"

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=secret/data/from-env"
}

@test "vault setup: path_prefix from PROVIDER_CONFIG wins over VAULT_PATH_PREFIX env var" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export VAULT_PATH_PREFIX="secret/data/from-env"
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"secret/data/from-config"}}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=secret/data/from-config"
}

@test "vault setup: path_prefix trailing slash is trimmed" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"secret/data/team-x/"}}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=secret/data/team-x"
}

@test "vault setup: unknown auth_mode fails" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_AUTH_MODE="ldap"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Unknown Vault authentication mode 'ldap'"
}

# --- userpass mode (default) ------------------------------------------------

@test "vault setup: userpass fails when VAULT_USERNAME is missing" {
  export VAULT_ADDR="https://vault.example.com"
  unset VAULT_USERNAME
  export VAULT_PASSWORD="pw"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault username not configured"
}

@test "vault setup: userpass fails when VAULT_PASSWORD is missing" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  unset VAULT_PASSWORD

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault password not configured"
}

@test "vault setup: userpass credentials must come from env (not PROVIDER_CONFIG)" {
  export VAULT_ADDR="https://vault.example.com"
  unset VAULT_USERNAME VAULT_PASSWORD
  export PROVIDER_CONFIG='{"setup":{"username":"from-config","password":"from-config"}}'

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault username not configured"
}

@test "vault setup: userpass login exports derived VAULT_TOKEN" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"

  run bash -c "$DEPS; source $SCRIPT && echo TOKEN=\$VAULT_TOKEN"

  assert_equal "$status" "0"
  assert_contains "$output" "TOKEN=hvs.derived-token"
}

@test "vault setup: userpass POSTs password to the userpass login endpoint" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="s3cr3t"

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "-X POST"
  assert_contains "$captured" "https://vault.example.com/v1/auth/userpass/login/agent"
  assert_contains "$captured" '"password":"s3cr3t"'
}

@test "vault setup: userpass URL-encodes the username in the login path" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="ns/agent"
  export VAULT_PASSWORD="pw"

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "login/ns%2Fagent"
}

@test "vault setup: userpass login is NOT namespace-prefixed for the default prefix" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  # default prefix (secret/data/nullplatform) → root namespace, no prefix

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/auth/userpass/login/agent"
}

@test "vault setup: userpass login is prefixed with the Vault namespace (prefix ends in /data)" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  # admin/ns/data → Vault namespace = admin/ns
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"admin/ns/data"}}'

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/admin/ns/auth/userpass/login/agent"
}

@test "vault setup: VAULT_PATH_PREFIX export keeps the trailing /data segment when a namespace is derived" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  # Namespace derivation must not mutate VAULT_PATH_PREFIX itself — store/retrieve/
  # delete compose their Vault paths from the full prefix (including /data).
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"admin/ns/data"}}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$VAULT_PATH_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=admin/ns/data"
}

@test "vault setup: userpass login is NOT namespace-prefixed for a non-default root prefix (custom subpath, no Enterprise namespace)" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  # secret/data/team-x is a plain KV mount + subpath in the root namespace — the
  # `data` segment is in the MIDDLE, so no namespace is derived (backward compat).
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"secret/data/team-x"}}'

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/auth/userpass/login/agent"
}

@test "vault setup: userpass login is NOT namespace-prefixed when a subpath follows the data segment" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  # Only a TRAILING /data derives a namespace; admin/ns/data/foo has a subpath
  # after data, so it is treated as a root KV path (no namespace prefix).
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"admin/ns/data/foo"}}'

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/auth/userpass/login/agent"
}

@test "vault setup: userpass login namespace does not treat 'database' as the data segment" {
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","namespace":"myns/database/x"}}'

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  # 'database' is not the KV 'data' segment → no namespace derived → root login
  assert_contains "$captured" "https://vault.example.com/v1/auth/userpass/login/agent"
}

@test "vault setup: kubernetes login is prefixed with the Vault namespace" {
  export VAULT_AUTH_MODE="kubernetes"
  export VAULT_K8S_ROLE="nullplatform-agent"
  export VAULT_K8S_JWT_PATH="$SA_TOKEN_FILE"
  export PROVIDER_CONFIG='{"setup":{"address":"https://vault.example.com","auth_mode":"kubernetes","kubernetes_role":"nullplatform-agent","namespace":"admin/ns/data"}}'

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/admin/ns/auth/kubernetes/login"
}

@test "vault setup: userpass login without a token fails" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export MOCK_LOGIN_BODY='{"errors":["invalid username or password"]}'

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault userpass login did not return a token"
}

# --- kubernetes mode --------------------------------------------------------

@test "vault setup: non-JSON login response fails with troubleshooting (not a jq crash)" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_USERNAME="agent"
  export VAULT_PASSWORD="pw"
  export MOCK_LOGIN_BODY='<html>502 Bad Gateway</html>'

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault userpass login did not return a token"
}

@test "vault setup: auth_mode kubernetes from PROVIDER_CONFIG" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_K8S_JWT_PATH="$SA_TOKEN_FILE"
  export PROVIDER_CONFIG='{"setup":{"auth_mode":"kubernetes","kubernetes_role":"nullplatform-agent"}}'

  run bash -c "$DEPS; source $SCRIPT && echo TOKEN=\$VAULT_TOKEN"

  assert_equal "$status" "0"
  assert_contains "$output" "TOKEN=hvs.derived-token"
}

@test "vault setup: kubernetes fails when role is missing" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_AUTH_MODE="kubernetes"
  export VAULT_K8S_JWT_PATH="$SA_TOKEN_FILE"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Vault Kubernetes role not configured"
}

@test "vault setup: kubernetes fails when SA token file is unreadable" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_AUTH_MODE="kubernetes"
  export VAULT_K8S_ROLE="nullplatform-agent"
  export VAULT_K8S_JWT_PATH="$BATS_TEST_TMPDIR/does-not-exist"

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Kubernetes ServiceAccount token not readable"
}

@test "vault setup: kubernetes POSTs role + jwt to the kubernetes login endpoint" {
  export VAULT_ADDR="https://vault.example.com"
  export VAULT_AUTH_MODE="kubernetes"
  export VAULT_K8S_ROLE="nullplatform-agent"
  export VAULT_K8S_JWT_PATH="$SA_TOKEN_FILE"

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "https://vault.example.com/v1/auth/kubernetes/login"
  assert_contains "$captured" '"role":"nullplatform-agent"'
  assert_contains "$captured" '"jwt":"eyJhbGc.k8s-jwt.sig"'
}
