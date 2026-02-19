#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/usr/local/share/step-p11-kit/validation.sh
source /usr/local/share/step-p11-kit/validation.sh
# shellcheck source=/usr/local/share/step-p11-kit/pkcs11.sh
source /usr/local/share/step-p11-kit/pkcs11.sh
# shellcheck source=/usr/local/share/step-p11-kit/openssl.sh
source /usr/local/share/step-p11-kit/openssl.sh
# shellcheck source=/usr/local/share/step-p11-kit/logging.sh
source /usr/local/share/step-p11-kit/logging.sh

STEPPATH="${STEPPATH:-/home/step/.step}"

require_env ROOT_CA_PRIVATE_KEY_PKCS11_URI
require_env ROOT_CA_CERT_NAME
require_env STEP_CA_PRIVATE_KEY_PKCS11_URI
require_env STEP_CA_CERT_NAME
require_env STEP_CA_NAME
require_env STEP_CA_DNS_NAMES
require_file "${STEP_HSM_PIN_FILE_PATH}"

function trim_whitespace {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "${value}"
}

function uri_attr_or_die {
  local uri="${1:?uri is required}"
  local attr="${2:?attr is required}"
  local value=""

  if ! value="$(pkcs11_parse_uri_attr "${uri}" "${attr}")"; then
    die "PKCS#11 URI is missing required attribute '${attr}': ${uri}"
  fi

  echo "${value}"
}

function pkcs11_cmd {
  local pin
  pin="$(pkcs11_read_pin "${STEP_HSM_PIN_FILE_PATH}")"
  pkcs11-tool --module "${STEP_P11KIT_CLIENT_MODULE_PATH}" --login --pin "${pin}" "$@"
}

function priv_key_exists {
  local token_label="${1:?token_label is required}"
  local key_id="${2:?key_id is required}"

  set +o errexit

  pkcs11_cmd \
    --token-label "${token_label}" \
    --type privkey \
    --id "${key_id}" \
    --sign \
    --mechanism SHA256-RSA-PKCS \
    --input-file <(echo "test") \
    --output-file /dev/null \
    &>/dev/null

  local return_code=$?

  set -o errexit

  if [[ ${return_code} -eq 0 ]]; then
    echo "true"
  else
    echo "false"
  fi
}

function create_keypair {
  local token_label="${1:?token_label is required}"
  local key_id="${2:?key_id is required}"
  local key_label="${3:?key_label is required}"

  pkcs11_cmd \
    --token-label "${token_label}" \
    --keypairgen \
    --key-type "RSA:2048" \
    --id "${key_id}" \
    --label "${key_label}" \
    &>/dev/null

  log_info "create-ca-hierarchy" "Created keypair: key-type='RSA:2048', id='${key_id}', label='${key_label}'"
}

ROOT_TOKEN_LABEL="$(uri_attr_or_die "${ROOT_CA_PRIVATE_KEY_PKCS11_URI}" "token")"
ROOT_KEY_ID_URI="$(uri_attr_or_die "${ROOT_CA_PRIVATE_KEY_PKCS11_URI}" "id")"
ROOT_KEY_LABEL="$(uri_attr_or_die "${ROOT_CA_PRIVATE_KEY_PKCS11_URI}" "object")"
ROOT_KEY_ID="$(pkcs11_key_id_for_pkcs11_tool "${ROOT_KEY_ID_URI}")"

STEP_CA_TOKEN_LABEL="$(uri_attr_or_die "${STEP_CA_PRIVATE_KEY_PKCS11_URI}" "token")"
STEP_CA_KEY_ID_URI="$(uri_attr_or_die "${STEP_CA_PRIVATE_KEY_PKCS11_URI}" "id")"
STEP_CA_KEY_LABEL="$(uri_attr_or_die "${STEP_CA_PRIVATE_KEY_PKCS11_URI}" "object")"
STEP_CA_KEY_ID="$(pkcs11_key_id_for_pkcs11_tool "${STEP_CA_KEY_ID_URI}")"

IFS=',' read -r -a RAW_DNS_NAMES <<< "${STEP_CA_DNS_NAMES}"
CA_DNS_NAMES=()
for raw_dns in "${RAW_DNS_NAMES[@]}"; do
  dns_name="$(trim_whitespace "${raw_dns}")"
  if [[ -n "${dns_name}" ]]; then
    CA_DNS_NAMES+=("${dns_name}")
  fi
done

if [[ ${#CA_DNS_NAMES[@]} -eq 0 ]]; then
  die "STEP_CA_DNS_NAMES must include at least one DNS name"
fi

CA_CN="${CA_DNS_NAMES[0]}"
CA_SAN="DNS:${CA_DNS_NAMES[0]}"
for dns_name in "${CA_DNS_NAMES[@]:1}"; do
  CA_SAN="${CA_SAN},DNS:${dns_name}"
done

log_info "create-ca-hierarchy" "Preparing issuing CA '${STEP_CA_NAME}' with CN='${CA_CN}' and SAN='${CA_SAN}'"

if [[ "$(priv_key_exists "${ROOT_TOKEN_LABEL}" "${ROOT_KEY_ID}")" == "false" ]]; then
  create_keypair "${ROOT_TOKEN_LABEL}" "${ROOT_KEY_ID}" "${ROOT_KEY_LABEL}"
fi

if [[ "$(priv_key_exists "${STEP_CA_TOKEN_LABEL}" "${STEP_CA_KEY_ID}")" == "false" ]]; then
  create_keypair "${STEP_CA_TOKEN_LABEL}" "${STEP_CA_KEY_ID}" "${STEP_CA_KEY_LABEL}"
fi

mkdir -p "${STEPPATH}/certs"

ROOT_KEY_URI="${ROOT_CA_PRIVATE_KEY_PKCS11_URI}"
STEP_CA_KEY_URI="${STEP_CA_PRIVATE_KEY_PKCS11_URI}"

ROOT_CA_CERT_PATH="${STEPPATH}/certs/${ROOT_CA_CERT_NAME}"
STEP_CA_CERT_PATH="${STEPPATH}/certs/${STEP_CA_CERT_NAME}"

if [[ ! -f "${ROOT_CA_CERT_PATH}" ]]; then
  log_info "create-ca-hierarchy" "Creating root CA certificate: ${ROOT_CA_CERT_PATH}"

  openssl_pkcs11_req_x509 \
    -key "${ROOT_KEY_URI}" \
    -subj "/CN=Test Root CA" \
    -sha512 \
    -days 3650 \
    -out "${ROOT_CA_CERT_PATH}" \
    -addext "basicConstraints=critical,CA:true,pathlen:2" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" \
    -addext "authorityKeyIdentifier=keyid:always"
fi

if [[ ! -f "${STEP_CA_CERT_PATH}" ]]; then
  log_info "create-ca-hierarchy" "Creating issuing CA certificate: ${STEP_CA_CERT_PATH}"

  TMPDIR="$(mktemp -d)"
  TEMP_STEP_CA_CSR="${TMPDIR}/issuing.csr"
  TEMP_STEP_CA_CERT="${TMPDIR}/ca.crt"

  openssl_pkcs11_req_csr \
    -key "${STEP_CA_KEY_URI}" \
    -subj "/CN=${CA_CN}" \
    -sha512 \
    -out "${TEMP_STEP_CA_CSR}"

  openssl_pkcs11_x509_sign \
    -in "${TEMP_STEP_CA_CSR}" \
    -CA "${ROOT_CA_CERT_PATH}" \
    -CAkey "${ROOT_KEY_URI}" \
    -CAcreateserial \
    -sha512 \
    -days 1825 \
    -out "${TEMP_STEP_CA_CERT}" \
    -extfile <(cat <<EOF_EXT
basicConstraints = critical,CA:true,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = ${CA_SAN}
EOF_EXT
)

  cp "${TEMP_STEP_CA_CERT}" "${STEP_CA_CERT_PATH}"

  rm -rf "${TMPDIR}"
fi
