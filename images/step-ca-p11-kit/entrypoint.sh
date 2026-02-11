#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/usr/local/share/step-p11-kit/validation.sh
source /usr/local/share/step-p11-kit/validation.sh
# shellcheck source=/usr/local/share/step-p11-kit/pkcs11.sh
source /usr/local/share/step-p11-kit/pkcs11.sh
# shellcheck source=/usr/local/share/step-p11-kit/logging.sh
source /usr/local/share/step-p11-kit/logging.sh

P11_KIT_SOCKET_DIR="/run/p11-kit"
P11_KIT_SOCKET_PATH="${STEP_P11KIT_SOCKET_PATH}"
export P11_KIT_SERVER_ADDRESS="unix:path=${P11_KIT_SOCKET_PATH}"

export STEPPATH="${STEPPATH:-/home/step/.step}"
CA_CONFIG_FILE="${STEPPATH}/config/ca.json"
DEFAULTS_CONFIG_FILE="${STEPPATH}/config/defaults.json"
HSM_PIN_FILE_PATH="${STEP_HSM_PIN_FILE_PATH}"

STEP_CA_PORT="${STEP_CA_PORT:-9000}"
STEP_CA_ADDRESS="${STEP_CA_ADDRESS:-:${STEP_CA_PORT}}"

function infer_step_ca_port {
  local address="${1:?address is required}"
  if [[ "${address}" =~ :([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "${STEP_CA_PORT}"
  fi
}

function trim_whitespace {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "${value}"
}

function parse_dns_names_or_die {
  local raw_dns_names="${1:?raw_dns_names is required}"
  local -a raw_dns_array
  local dns_name=""

  IFS=',' read -r -a raw_dns_array <<< "${raw_dns_names}"

  DNS_ARRAY=()
  for raw_dns in "${raw_dns_array[@]}"; do
    dns_name="$(trim_whitespace "${raw_dns}")"
    if [[ -n "${dns_name}" ]]; then
      DNS_ARRAY+=("${dns_name}")
    fi
  done

  if [[ ${#DNS_ARRAY[@]} -eq 0 ]]; then
    die "STEP_CA_DNS_NAMES must include at least one DNS name"
  fi
}

require_env STEP_CA_NAME
require_env STEP_CA_DNS_NAMES
require_env STEP_CA_PRIVATE_KEY_PKCS11_URI
require_env STEP_CA_KMS_PKCS11_URI
require_env STEP_ADMIN_PASSWORD_FILE
require_env STEP_ROOT_CERT_FILE
require_env STEP_INTERMEDIATE_CERT_FILE

STEP_CA_ADMIN_SUBJECT="${STEP_CA_ADMIN_SUBJECT:-step}"
STEP_CA_ADMIN_PROVISIONER_NAME="${STEP_CA_ADMIN_PROVISIONER_NAME:-admin}"

require_dir "${STEPPATH}"
require_dir "${P11_KIT_SOCKET_DIR}"
require_file "${HSM_PIN_FILE_PATH}"
require_socket "${P11_KIT_SOCKET_PATH}"
require_file "${STEP_ADMIN_PASSWORD_FILE}"
require_file "${STEP_ROOT_CERT_FILE}"
require_file "${STEP_INTERMEDIATE_CERT_FILE}"

if [[ ! -f "${CA_CONFIG_FILE}" ]]; then
  log_info "step-ca-entrypoint" "Initializing CA configuration..."

  parse_dns_names_or_die "${STEP_CA_DNS_NAMES}"
  DNS_JSON="$(printf '%s\n' "${DNS_ARRAY[@]}" | jq -R . | jq -s .)"

  mkdir -p "${STEPPATH}/certs" "${STEPPATH}/config" "${STEPPATH}/db" "${STEPPATH}/secrets" "${STEPPATH}/templates"

  cat > "${CA_CONFIG_FILE}" <<EOF_JSON
{
  "root": "${STEP_ROOT_CERT_FILE}",
  "crt": "${STEP_INTERMEDIATE_CERT_FILE}",
  "key": "${STEP_CA_PRIVATE_KEY_PKCS11_URI}",
  "kms": {
    "type": "pkcs11",
    "uri": "${STEP_CA_KMS_PKCS11_URI}"
  },
  "address": "${STEP_CA_ADDRESS}",
  "dnsNames": ${DNS_JSON},
  "logger": {
    "format": "text"
  },
  "db": {
    "type": "badgerv2",
    "dataSource": "${STEPPATH}/db"
  },
  "authority": {
    "enableAdmin": true,
    "provisioners": []
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
    ],
    "minVersion": 1.2,
    "maxVersion": 1.3,
    "renegotiation": false
  }
}
EOF_JSON

  FINGERPRINT="$(step certificate fingerprint "${STEP_ROOT_CERT_FILE}")"
  EFFECTIVE_PORT="$(infer_step_ca_port "${STEP_CA_ADDRESS}")"

  cat > "${DEFAULTS_CONFIG_FILE}" <<EOF_JSON
{
  "ca-url": "https://${DNS_ARRAY[0]}:${EFFECTIVE_PORT}",
  "ca-config": "${STEPPATH}/config/ca.json",
  "fingerprint": "${FINGERPRINT}",
  "root": "${STEP_ROOT_CERT_FILE}"
}
EOF_JSON

  step ca provisioner add "${STEP_CA_ADMIN_PROVISIONER_NAME}" \
    --create \
    --type JWK \
    --password-file "${STEP_ADMIN_PASSWORD_FILE}" \
    --admin-subject "${STEP_CA_ADMIN_SUBJECT}"

  log_info "step-ca-entrypoint" "CA configuration initialized successfully"
  log_info "step-ca-entrypoint" "Admin subject: ${STEP_CA_ADMIN_SUBJECT}"
  log_info "step-ca-entrypoint" "Admin provisioner: ${STEP_CA_ADMIN_PROVISIONER_NAME}"
fi

exec "$@"
