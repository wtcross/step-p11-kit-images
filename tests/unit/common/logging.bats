#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"

@test "log_info includes component and INFO level" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/logging.sh'; log_info test-component 'hello'"
  assert_status_eq 0
  assert_output_contains "[test-component] [INFO] hello"
}

@test "log_warn includes WARN level" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/logging.sh'; log_warn test-component 'watch out'"
  assert_status_eq 0
  assert_output_contains "[test-component] [WARN] watch out"
}

@test "log_error includes ERROR level" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/logging.sh'; log_error test-component 'boom'"
  assert_status_eq 0
  assert_output_contains "[test-component] [ERROR] boom"
}

@test "log_info fails when required arguments are missing" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/logging.sh'; log_info"
  assert_status_ne 0
}
