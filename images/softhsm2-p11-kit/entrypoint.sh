#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/usr/local/share/step-p11-kit/validation.sh
source /usr/local/share/step-p11-kit/validation.sh

export SOFTHSM_LIB_PATH="${SOFTHSM_LIB_PATH:-/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so}"
export STEP_HSM_PIN_FILE_PATH="${STEP_HSM_PIN_FILE_PATH:-/run/secrets/hsm-pin}"
export STEP_P11KIT_SOCKET_PATH="${STEP_P11KIT_SOCKET_PATH:-${P11_KIT_SOCKET:-/run/p11-kit/pkcs11-socket}}"
export P11_KIT_SOCKET="${STEP_P11KIT_SOCKET_PATH}"
export HSM_PIN_FILE_PATH="${STEP_HSM_PIN_FILE_PATH}"

require_env STEP_CA_ROOT_PKCS11_TOKEN_LABEL
require_env STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL

/usr/local/bin/init-softhsm.sh
exec /usr/local/bin/start-p11-kit-server.sh
