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

TAR_DIR="${STEP_SYSTEMD_TEST_IMAGE_TAR_DIR:-${REPO_ROOT}/.tmp/image-tars}"
STEP_CA_IMAGE="${STEP_CA_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit:latest}"
SOFTHSM_IMAGE="${SOFTHSM_IMAGE:-ghcr.io/wtcross/softhsm2-p11-kit:latest}"
STEP_TEST_INIT_IMAGE="${STEP_TEST_INIT_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit-test-init:latest}"

usage() {
  cat <<USAGE
Usage: save-systemd-testing-image-tars.sh [OPTIONS]

Save required test images as local OCI archives for systemd-testing.

Options:
  --tar-dir PATH             Output directory for image tars
  --step-ca-image IMAGE      step-ca image reference
  --softhsm-image IMAGE      softhsm image reference
  --step-test-init-image IMAGE
                             test-init image reference
  --help                     Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tar-dir) TAR_DIR="$2"; shift 2 ;;
    --step-ca-image) STEP_CA_IMAGE="$2"; shift 2 ;;
    --softhsm-image) SOFTHSM_IMAGE="$2"; shift 2 ;;
    --step-test-init-image) STEP_TEST_INIT_IMAGE="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

function save_image_tar {
  local image_ref="${1:?image_ref is required}"
  local output_path="${2:?output_path is required}"

  require_image "${image_ref}"
  log_info "save-image-tars" "Saving ${image_ref} -> ${output_path}"
  podman save --format oci-archive --output "${output_path}" "${image_ref}"
}

require_command podman
mkdir -p "${TAR_DIR}"

save_image_tar "${STEP_CA_IMAGE}" "${TAR_DIR}/step-ca-p11-kit.tar"
save_image_tar "${SOFTHSM_IMAGE}" "${TAR_DIR}/softhsm2-p11-kit.tar"
save_image_tar "${STEP_TEST_INIT_IMAGE}" "${TAR_DIR}/step-ca-p11-kit-test-init.tar"

log_info "save-image-tars" "Saved image archives in ${TAR_DIR}"
