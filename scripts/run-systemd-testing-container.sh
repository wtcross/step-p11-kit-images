#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=common/validation.sh
source "${SCRIPT_DIR}/common/validation.sh"
# shellcheck source=common/logging.sh
source "${SCRIPT_DIR}/common/logging.sh"

SYSTEMD_TESTING_IMAGE="${SYSTEMD_TESTING_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit-systemd-testing:latest}"
IMAGE_TAR_DIR="${STEP_SYSTEMD_TEST_IMAGE_TAR_DIR:-${REPO_ROOT}/.tmp/image-tars}"
RUNTIME_DIR="${STEP_SYSTEMD_TEST_RUNTIME_DIR:-${REPO_ROOT}/.tmp/systemd-testing}"
INSTANCE="${STEP_SYSTEMD_TEST_INSTANCE:-test}"

STEP_CA_IMAGE="${STEP_CA_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit:latest}"
SOFTHSM_IMAGE="${SOFTHSM_IMAGE:-ghcr.io/wtcross/softhsm2-p11-kit:latest}"
STEP_TEST_INIT_IMAGE="${STEP_TEST_INIT_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit-test-init:latest}"

STEP_CA_ROOT_TOKEN_LABEL="${STEP_CA_ROOT_TOKEN_LABEL:-RootCA}"
STEP_CA_INTERMEDIATE_TOKEN_LABEL="${STEP_CA_INTERMEDIATE_TOKEN_LABEL:-IntermediateCA}"
STEP_CA_NAME="${STEP_CA_NAME:-Test CA}"
STEP_CA_DNS_NAMES="${STEP_CA_DNS_NAMES:-ca.example.local,ca.internal.local}"

STEP_HSM_PIN="${STEP_HSM_PIN:-123456}"
STEP_CA_ADMIN_PASSWORD="${STEP_CA_ADMIN_PASSWORD:-admin-password}"
SYSTEMD_INIT_BINARY="${STEP_SYSTEMD_INIT_BINARY:-/sbin/init}"
SYSTEMD_DEFAULT_UNIT="${STEP_SYSTEMD_DEFAULT_UNIT:-}"

usage() {
  cat <<USAGE
Usage: run-systemd-testing-container.sh [OPTIONS] [-- extra-container-args]

Run step-ca-p11-kit-systemd-testing with local image tar archives mounted.

Options:
  --image IMAGE               systemd-testing image reference
  --image-tar-dir PATH        Directory containing image tar archives
  --runtime-dir PATH          Runtime dir for secrets/state
  --instance NAME             systemd instance name
  --step-ca-image IMAGE       step-ca image reference to use inside nested podman
  --softhsm-image IMAGE       softhsm image reference to preload
  --step-test-init-image IMAGE
                              test-init image reference
  --help                      Show this help message
USAGE
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) SYSTEMD_TESTING_IMAGE="$2"; shift 2 ;;
    --image-tar-dir) IMAGE_TAR_DIR="$2"; shift 2 ;;
    --runtime-dir) RUNTIME_DIR="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --step-ca-image) STEP_CA_IMAGE="$2"; shift 2 ;;
    --softhsm-image) SOFTHSM_IMAGE="$2"; shift 2 ;;
    --step-test-init-image) STEP_TEST_INIT_IMAGE="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) EXTRA_ARGS+=("$1"); shift 1 ;;
  esac
done

function ensure_runtime_layout {
  mkdir -p "${RUNTIME_DIR}/secrets" "${RUNTIME_DIR}/step"

  if [[ ! -f "${RUNTIME_DIR}/secrets/hsm-pin" ]]; then
    printf '%s' "${STEP_HSM_PIN}" > "${RUNTIME_DIR}/secrets/hsm-pin"
  fi

  if [[ ! -f "${RUNTIME_DIR}/secrets/admin-password" ]]; then
    printf '%s' "${STEP_CA_ADMIN_PASSWORD}" > "${RUNTIME_DIR}/secrets/admin-password"
  fi

  chmod 0644 "${RUNTIME_DIR}/secrets/hsm-pin" "${RUNTIME_DIR}/secrets/admin-password"
}

require_command podman
require_image "${SYSTEMD_TESTING_IMAGE}"
require_dir "${IMAGE_TAR_DIR}"
require_file "${IMAGE_TAR_DIR}/step-ca-p11-kit.tar"
require_file "${IMAGE_TAR_DIR}/softhsm2-p11-kit.tar"
require_file "${IMAGE_TAR_DIR}/step-ca-p11-kit-test-init.tar"
ensure_runtime_layout

TTY_ARGS=()
if [[ -t 0 && -t 1 ]]; then
  TTY_ARGS=(-it)
fi

SYSTEMD_INIT_ARGS=()
if [[ -n "${SYSTEMD_DEFAULT_UNIT}" ]]; then
  SYSTEMD_INIT_ARGS+=("--unit=${SYSTEMD_DEFAULT_UNIT}")
fi

log_info "run-systemd-testing" "Running ${SYSTEMD_TESTING_IMAGE} with local image archives from ${IMAGE_TAR_DIR}"
exec podman run \
  "${TTY_ARGS[@]}" \
  --rm \
  --pull=never \
  --systemd=always \
  --privileged \
  --security-opt label=disable \
  --userns=host \
  --entrypoint "${SYSTEMD_INIT_BINARY}" \
  -e STEP_SYSTEMD_INSTANCE="${INSTANCE}" \
  -e STEP_CA_ROOT_PKCS11_TOKEN_LABEL="${STEP_CA_ROOT_TOKEN_LABEL}" \
  -e STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL="${STEP_CA_INTERMEDIATE_TOKEN_LABEL}" \
  -e STEP_HSM_PIN_FILE_PATH=/run/secrets/hsm-pin \
  -e STEP_ADMIN_PASSWORD_FILE=/run/secrets/admin-password \
  -e STEP_CA_NAME="${STEP_CA_NAME}" \
  -e STEP_CA_DNS_NAMES="${STEP_CA_DNS_NAMES}" \
  -e STEP_CA_IMAGE="${STEP_CA_IMAGE}" \
  -e SOFTHSM_IMAGE="${SOFTHSM_IMAGE}" \
  -e STEP_TEST_INIT_IMAGE="${STEP_TEST_INIT_IMAGE}" \
  -e STEP_SYSTEMD_TEST_IMAGE_TAR_DIR=/opt/step-p11-kit-images \
  -v "${IMAGE_TAR_DIR}:/opt/step-p11-kit-images:ro,z" \
  -v "${RUNTIME_DIR}/secrets:/run/secrets:z" \
  -v "${RUNTIME_DIR}/step:/root/.step:z" \
  "${SYSTEMD_TESTING_IMAGE}" \
  "${SYSTEMD_INIT_ARGS[@]}" \
  "${EXTRA_ARGS[@]}"
