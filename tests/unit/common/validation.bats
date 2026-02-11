#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"

@test "require_env fails when var name is missing" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/validation.sh'; require_env"
  assert_status_ne 0
}

@test "require_env fails when env var is unset" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/validation.sh'; require_env MISSING_VAR"
  assert_status_ne 0
  assert_output_contains "Error: MISSING_VAR is required"
}

@test "require_env succeeds when env var is set" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/validation.sh'; TEST_VAR=value; require_env TEST_VAR; echo ok"
  assert_status_eq 0
  assert_output_contains "ok"
}

@test "require_file fails when file is missing" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/validation.sh'; require_file /tmp/does-not-exist-file"
  assert_status_ne 0
  assert_output_contains "Error: File not found"
}

@test "require_dir and require_command succeed for known inputs" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/validation.sh'; require_dir /tmp; require_command bash; echo ok"
  assert_status_eq 0
  assert_output_contains "ok"
}
