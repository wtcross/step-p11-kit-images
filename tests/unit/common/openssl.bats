#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../helpers/assertions.bash"

@test "openssl_use_pkcs11_config sets OPENSSL_CONF" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/openssl.sh'; openssl_use_pkcs11_config /tmp/custom.cnf; echo \"\$OPENSSL_CONF\""
  assert_status_eq 0
  assert_output_contains "/tmp/custom.cnf"
}

@test "openssl_require_pkcs11_provider_inputs fails when config is missing" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../../../scripts/common/openssl.sh'; openssl_require_pkcs11_provider_inputs /tmp/missing.cnf /tmp/missing.so"
  assert_status_ne 0
  assert_output_contains "OpenSSL provider config not found"
}

@test "openssl_require_pkcs11_provider_inputs succeeds with existing files" {
  run bash -c "tmpdir=\"\$(mktemp -d)\"; conf=\"\${tmpdir}/openssl.cnf\"; mod=\"\${tmpdir}/module.so\"; touch \"\$conf\" \"\$mod\"; source '${BATS_TEST_DIRNAME}/../../../scripts/common/openssl.sh'; openssl_require_pkcs11_provider_inputs \"\$conf\" \"\$mod\"; echo ok; rm -rf \"\$tmpdir\""
  assert_status_eq 0
  assert_output_contains "ok"
}
