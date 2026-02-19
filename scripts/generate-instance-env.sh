#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/common"
if [[ ! -d "${COMMON_DIR}" ]]; then
  COMMON_DIR="/usr/local/share/step-p11-kit"
fi

# shellcheck source=common/validation.sh
source "${COMMON_DIR}/validation.sh"
# shellcheck source=common/logging.sh
source "${COMMON_DIR}/logging.sh"

usage() {
  cat <<USAGE
Usage: generate-instance-env.sh [OPTIONS]

Generate per-instance env files for p11-kit-server and step-ca.

Required:
  --instance NAME                   Instance name (e.g., prod)

Optional (step-ca):
  --ca-name NAME                    STEP_CA_NAME value
  --dns LIST                        STEP_CA_DNS_NAMES value (comma-separated)
  --external-port PORT              Host PublishPort value for container port 9000 (default 9000)
  --admin-subject NAME              STEP_CA_ADMIN_SUBJECT (default step)
  --provisioner NAME                STEP_CA_ADMIN_PROVISIONER_NAME (default admin)
  --steppath PATH                   STEPPATH (default /home/step/.step)
  --root-cert PATH                  ROOT_CA_CERT_FILE (default /run/secrets/root.crt)
  --cert PATH          STEP_CA_CERT_FILE (default /run/secrets/ca.crt)
  --admin-password PATH             STEP_ADMIN_PASSWORD_FILE (default /run/secrets/admin-password)
  --private-key-pkcs11-uri URI      STEP_CA_PRIVATE_KEY_PKCS11_URI value
  Note: this script writes file paths under /run/secrets/*, but secret files
  are provided at runtime by quadlet Secret= mounts (not created here).

Optional (p11-kit server):
  --hsm-module PATH                 STEP_HSM_MODULE_PATH (default /usr/lib/x86_64-linux-gnu/pkcs11/opensc-pkcs11.so)
  --hsm-uri URI                     STEP_HSM_PKCS11_URI value (required for working p11-kit server config)

Flags:
  --force                           Overwrite existing files
  --help                            Show this help message
USAGE
}

INSTANCE=""
CA_NAME=""
DNS_NAMES=""
INTERNAL_ADDRESS=":9000"
EXTERNAL_PORT="9000"
ADMIN_SUBJECT="step"
PROVISIONER_NAME="admin"
STEPPATH="/home/step/.step"
ROOT_CA_CERT="/run/secrets/root.crt"
STEP_CA_CERT="/run/secrets/ca.crt"
ADMIN_PASSWORD="/run/secrets/admin-password"
PRIVATE_KEY_PKCS11_URI=""
HSM_MODULE="/usr/lib/x86_64-linux-gnu/pkcs11/opensc-pkcs11.so"
HSM_URI=""
FORCE="false"

function validate_port_or_die {
  local port="${1:?port is required}"
  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    die "port must be numeric: ${port}"
  fi

  if (( port < 1 || port > 65535 )); then
    die "port must be between 1 and 65535: ${port}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance) INSTANCE="$2"; shift 2 ;;
    --ca-name) CA_NAME="$2"; shift 2 ;;
    --dns) DNS_NAMES="$2"; shift 2 ;;
    --external-port) EXTERNAL_PORT="$2"; shift 2 ;;
    --admin-subject) ADMIN_SUBJECT="$2"; shift 2 ;;
    --provisioner) PROVISIONER_NAME="$2"; shift 2 ;;
    --steppath) STEPPATH="$2"; shift 2 ;;
    --root-cert) ROOT_CA_CERT="$2"; shift 2 ;;
    --cert) STEP_CA_CERT="$2"; shift 2 ;;
    --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
    --private-key-pkcs11-uri) PRIVATE_KEY_PKCS11_URI="$2"; shift 2 ;;
    --hsm-module) HSM_MODULE="$2"; shift 2 ;;
    --hsm-uri) HSM_URI="$2"; shift 2 ;;
    --force) FORCE="true"; shift 1 ;;
    --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
 done

[[ -n "${INSTANCE}" ]] || die "--instance is required"
validate_port_or_die "${EXTERNAL_PORT}"

P11_DIR="${HOME}/.config/p11-kit-server"
CA_DIR="${HOME}/.config/step-ca"
P11_FILE="${P11_DIR}/${INSTANCE}.env"
CA_FILE="${CA_DIR}/${INSTANCE}.env"
CONTAINER_DROPIN_DIR="${HOME}/.config/containers/systemd/step-ca-p11-kit@${INSTANCE}.container.d"
CONTAINER_DROPIN_FILE="${CONTAINER_DROPIN_DIR}/10-publish-port.conf"

mkdir -p "${P11_DIR}" "${CA_DIR}" "${CONTAINER_DROPIN_DIR}"

if [[ -f "${P11_FILE}" && "${FORCE}" != "true" ]]; then
  die "Refusing to overwrite ${P11_FILE} (use --force)"
fi

if [[ -f "${CA_FILE}" && "${FORCE}" != "true" ]]; then
  die "Refusing to overwrite ${CA_FILE} (use --force)"
fi

if [[ -f "${CONTAINER_DROPIN_FILE}" && "${FORCE}" != "true" ]]; then
  die "Refusing to overwrite ${CONTAINER_DROPIN_FILE} (use --force)"
fi

cat > "${P11_FILE}" <<EOF_ENV
STEP_HSM_MODULE_PATH=${HSM_MODULE}
STEP_HSM_PKCS11_URI=${HSM_URI}
EOF_ENV

cat > "${CA_FILE}" <<EOF_ENV
STEP_CA_NAME=${CA_NAME}
STEP_CA_DNS_NAMES=${DNS_NAMES}
STEP_CA_PRIVATE_KEY_PKCS11_URI=${PRIVATE_KEY_PKCS11_URI}
STEP_ADMIN_PASSWORD_FILE=${ADMIN_PASSWORD}
STEP_CA_ADDRESS=${INTERNAL_ADDRESS}
STEP_CA_CERT_FILE=${STEP_CA_CERT}
ROOT_CA_CERT_FILE=${ROOT_CA_CERT}
STEP_CA_ADMIN_SUBJECT=${ADMIN_SUBJECT}
STEP_CA_ADMIN_PROVISIONER_NAME=${PROVISIONER_NAME}
STEPPATH=${STEPPATH}
STEP_P11KIT_SOCKET_PATH=/run/p11-kit/${INSTANCE}.sock
EOF_ENV

cat > "${CONTAINER_DROPIN_FILE}" <<EOF_ENV
[Container]
PublishPort=${EXTERNAL_PORT}:9000
EOF_ENV

log_info "generate-instance-env" "Wrote: ${P11_FILE}"
log_info "generate-instance-env" "Wrote: ${CA_FILE}"
log_info "generate-instance-env" "Wrote: ${CONTAINER_DROPIN_FILE}"
