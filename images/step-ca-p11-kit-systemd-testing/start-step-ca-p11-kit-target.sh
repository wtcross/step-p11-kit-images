#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/usr/local/share/step-p11-kit/validation.sh
source /usr/local/share/step-p11-kit/validation.sh
# shellcheck source=/usr/local/share/step-p11-kit/logging.sh
source /usr/local/share/step-p11-kit/logging.sh
# shellcheck source=/usr/local/share/step-p11-kit/pkcs11.sh
source /usr/local/share/step-p11-kit/pkcs11.sh

INSTANCE="${STEP_SYSTEMD_INSTANCE:-test}"
IMAGE_TAR_DIR="${STEP_SYSTEMD_TEST_IMAGE_TAR_DIR:-/opt/step-p11-kit-images}"

STEP_CA_IMAGE="${STEP_CA_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit:latest}"
SOFTHSM_IMAGE="${SOFTHSM_IMAGE:-ghcr.io/wtcross/softhsm2-p11-kit:latest}"
STEP_TEST_INIT_IMAGE="${STEP_TEST_INIT_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit-test-init:latest}"

STEP_CA_NAME="${STEP_CA_NAME:-Test CA}"
STEP_CA_DNS_NAMES="${STEP_CA_DNS_NAMES:-ca.example.local,ca.internal.local}"
STEP_CA_EXTERNAL_PORT="${STEP_CA_EXTERNAL_PORT:-9000}"
STEP_CA_ROOT_CERT_NAME="${STEP_CA_ROOT_CERT_NAME:-root.crt}"
STEP_CA_INTERMEDIATE_CERT_NAME="${STEP_CA_INTERMEDIATE_CERT_NAME:-intermediate.crt}"
STEP_HSM_PIN_FILE_PATH="${STEP_HSM_PIN_FILE_PATH:-/run/secrets/hsm-pin}"
STEP_ADMIN_PASSWORD_FILE="${STEP_ADMIN_PASSWORD_FILE:-/run/secrets/admin-password}"
STEP_P11KIT_CLIENT_MODULE_PATH="${STEP_P11KIT_CLIENT_MODULE_PATH:-/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so}"
SOFTHSM_LIB_PATH="${SOFTHSM_LIB_PATH:-/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so}"
STEPPATH="${STEPPATH:-${HOME}/.step}"
SYSTEMD_UNIT_DIR="${HOME}/.config/containers/systemd"
STEP_CA_CONTAINER_UNIT="${SYSTEMD_UNIT_DIR}/step-ca-p11-kit@.container"
STEP_CA_CONTAINER_NAME="${STEP_CA_CONTAINER_NAME:-step-ca-${INSTANCE}}"
STEP_CA_HEALTH_URL="${STEP_CA_HEALTH_URL:-}"
STEP_CA_HEALTH_ROOT_CERT_PATH="${STEP_CA_HEALTH_ROOT_CERT_PATH:-/run/secrets/root.crt}"
STEP_CA_HEALTH_RETRIES="${STEP_CA_HEALTH_RETRIES:-30}"
STEP_CA_HEALTH_RETRY_INTERVAL_SECONDS="${STEP_CA_HEALTH_RETRY_INTERVAL_SECONDS:-1}"
STEP_SYSTEMD_WAIT_FOR_SHUTDOWN="${STEP_SYSTEMD_WAIT_FOR_SHUTDOWN:-false}"
STEP_SYSTEMD_RESET_STEPPATH_ON_START="${STEP_SYSTEMD_RESET_STEPPATH_ON_START:-true}"
STEP_SYSTEMD_SHUTDOWN_ON_EXIT="${STEP_SYSTEMD_SHUTDOWN_ON_EXIT:-true}"

ROOT_PRIVATE_URI=""
INT_PRIVATE_URI=""
INT_KMS_URI=""

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
export STEPPATH

function trim_whitespace {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "${value}"
}

function validate_port_or_die {
  local port="${1:?port is required}"
  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    die "port must be numeric: ${port}"
  fi

  if (( port < 1 || port > 65535 )); then
    die "port must be between 1 and 65535: ${port}"
  fi
}

function step_ca_primary_dns_name {
  local -a raw_dns_names=()
  local raw_dns
  local dns_name=""

  IFS=',' read -r -a raw_dns_names <<< "${STEP_CA_DNS_NAMES}"
  for raw_dns in "${raw_dns_names[@]}"; do
    dns_name="$(trim_whitespace "${raw_dns}")"
    if [[ -n "${dns_name}" ]]; then
      echo "${dns_name}"
      return 0
    fi
  done

  die "STEP_CA_DNS_NAMES must include at least one DNS name"
}

function wait_for_socket {
  local socket_path="${1:?socket_path is required}"
  local timeout_seconds="${2:-30}"
  local elapsed=0

  while [[ ! -S "${socket_path}" && "${elapsed}" -lt "${timeout_seconds}" ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [[ ! -S "${socket_path}" ]]; then
    die "Timed out waiting for socket: ${socket_path}"
  fi
}

function setup_systemd_runtime_dir {
  mkdir -p "${XDG_RUNTIME_DIR}"
  chmod 0700 "${XDG_RUNTIME_DIR}"
}

function wait_for_user_manager {
  local retries=0
  local user_bus="${XDG_RUNTIME_DIR}/bus"

  while [[ ! -S "${user_bus}" ]]; do
    if [[ "${retries}" -ge 100 ]]; then
      die "Timed out waiting for user dbus socket at ${user_bus}"
    fi
    sleep 0.1
    retries=$((retries + 1))
  done

  retries=0
  while ! systemctl --user show-environment >/dev/null 2>&1; do
    if [[ "${retries}" -ge 100 ]]; then
      die "Timed out waiting for user systemd manager"
    fi
    sleep 0.1
    retries=$((retries + 1))
  done
}

function load_local_images {
  local image_tar
  local -a image_tars=(
    "${IMAGE_TAR_DIR}/step-ca-p11-kit.tar"
    "${IMAGE_TAR_DIR}/softhsm2-p11-kit.tar"
    "${IMAGE_TAR_DIR}/step-ca-p11-kit-test-init.tar"
  )

  for image_tar in "${image_tars[@]}"; do
    require_file "${image_tar}"
    log_info "systemd-testing" "Loading local image archive: ${image_tar}"
    podman load --input "${image_tar}" >/dev/null
  done

  require_image "${STEP_CA_IMAGE}"
  require_image "${SOFTHSM_IMAGE}"
  require_image "${STEP_TEST_INIT_IMAGE}"
}

function configure_step_ca_container_unit {
  require_file "${STEP_CA_CONTAINER_UNIT}"
  local -a raw_dns_names=()
  local raw_dns
  local dns_name=""

  sed -i "s|^Image=.*|Image=${STEP_CA_IMAGE}|" "${STEP_CA_CONTAINER_UNIT}"
  sed -i 's/^Pull=.*/Pull=always/' "${STEP_CA_CONTAINER_UNIT}"
  sed -i 's/^UserNS=.*/UserNS=host/' "${STEP_CA_CONTAINER_UNIT}"
  sed -i '/^AddHost=/d' "${STEP_CA_CONTAINER_UNIT}"

  IFS=',' read -r -a raw_dns_names <<< "${STEP_CA_DNS_NAMES}"
  for raw_dns in "${raw_dns_names[@]}"; do
    dns_name="$(trim_whitespace "${raw_dns}")"
    if [[ -n "${dns_name}" ]]; then
      printf 'AddHost=%s:127.0.0.1\n' "${dns_name}" >> "${STEP_CA_CONTAINER_UNIT}"
    fi
  done
}

function build_pkcs11_uris {
  local pin_path="/run/secrets/hsm-pin"

  ROOT_PRIVATE_URI="$(pkcs11_build_private_key_uri "${STEP_CA_ROOT_PKCS11_TOKEN_LABEL}" "01" "root" "${pin_path}" "${STEP_P11KIT_CLIENT_MODULE_PATH}")"
  INT_PRIVATE_URI="$(pkcs11_build_private_key_uri "${STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL}" "01" "intermediate" "${pin_path}" "${STEP_P11KIT_CLIENT_MODULE_PATH}")"
  INT_KMS_URI="$(pkcs11_build_kms_uri "${STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL}" "${pin_path}" "${STEP_P11KIT_CLIENT_MODULE_PATH}")"
}

function generate_instance_env_files {
  local hsm_uri="${STEP_HSM_PKCS11_URI:-pkcs11:}"

  /usr/local/bin/generate-instance-env.sh \
    --instance "${INSTANCE}" \
    --ca-name "${STEP_CA_NAME}" \
    --dns "${STEP_CA_DNS_NAMES}" \
    --external-port "${STEP_CA_EXTERNAL_PORT}" \
    --private-key-pkcs11-uri "${INT_PRIVATE_URI}" \
    --kms-pkcs11-uri "${INT_KMS_URI}" \
    --hsm-module "${SOFTHSM_LIB_PATH}" \
    --hsm-uri "${hsm_uri}" \
    --force
}

function start_p11_kit_target {
  local socket_dir="${XDG_RUNTIME_DIR}/p11-kit"
  local socket_path="${XDG_RUNTIME_DIR}/p11-kit/${INSTANCE}.sock"

  mkdir -p "${socket_dir}"

  log_info "systemd-testing" "Starting p11-kit-server@${INSTANCE}.target"
  systemctl --user daemon-reload
  systemctl --user start "p11-kit-server@${INSTANCE}.target"
  wait_for_socket "${socket_path}" 30
}

function run_ca_init_container {
  local init_container="step-ca-test-init-${INSTANCE}"
  local socket_mount="${XDG_RUNTIME_DIR}/p11-kit"

  mkdir -p "${STEPPATH}" "${socket_mount}"
  if [[ "${STEP_SYSTEMD_RESET_STEPPATH_ON_START}" == "true" ]]; then
    rm -rf "${STEPPATH:?}"/*
  fi
  chown -R 1001:1001 "${STEPPATH}"

  log_info "systemd-testing" "Running '${STEP_TEST_INIT_IMAGE}' for CA initialization"
  podman run --rm \
    --name "${init_container}" \
    --pull=never \
    --userns=host \
    -e STEP_CA_NAME="${STEP_CA_NAME}" \
    -e STEP_CA_DNS_NAMES="${STEP_CA_DNS_NAMES}" \
    -e STEP_HSM_PIN_FILE_PATH=/run/secrets/hsm-pin \
    -e STEP_P11KIT_SOCKET_PATH="/run/p11-kit/${INSTANCE}.sock" \
    -e STEP_CA_ROOT_PRIVATE_KEY_PKCS11_URI="${ROOT_PRIVATE_URI}" \
    -e STEP_CA_ROOT_CERT_NAME="${STEP_CA_ROOT_CERT_NAME}" \
    -e STEP_CA_INT_PRIVATE_KEY_PKCS11_URI="${INT_PRIVATE_URI}" \
    -e STEP_CA_INT_CERT_NAME="${STEP_CA_INTERMEDIATE_CERT_NAME}" \
    -v "${socket_mount}:/run/p11-kit:z" \
    -v "${STEP_HSM_PIN_FILE_PATH}:/run/secrets/hsm-pin:ro,z" \
    -v "${STEPPATH}:/home/step/.step:z" \
    "${STEP_TEST_INIT_IMAGE}"
}

function replace_secret {
  local secret_name="${1:?secret_name is required}"
  local source_path="${2:?source_path is required}"

  require_file "${source_path}"
  podman secret rm "${secret_name}" >/dev/null 2>&1 || true
  podman secret create "${secret_name}" "${source_path}" >/dev/null
}

function create_runtime_secrets {
  local root_cert_path="${STEPPATH}/certs/${STEP_CA_ROOT_CERT_NAME}"
  local intermediate_cert_path="${STEPPATH}/certs/${STEP_CA_INTERMEDIATE_CERT_NAME}"

  replace_secret "hsm-pin-${INSTANCE}" "${STEP_HSM_PIN_FILE_PATH}"
  replace_secret "admin-password-${INSTANCE}" "${STEP_ADMIN_PASSWORD_FILE}"
  replace_secret "root-cert-${INSTANCE}" "${root_cert_path}"
  replace_secret "intermediate-cert-${INSTANCE}" "${intermediate_cert_path}"
}

function start_step_ca_target {
  log_info "systemd-testing" "Starting step-ca-p11-kit@${INSTANCE}.target"
  systemctl --user daemon-reload
  systemctl --user start "step-ca-p11-kit@${INSTANCE}.target"
}

function run_step_ca_health_check {
  local health_url="${STEP_CA_HEALTH_URL:-https://$(step_ca_primary_dns_name):9000}"
  local attempt
  local -a health_cmd=(
    podman exec
    "${STEP_CA_CONTAINER_NAME}"
    step ca health
    --ca-url "${health_url}"
    --root "${STEP_CA_HEALTH_ROOT_CERT_PATH}"
  )

  for ((attempt = 1; attempt <= STEP_CA_HEALTH_RETRIES; attempt++)); do
    if "${health_cmd[@]}" >/dev/null 2>&1; then
      log_info "systemd-testing" "step-ca health check passed on attempt ${attempt}/${STEP_CA_HEALTH_RETRIES} (url: ${health_url})"
      return
    fi

    if [[ "${attempt}" -lt "${STEP_CA_HEALTH_RETRIES}" ]]; then
      sleep "${STEP_CA_HEALTH_RETRY_INTERVAL_SECONDS}"
    fi
  done

  log_info "systemd-testing" "step-ca health check failed; printing final command output"
  "${health_cmd[@]}" || true
  die "step-ca health check failed after ${STEP_CA_HEALTH_RETRIES} attempts"
}

function wait_for_step_ca_target_shutdown {
  local target="step-ca-p11-kit@${INSTANCE}.target"

  log_info "systemd-testing" "Waiting for ${target} to stop"
  while systemctl --user is-active --quiet "${target}"; do
    sleep 1
  done

  if systemctl --user is-failed --quiet "${target}"; then
    die "${target} failed"
  fi
}

function cleanup {
  local exit_code="${1:-0}"

  systemctl --user stop "step-ca-p11-kit@${INSTANCE}.target" >/dev/null 2>&1 || true
  systemctl --user stop "p11-kit-server@${INSTANCE}.target" >/dev/null 2>&1 || true
  if [[ "${STEP_SYSTEMD_SHUTDOWN_ON_EXIT}" == "true" ]]; then
    systemctl --no-block exit "${exit_code}" >/dev/null 2>&1 \
      || systemctl --no-block poweroff >/dev/null 2>&1 \
      || true
  fi

  trap - EXIT
  exit "${exit_code}"
}

trap 'cleanup $?' EXIT

require_env STEP_CA_ROOT_PKCS11_TOKEN_LABEL
require_env STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL
validate_port_or_die "${STEP_CA_EXTERNAL_PORT}"
require_file "${STEP_HSM_PIN_FILE_PATH}"
require_file "${STEP_ADMIN_PASSWORD_FILE}"
require_dir "${IMAGE_TAR_DIR}"
require_env DBUS_SESSION_BUS_ADDRESS
require_command podman
require_command systemctl

setup_systemd_runtime_dir
wait_for_user_manager
load_local_images
configure_step_ca_container_unit
build_pkcs11_uris
generate_instance_env_files
start_p11_kit_target
run_ca_init_container
create_runtime_secrets
start_step_ca_target
run_step_ca_health_check

if [[ "${STEP_SYSTEMD_WAIT_FOR_SHUTDOWN}" == "true" ]]; then
  wait_for_step_ca_target_shutdown
fi
