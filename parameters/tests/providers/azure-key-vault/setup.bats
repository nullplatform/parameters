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
  # driven per-test. Only exercised by the service-principal login tests — the
  # other tests never set the SP env vars, so setup never calls az.
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
  unset AZURE_KEY_VAULT_NAME AZ_VAULT_NAME AZ_SECRET_PREFIX PROVIDER_CONFIG
  unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID
  unset MOCK_AZ_ACCOUNT_SHOW_EXIT MOCK_AZ_LOGIN_EXIT
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

@test "azure-key-vault setup: logs in with service principal when not authenticated" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_CLIENT_ID="client-123"
  export AZURE_CLIENT_SECRET="secret-abc"
  export AZURE_TENANT_ID="tenant-xyz"
  export MOCK_AZ_ACCOUNT_SHOW_EXIT=1 # not logged in

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "az account show"
  assert_contains "$captured" "login --service-principal --username client-123 --password secret-abc --tenant tenant-xyz --allow-no-subscriptions"
}

@test "azure-key-vault setup: skips login when already authenticated" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_CLIENT_ID="client-123"
  export AZURE_CLIENT_SECRET="secret-abc"
  export AZURE_TENANT_ID="tenant-xyz"
  export MOCK_AZ_ACCOUNT_SHOW_EXIT=0 # already logged in

  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  captured=$(cat "$AZ_LOG")
  assert_contains "$captured" "az account show"
  [[ "$captured" != *"login --service-principal"* ]]
}

@test "azure-key-vault setup: fails with troubleshooting when service principal login fails" {
  export AZURE_KEY_VAULT_NAME="my-vault"
  export AZURE_CLIENT_ID="client-123"
  export AZURE_CLIENT_SECRET="secret-abc"
  export AZURE_TENANT_ID="tenant-xyz"
  export MOCK_AZ_ACCOUNT_SHOW_EXIT=1 # not logged in
  export MOCK_AZ_LOGIN_EXIT=1        # login fails

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Azure service principal login failed"
  assert_contains "$output" "🔧 How to fix:"
}
