#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/usr/local/share/step-p11-kit/validation.sh
source /usr/local/share/step-p11-kit/validation.sh
# shellcheck source=/usr/local/share/step-p11-kit/logging.sh
source /usr/local/share/step-p11-kit/logging.sh

# start-p11-kit-server.sh - Start p11-kit server exposing SoftHSM

require_env SOFTHSM_LIB_PATH
require_env STEP_CA_ROOT_PKCS11_TOKEN_LABEL
require_env STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL

P11_KIT_SOCKET="${STEP_P11KIT_SOCKET_PATH:-${P11_KIT_SOCKET:-/run/p11-kit/pkcs11-socket}}"
SOCKET_DIR="$(dirname "${P11_KIT_SOCKET}")"
SOCKET_NAME="$(basename "${P11_KIT_SOCKET}")"

export XDG_RUNTIME_DIR="$(dirname "${SOCKET_DIR}")"

mkdir -p "${SOCKET_DIR}"
rm -f "${P11_KIT_SOCKET}"

log_info "p11-kit-server" "Starting p11-kit server..."
log_info "p11-kit-server" "SoftHSM library: ${SOFTHSM_LIB_PATH}"
log_info "p11-kit-server" "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR}"
log_info "p11-kit-server" "Socket: ${P11_KIT_SOCKET}"

cd "${SOCKET_DIR}"

p11-kit server \
  --foreground \
  --provider "${SOFTHSM_LIB_PATH}" \
  --name "${SOCKET_NAME}" \
  "pkcs11:token=${STEP_CA_ROOT_PKCS11_TOKEN_LABEL}" \
  "pkcs11:token=${STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL}" &

P11_SERVER_PID=$!

cleanup() {
  if kill -0 "${P11_SERVER_PID}" 2>/dev/null; then
    kill "${P11_SERVER_PID}"
  fi
}
trap cleanup EXIT

max_wait=100
waited=0
while [[ ! -S "${P11_KIT_SOCKET}" && ${waited} -lt ${max_wait} ]]; do
  sleep 0.1
  waited=$((waited + 1))
done

if [[ -S "${P11_KIT_SOCKET}" ]]; then
  log_info "p11-kit-server" "Socket ready: $(ls -la "${P11_KIT_SOCKET}")"
else
  log_warn "p11-kit-server" "Socket not created after ${max_wait} iterations"
fi

wait ${P11_SERVER_PID}
