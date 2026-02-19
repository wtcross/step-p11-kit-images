#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"

setup() {
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

@test "generate-instance-env creates per-instance env files and quadlet artifacts" {
  local instance="prod"
  local script_path="${BATS_TEST_DIRNAME}/../../../scripts/generate-instance-env.sh"
  local p11_file="${TEST_HOME}/.config/p11-kit-server/${instance}.env"
  local ca_file="${TEST_HOME}/.config/step-ca/${instance}.env"
  local container_instance_source="${TEST_HOME}/.config/containers/systemd/step-ca-p11-kit@${instance}.container"
  local dropin_file="${TEST_HOME}/.config/containers/systemd/step-ca-p11-kit@${instance}.container.d/10-publish-port.conf"

  run env HOME="${TEST_HOME}" "${script_path}" \
    --instance "${instance}" \
    --external-port 9443 \
    --hsm-uri "pkcs11:token=RootCA"
  assert_status_eq 0

  assert_file_exists "${p11_file}"
  assert_file_exists "${ca_file}"
  assert_file_exists "${dropin_file}"

  run test -L "${container_instance_source}"
  assert_status_eq 0

  run readlink "${container_instance_source}"
  assert_status_eq 0
  assert_output_contains "step-ca-p11-kit@.container"

  run grep -Fx "PublishPort=9443:9000" "${dropin_file}"
  assert_status_eq 0
}

@test "generate-instance-env sets expected drop-in permissions and ownership" {
  local instance="prod"
  local expected_owner_group
  local script_path="${BATS_TEST_DIRNAME}/../../../scripts/generate-instance-env.sh"
  local dropin_dir="${TEST_HOME}/.config/containers/systemd/step-ca-p11-kit@${instance}.container.d"
  local dropin_file="${dropin_dir}/10-publish-port.conf"

  expected_owner_group="$(id -u):$(id -g)"

  run env HOME="${TEST_HOME}" "${script_path}" \
    --instance "${instance}" \
    --hsm-uri "pkcs11:token=RootCA"
  assert_status_eq 0

  run stat -c '%a' "${dropin_dir}"
  assert_status_eq 0
  assert_output_contains "755"

  run stat -c '%a' "${dropin_file}"
  assert_status_eq 0
  assert_output_contains "644"

  run stat -c '%u:%g' "${dropin_dir}"
  assert_status_eq 0
  assert_output_contains "${expected_owner_group}"

  run stat -c '%u:%g' "${dropin_file}"
  assert_status_eq 0
  assert_output_contains "${expected_owner_group}"
}
