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

# init-softhsm.sh - Initialize SoftHSM tokens for testing

require_env HSM_PIN_FILE_PATH
require_env STEP_CA_ROOT_PKCS11_TOKEN_LABEL
require_env STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL

SOFTHSM_TOKEN_DIR="${SOFTHSM_TOKEN_DIR:-/var/lib/softhsm/tokens}"
SOFTHSM2_CONF="${SOFTHSM2_CONF:-/etc/softhsm/softhsm2.conf}"

export SOFTHSM2_CONF

log_info "init-softhsm" "Initializing SoftHSM environment..."

mkdir -p "${SOFTHSM_TOKEN_DIR}"
mkdir -p "$(dirname "${SOFTHSM2_CONF}")"

log_info "init-softhsm" "Creating SoftHSM configuration..."
cat > "${SOFTHSM2_CONF}" <<EOF_CONF
directories.tokendir = ${SOFTHSM_TOKEN_DIR}
objectstore.backend = file
log.level = INFO
slots.removable = false
slots.mechanisms = ALL
EOF_CONF

log_info "init-softhsm" "SoftHSM configuration written to: ${SOFTHSM2_CONF}"

if [[ -d "${SOFTHSM_TOKEN_DIR}" ]]; then
  log_info "init-softhsm" "Resetting SoftHSM token directory: ${SOFTHSM_TOKEN_DIR}"
  rm -rf "${SOFTHSM_TOKEN_DIR:?}"/*
fi

require_file "${HSM_PIN_FILE_PATH}"
PIN="$(pkcs11_read_pin "${HSM_PIN_FILE_PATH}")"

log_info "init-softhsm" "Initializing RootCA token..."
softhsm2-util --init-token --free --label "${STEP_CA_ROOT_PKCS11_TOKEN_LABEL}" --pin "${PIN}" --so-pin "${PIN}"

log_info "init-softhsm" "Initializing IntermediateCA token..."
softhsm2-util --init-token --free --label "${STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL}" --pin "${PIN}" --so-pin "${PIN}"

log_info "init-softhsm" "Verifying tokens..."
softhsm2-util --show-slots

log_info "init-softhsm" "SoftHSM initialization complete"
