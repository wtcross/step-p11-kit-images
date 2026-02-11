#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"
load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/runtime.bash"

setup_file() {
  ensure_test_images
  initialize_test_context
  start_softhsm2_p11_kit
  run_step_ca_p11_kit_test_init
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

@test "root and intermediate certs are generated" {
  assert_file_nonempty "${STEP_TEST_TMPDIR}/step/certs/${STEP_CA_ROOT_CERT_NAME}"
  assert_file_nonempty "${STEP_TEST_TMPDIR}/step/certs/${STEP_CA_INTERMEDIATE_CERT_NAME}"
}

@test "intermediate cert CN uses first STEP_CA_DNS_NAMES value" {
  run openssl x509 -in "${STEP_TEST_TMPDIR}/step/certs/${STEP_CA_INTERMEDIATE_CERT_NAME}" -noout -subject
  assert_status_eq 0
  [[ "${output}" =~ CN[[:space:]]*=[[:space:]]*ca\.example\.local ]]
}

@test "intermediate cert SAN includes all STEP_CA_DNS_NAMES entries" {
  run openssl x509 -in "${STEP_TEST_TMPDIR}/step/certs/${STEP_CA_INTERMEDIATE_CERT_NAME}" -noout -ext subjectAltName
  assert_status_eq 0
  assert_output_contains "DNS:ca.example.local"
  assert_output_contains "DNS:ca.internal.local"
}
