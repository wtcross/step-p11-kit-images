#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/usr/local/share/step-p11-kit/validation.sh
source /usr/local/share/step-p11-kit/validation.sh
# shellcheck source=/usr/local/share/step-p11-kit/logging.sh
source /usr/local/share/step-p11-kit/logging.sh

export SOFTHSM_LIB_PATH="${SOFTHSM_LIB_PATH:-/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so}"
export STEP_HSM_PIN_FILE_PATH="${STEP_HSM_PIN_FILE_PATH:-/run/secrets/hsm-pin}"
export HSM_PIN_FILE_PATH="${STEP_HSM_PIN_FILE_PATH}"
export STEP_SYSTEMD_INSTANCE="${STEP_SYSTEMD_INSTANCE:-test}"

require_env STEP_CA_ROOT_PKCS11_TOKEN_LABEL
require_env STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL
require_file "${STEP_HSM_PIN_FILE_PATH}"
require_command dbus-run-session

log_info "entrypoint" "Initializing SoftHSM tokens"
/usr/local/bin/init-softhsm.sh

log_info "entrypoint" "Launching systemd test target for instance '${STEP_SYSTEMD_INSTANCE}'"
exec dbus-run-session -- /usr/local/bin/start-step-ca-p11-kit-target.sh "$@"
