#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"

@test "pkcs11_format_key_id adds percent prefix" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/pkcs11.sh'; pkcs11_format_key_id 01"
  assert_status_eq 0
  assert_output_contains "%01"
}

@test "pkcs11_pin_source_uri normalizes file URI" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/pkcs11.sh'; pkcs11_pin_source_uri /run/secrets/hsm-pin"
  assert_status_eq 0
  assert_output_contains "file:///run/secrets/hsm-pin"
}

@test "pkcs11_build_private_key_uri includes token and object" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/pkcs11.sh'; pkcs11_build_private_key_uri RootCA 01 root /run/secrets/hsm-pin"
  assert_status_eq 0
  assert_output_contains "token=RootCA"
  assert_output_contains "object=root"
}

@test "pkcs11_parse_uri_attr returns path and query attrs" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/pkcs11.sh'; uri='pkcs11:token=RootCA;id=%01?module-path=/tmp/module.so&pin-source=file:///run/secrets/hsm-pin'; printf '%s\n' \"\$(pkcs11_parse_uri_attr \"\$uri\" token)\" \"\$(pkcs11_parse_uri_attr \"\$uri\" pin-source)\""
  assert_status_eq 0
  assert_output_contains "RootCA"
  assert_output_contains "file:///run/secrets/hsm-pin"
}

@test "pkcs11_parse_uri_attr fails when attr is missing" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/pkcs11.sh'; pkcs11_parse_uri_attr 'pkcs11:token=RootCA' module-path"
  assert_status_ne 0
}
