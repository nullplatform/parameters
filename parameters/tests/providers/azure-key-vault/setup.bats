#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure-key-vault/setup
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure-key-vault/setup"
  export DEPS="source $PARAMETERS_DIR/utils/log; source $PARAMETERS_DIR/utils/get_config_value"

  # Mock `az`: logs every invocation and lets each subcommand's exit code be
  # driven per-test. Only exercised by the workload-identity login tests — the
  # other tests never set the federated-token env vars, so setup never calls az.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export AZ_LOG="$BATS_TEST_TMPDIR/az.log"
  cat > "$BATS_TEST_TMPDIR/bin/az" << 'EOF'
#!/bin/bash
echo "az $*" >> "$AZ_LOG"
case "$1" in
  account) exit "${MOCK_AZ_ACCOUNT_SHOW_EXIT:-0}" ;;
  login)   exit "${MOCK_AZ_LOGIN_EXIT:-0}" ;;
esac
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/az"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

teardown() {
  unset AZURE_KEY_VAULT_NAME AZ_VAULT_NAME AZ_SECRET_PREFIX PROVIDER_CONFIG \
    AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_FEDERATED_TOKEN_FILE \
    MOCK_AZ_ACCOUNT_SHOW_EXIT MOCK_AZ_LOGIN_EXIT
}

@test "azure-key-vault setup: fails when vault name is missing" {
  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Azure Key Vault name not configured"
  assert_contains "$output" "🔧 How to fix:"
}

@test "azure-key-vault setup: vault name from env" {
  export AZURE_KEY_VAULT_NAME="my-vault"

  run bash -c "$DEPS; source $SCRIPT && echo VAULT=\$AZ_VAULT_NAME PREFIX=\$AZ_SECRET_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "VAULT=my-vault"
  assert_contains "$output" "PREFIX=nullplatform-"
}

@test "azure-key-vault setup: secret_prefix is hardcoded to nullplatform-" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  # PROVIDER_CONFIG tries to override; ignored
  export PROVIDER_CONFIG='{"secret_prefix":"app-secret-"}'

  run bash -c "$DEPS; source $SCRIPT && echo PREFIX=\$AZ_SECRET_PREFIX"

  assert_equal "$status" "0"
  assert_contains "$output" "PREFIX=nullplatform-"
}

@test "azure-key-vault setup: vault_name from PROVIDER_CONFIG" {
  export PROVIDER_CONFIG='{"setup":{"vault_name":"cfg-vault"}}'

  run bash -c "$DEPS; source $SCRIPT && echo VAULT=\$AZ_VAULT_NAME"

  assert_equal "$status" "0"
  assert_contains "$output" "VAULT=cfg-vault"
}

@test "azure-key-vault setup: logs in with workload identity federated token when not authenticated" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_CLIENT_ID="client-123"
  export AZURE_TENANT_ID="tenant-xyz"
  export AZURE_FEDERATED_TOKEN_FILE="$BATS_TEST_TMPDIR/federated-token"
  echo -n "federated-token-abc" > "$AZURE_FEDERATED_TOKEN_FILE"
  export MOCK_AZ_ACCOUNT_SHOW_EXIT=1 # not logged in

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "az account show"
  assert_contains "$captured" "login --service-principal --username client-123 --tenant tenant-xyz --federated-token federated-token-abc --allow-no-subscriptions"
}

@test "azure-key-vault setup: skips login when already authenticated" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_CLIENT_ID="client-123"
  export AZURE_TENANT_ID="tenant-xyz"
  export AZURE_FEDERATED_TOKEN_FILE="$BATS_TEST_TMPDIR/federated-token"
  echo -n "federated-token-abc" > "$AZURE_FEDERATED_TOKEN_FILE"
  export MOCK_AZ_ACCOUNT_SHOW_EXIT=0 # already logged in

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "az account show"
  [[ "$captured" != *"login --service-principal"* ]]
}

@test "azure-key-vault setup: skips workload-identity login when only some env vars are set" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_CLIENT_ID="client-123"
  # AZURE_TENANT_ID and AZURE_FEDERATED_TOKEN_FILE intentionally left unset —
  # the guard requires all three, so this must fall through to the default
  # credential chain (no az call at all) instead of failing or half-logging-in.
  export MOCK_AZ_ACCOUNT_SHOW_EXIT=1

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  [ ! -s "$AZ_LOG" ]
}

@test "azure-key-vault setup: fails with troubleshooting when workload-identity login fails" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_CLIENT_ID="client-123"
  export AZURE_TENANT_ID="tenant-xyz"
  export AZURE_FEDERATED_TOKEN_FILE="$BATS_TEST_TMPDIR/federated-token"
  echo -n "federated-token-abc" > "$AZURE_FEDERATED_TOKEN_FILE"
  export MOCK_AZ_ACCOUNT_SHOW_EXIT=1 # not logged in
  export MOCK_AZ_LOGIN_EXIT=1        # login fails

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Azure workload-identity login failed"
  assert_contains "$output" "🔧 How to fix:"
}
