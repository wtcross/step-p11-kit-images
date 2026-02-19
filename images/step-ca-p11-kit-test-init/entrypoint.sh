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

P11_KIT_SOCKET_DIR="/run/p11-kit"
P11_KIT_SOCKET_PATH="${STEP_P11KIT_SOCKET_PATH}"
export P11_KIT_SERVER_ADDRESS="unix:path=${P11_KIT_SOCKET_PATH}"
STEPPATH="${STEPPATH:-/home/step/.step}"

STEP_OPENSSL_CONF_PATH="${STEP_OPENSSL_CONF_PATH}"
openssl_use_pkcs11_config "${STEP_OPENSSL_CONF_PATH}"

require_env ROOT_CA_PRIVATE_KEY_PKCS11_URI
require_env ROOT_CA_CERT_NAME
require_env STEP_CA_PRIVATE_KEY_PKCS11_URI
require_env STEP_CA_CERT_NAME
require_env STEP_CA_NAME
require_env STEP_CA_DNS_NAMES

require_dir "${STEPPATH}"
require_file "${STEP_HSM_PIN_FILE_PATH}"
require_dir "${P11_KIT_SOCKET_DIR}"
require_socket "${P11_KIT_SOCKET_PATH}"

openssl_require_pkcs11_provider_inputs

exec "$@"
