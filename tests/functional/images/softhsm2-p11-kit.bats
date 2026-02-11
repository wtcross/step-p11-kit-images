#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"
load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/runtime.bash"

setup_file() {
  ensure_test_images
  initialize_test_context
  start_softhsm2_p11_kit
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

@test "softhsm2 image exists" {
  run podman image exists "${SOFTHSM_TEST_IMAGE}"
  assert_status_eq 0
}

@test "pkcs11 socket is created" {
  run test -S "${STEP_TEST_TMPDIR}/p11-kit/pkcs11-socket"
  assert_status_eq 0
}

@test "softhsm2 container is running" {
  run podman inspect --format '{{.State.Running}}' "${STEP_SOFTHSM_CONTAINER}"
  assert_status_eq 0
  assert_output_contains "true"
}
