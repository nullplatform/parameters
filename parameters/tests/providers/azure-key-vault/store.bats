#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/providers/azure-key-vault/store
# AKV transforms / and = to - in the secret name (canonical form has slashes).
# Store now uses the Key Vault REST API via curl (no az CLI).
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_ROOT="$PARAMETERS_DIR"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/providers/azure-key-vault/store"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'EOF'
#!/bin/bash
echo "curl $*" >> "$CURL_LOG"
out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done
[ -n "$out" ] && printf '%s' "${MOCK_CURL_BODY:-}" > "$out"
printf '%s' "${MOCK_CURL_CODE:-200}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  export AZ_VAULT_NAME="my-vault"
  export AZ_VAULT_URL="https://my-vault.vault.azure.net"
  export AZ_ACCESS_TOKEN="tok-abc"
  export AZ_SECRET_PREFIX="parameters-"
  export PARAMETER_VALUE="my-secret"
  export MOCK_CURL_CODE=200
  export MOCK_CURL_BODY='{"id":"https://my-vault.vault.azure.net/secrets/some-name/abc123"}'

  export CONTEXT='{
    "parameter_id": 42,
    "value": "my-secret",
    "entities": {
      "organization": "1255165411",
      "organization_slug": "acme",
      "account": "95118862",
      "account_slug": "prod",
      "namespace": "37094320",
      "namespace_slug": "billing",
      "application": "321402625",
      "application_slug": "api"
    },
    "dimensions": {}
  }'

  export DEPS="source $PARAMETERS_DIR/utils/log"
}

@test "azure-key-vault store: external_id is canonical slash form + version suffix" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  external_id=$(echo "$output" | jq -r '.external_id')
  # Mock id ends in /abc123 — that's the version
  expected="organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/42#abc123"
  assert_equal "$external_id" "$expected"
}

@test "azure-key-vault store: secret_name uses dashes (AKV-safe)" {
  run bash -c "$DEPS; source $SCRIPT"

  assert_equal "$status" "0"
  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  assert_contains "$secret_name" "parameters-organization-acme-1255165411-account-prod-95118862"
  assert_contains "$secret_name" "-42"
  [[ "$secret_name" != *"/"* ]]
  [[ "$secret_name" != *"="* ]]
}

@test "azure-key-vault store: PUTs to the AKV-safe secret URL, value not on argv" {
  run bash -c "$DEPS; source $SCRIPT"

  captured=$(cat "$CURL_LOG")
  assert_contains "$captured" "-X PUT"
  assert_contains "$captured" "https://my-vault.vault.azure.net/secrets/parameters-organization-acme-1255165411"
  assert_contains "$captured" "api-version=7.4"
  # The value travels in the body via stdin — it must NOT appear on argv.
  [[ "$captured" != *"my-secret"* ]]
}

@test "azure-key-vault store: dimensions sorted alphabetically in external_id" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.dimensions = {environment: "prod", country: "arg"}')

  run bash -c "$DEPS; source $SCRIPT"

  external_id=$(echo "$output" | jq -r '.external_id')
  assert_contains "$external_id" "country=arg/environment=prod/42"

  secret_name=$(echo "$output" | jq -r '.metadata.secret_name')
  assert_contains "$secret_name" "country-arg-environment-prod-42"
}

@test "azure-key-vault store: fails with troubleshooting and underlying error on HTTP error" {
  export MOCK_CURL_CODE=403
  export MOCK_CURL_BODY='{"error":{"code":"Forbidden","message":"Caller is not authorized to perform action on resource."}}'

  run bash -c "$DEPS; source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Failed to store secret in Azure Key Vault"
  assert_contains "$output" "Underlying error: Caller is not authorized"
}
