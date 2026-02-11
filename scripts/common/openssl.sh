#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${STEP_OPENSSL_CONF_PATH:=/etc/ssl/openssl-pkcs11.cnf}"
: "${STEP_P11KIT_CLIENT_MODULE_PATH:=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so}"

function openssl_use_pkcs11_config {
  local config_path="${1:-${STEP_OPENSSL_CONF_PATH}}"
  export OPENSSL_CONF="${config_path}"
}

function openssl_require_pkcs11_provider_inputs {
  local config_path="${1:-${STEP_OPENSSL_CONF_PATH}}"
  local module_path="${2:-${STEP_P11KIT_CLIENT_MODULE_PATH}}"

  if [[ ! -f "${config_path}" ]]; then
    echo "Error: OpenSSL provider config not found at ${config_path}" >&2
    exit 1
  fi

  if [[ ! -f "${module_path}" ]]; then
    echo "Error: PKCS#11 client module not found at ${module_path}" >&2
    exit 1
  fi
}

function openssl_pkcs11_req_x509 {
  openssl req -new -x509 -provider default -provider pkcs11 "$@"
}

function openssl_pkcs11_req_csr {
  openssl req -new -provider default -provider pkcs11 "$@"
}

function openssl_pkcs11_x509_sign {
  openssl x509 -req -provider default -provider pkcs11 "$@"
}
