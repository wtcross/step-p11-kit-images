#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"
load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/runtime.bash"

setup_file() {
  create_step_ca_deployment
  save_test_context "${BATS_TEST_FILENAME}"
}

setup() {
  load_test_context "${BATS_TEST_FILENAME}"
}

teardown_file() {
  local context_path
  context_path="$(test_context_file_path "${BATS_TEST_FILENAME}")"
  if [[ -f "${context_path}" ]]; then
    load_test_context "${BATS_TEST_FILENAME}"
    teardown_step_ca_deployment
    clear_test_context "${BATS_TEST_FILENAME}"
  fi
}

@test "step-ca container is running" {
  run podman inspect --format '{{.State.Running}}' "${STEP_CA_CONTAINER}"
  assert_status_eq 0
  assert_output_contains "true"
}

@test "step ca health returns ok" {
  local health_dns_name
  health_dns_name="$(step_ca_primary_dns_name)"

  run podman exec "${STEP_CA_CONTAINER}" \
    step ca health \
      --ca-url "https://${health_dns_name}:9000" \
      --root "/home/step/.step/certs/${ROOT_CA_CERT_NAME}"
  assert_status_eq 0
  assert_output_contains "ok"
}

@test "step-ca config contains expected DNS names" {
  run grep -F '"ca.example.local"' "${STEP_TEST_TMPDIR}/step/config/ca.json"
  assert_status_eq 0

  run grep -F '"ca.internal.local"' "${STEP_TEST_TMPDIR}/step/config/ca.json"
  assert_status_eq 0
}

@test "step-ca config contains derived KMS URI" {
  local expected_kms_uri
  expected_kms_uri="pkcs11:token=${STEP_CA_TOKEN_LABEL}?module-path=${STEP_P11KIT_CLIENT_MODULE_PATH}&pin-source=file:///run/secrets/hsm-pin"

  run jq -r '.kms.uri' "${STEP_TEST_TMPDIR}/step/config/ca.json"
  assert_status_eq 0
  assert_output_contains "${expected_kms_uri}"
}
