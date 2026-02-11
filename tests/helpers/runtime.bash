#!/usr/bin/env bash

SOFTHSM_TEST_IMAGE="${SOFTHSM_TEST_IMAGE:-ghcr.io/wtcross/softhsm2-p11-kit:latest}"
STEP_CA_INIT_TEST_IMAGE="${STEP_CA_INIT_TEST_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit-test-init:latest}"
STEP_CA_TEST_IMAGE="${STEP_CA_TEST_IMAGE:-ghcr.io/wtcross/step-ca-p11-kit:latest}"
STEP_TEST_REPO_ROOT="${STEP_TEST_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STEP_TEST_COMMON_SCRIPTS_DIR="${STEP_TEST_COMMON_SCRIPTS_DIR:-${STEP_TEST_REPO_ROOT}/scripts/common}"
STEP_TEST_TMP_ROOT="${STEP_TEST_TMP_ROOT:-${STEP_TEST_REPO_ROOT}/.tmp}"
STEP_TEST_CONTEXT_DIR="${STEP_TEST_CONTEXT_DIR:-${STEP_TEST_TMP_ROOT}/contexts}"

STEP_P11KIT_CLIENT_MODULE_PATH="${STEP_P11KIT_CLIENT_MODULE_PATH:-/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so}"
STEP_CA_NAME="${STEP_CA_NAME:-Test CA}"
STEP_CA_DNS_NAMES="${STEP_CA_DNS_NAMES:-ca.example.local,ca.internal.local}"
STEP_CA_ROOT_TOKEN_LABEL="${STEP_CA_ROOT_TOKEN_LABEL:-RootCA}"
STEP_CA_INTERMEDIATE_TOKEN_LABEL="${STEP_CA_INTERMEDIATE_TOKEN_LABEL:-IntermediateCA}"
STEP_CA_ROOT_CERT_NAME="${STEP_CA_ROOT_CERT_NAME:-root.crt}"
STEP_CA_INTERMEDIATE_CERT_NAME="${STEP_CA_INTERMEDIATE_CERT_NAME:-intermediate.crt}"
STEP_CA_ADMIN_PASSWORD="${STEP_CA_ADMIN_PASSWORD:-admin-password}"

STEP_TEST_ID=""
STEP_TEST_PIN=""
STEP_TEST_TMPDIR=""
STEP_SOFTHSM_CONTAINER=""
STEP_INIT_CONTAINER=""
STEP_CA_CONTAINER=""

ensure_test_images() {
  local image

  if [[ ! -d "${STEP_TEST_COMMON_SCRIPTS_DIR}" ]]; then
    echo "Required scripts directory not found: ${STEP_TEST_COMMON_SCRIPTS_DIR}" >&2
    return 1
  fi

  for image in "${SOFTHSM_TEST_IMAGE}" "${STEP_CA_INIT_TEST_IMAGE}" "${STEP_CA_TEST_IMAGE}"; do
    if ! podman image exists "${image}"; then
      echo "Required image not found: ${image}" >&2
      return 1
    fi
  done
}

generate_test_pin() {
  local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local pin=""

  while [[ ${#pin} -lt 6 ]]; do
    pin+="${alphabet:RANDOM%${#alphabet}:1}"
  done

  echo "${pin}"
}

trim_whitespace() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "${value}"
}

step_ca_primary_dns_name() {
  local -a raw_dns_names=()
  local dns_name=""

  IFS=',' read -r -a raw_dns_names <<< "${STEP_CA_DNS_NAMES}"
  for raw_dns in "${raw_dns_names[@]}"; do
    dns_name="$(trim_whitespace "${raw_dns}")"
    if [[ -n "${dns_name}" ]]; then
      echo "${dns_name}"
      return 0
    fi
  done

  echo "ca.example.local"
}

create_runtime_dirs() {
  local base_dir="${1:?base_dir is required}"
  mkdir -p "${base_dir}/p11-kit"
  mkdir -p "${base_dir}/secrets"
  mkdir -p "${base_dir}/step"
  chmod 0777 "${base_dir}/p11-kit" "${base_dir}/secrets" "${base_dir}/step"
}

write_runtime_secrets() {
  local base_dir="${1:?base_dir is required}"
  printf '%s' "${STEP_TEST_PIN}" > "${base_dir}/secrets/hsm-pin"
  printf '%s' "${STEP_CA_ADMIN_PASSWORD}" > "${base_dir}/secrets/admin-password"
  chmod 0644 "${base_dir}/secrets/hsm-pin" "${base_dir}/secrets/admin-password"
}

initialize_test_context() {
  STEP_TEST_PIN="$(generate_test_pin)"
  STEP_TEST_ID="${STEP_TEST_PIN}"
  mkdir -p "${STEP_TEST_TMP_ROOT}"
  STEP_TEST_TMPDIR="$(mktemp -d -p "${STEP_TEST_TMP_ROOT}" "step-ca-${STEP_TEST_PIN}-XXXXXX")"

  STEP_SOFTHSM_CONTAINER="softhsm2-${STEP_TEST_ID}"
  STEP_INIT_CONTAINER="step-ca-init-${STEP_TEST_ID}"
  STEP_CA_CONTAINER="step-ca-${STEP_TEST_ID}"

  create_runtime_dirs "${STEP_TEST_TMPDIR}"
  write_runtime_secrets "${STEP_TEST_TMPDIR}"
}

test_context_file_path() {
  local suite_path="${1:?suite_path is required}"
  local suite_name

  suite_name="$(basename "${suite_path}" .bats)"
  mkdir -p "${STEP_TEST_CONTEXT_DIR}"
  echo "${STEP_TEST_CONTEXT_DIR}/${suite_name}.env"
}

save_test_context() {
  local suite_path="${1:?suite_path is required}"
  local context_path

  context_path="$(test_context_file_path "${suite_path}")"
  {
    printf 'STEP_TEST_ID=%q\n' "${STEP_TEST_ID}"
    printf 'STEP_TEST_PIN=%q\n' "${STEP_TEST_PIN}"
    printf 'STEP_TEST_TMPDIR=%q\n' "${STEP_TEST_TMPDIR}"
    printf 'STEP_SOFTHSM_CONTAINER=%q\n' "${STEP_SOFTHSM_CONTAINER}"
    printf 'STEP_INIT_CONTAINER=%q\n' "${STEP_INIT_CONTAINER}"
    printf 'STEP_CA_CONTAINER=%q\n' "${STEP_CA_CONTAINER}"
  } > "${context_path}"
}

load_test_context() {
  local suite_path="${1:?suite_path is required}"
  local context_path

  context_path="$(test_context_file_path "${suite_path}")"
  if [[ ! -f "${context_path}" ]]; then
    echo "Test context not found: ${context_path}" >&2
    return 1
  fi

  # shellcheck disable=SC1090
  source "${context_path}"
}

clear_test_context() {
  local suite_path="${1:?suite_path is required}"
  local context_path

  context_path="$(test_context_file_path "${suite_path}")"
  rm -f "${context_path}"
}

wait_for_socket() {
  local socket_path="${1:?socket_path is required}"
  local timeout_seconds="${2:-30}"
  local elapsed=0

  while [[ ! -S "${socket_path}" && "${elapsed}" -lt "${timeout_seconds}" ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [[ ! -S "${socket_path}" ]]; then
    echo "Timed out waiting for PKCS#11 socket at ${socket_path}" >&2
    return 1
  fi
}

wait_for_ca_health() {
  local container_name="${1:?container_name is required}"
  local timeout_seconds="${2:-60}"
  local elapsed=0
  local health_output=""
  local health_dns_name
  local health_url
  local root_cert

  health_dns_name="$(step_ca_primary_dns_name)"
  health_url="https://${health_dns_name}:9000"
  root_cert="/home/step/.step/certs/${STEP_CA_ROOT_CERT_NAME}"

  while [[ "${elapsed}" -lt "${timeout_seconds}" ]]; do
    if health_output="$(podman exec "${container_name}" step ca health --ca-url "${health_url}" --root "${root_cert}" 2>/dev/null)"; then
      if [[ "${health_output}" == *"ok"* ]]; then
        return 0
      fi
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  echo "Timed out waiting for step-ca health response" >&2
  podman logs "${container_name}" >&2 || true
  return 1
}

start_softhsm2_p11_kit() {
  podman run -d --rm \
    --name "${STEP_SOFTHSM_CONTAINER}" \
    --pull=never \
    -e STEP_CA_ROOT_PKCS11_TOKEN_LABEL="${STEP_CA_ROOT_TOKEN_LABEL}" \
    -e STEP_CA_INTERMEDIATE_PKCS11_TOKEN_LABEL="${STEP_CA_INTERMEDIATE_TOKEN_LABEL}" \
    -e STEP_HSM_PIN_FILE_PATH=/run/secrets/hsm-pin \
    -e STEP_P11KIT_SOCKET_PATH=/run/p11-kit/pkcs11-socket \
    -v "${STEP_TEST_TMPDIR}/p11-kit:/run/p11-kit:z" \
    -v "${STEP_TEST_TMPDIR}/secrets:/run/secrets:z" \
    -v "${STEP_TEST_COMMON_SCRIPTS_DIR}:/usr/local/share/step-p11-kit:ro,z" \
    "${SOFTHSM_TEST_IMAGE}" >/dev/null

  wait_for_socket "${STEP_TEST_TMPDIR}/p11-kit/pkcs11-socket"
}

run_step_ca_p11_kit_test_init() {
  local root_private_uri
  local int_private_uri

  root_private_uri="pkcs11:token=${STEP_CA_ROOT_TOKEN_LABEL};id=%01;object=root;type=private?module-path=${STEP_P11KIT_CLIENT_MODULE_PATH}&pin-source=file:///run/secrets/hsm-pin"
  int_private_uri="pkcs11:token=${STEP_CA_INTERMEDIATE_TOKEN_LABEL};id=%01;object=intermediate;type=private?module-path=${STEP_P11KIT_CLIENT_MODULE_PATH}&pin-source=file:///run/secrets/hsm-pin"

  podman run --rm \
    --name "${STEP_INIT_CONTAINER}" \
    --pull=never \
    -e STEP_CA_NAME="${STEP_CA_NAME}" \
    -e STEP_CA_DNS_NAMES="${STEP_CA_DNS_NAMES}" \
    -e STEP_HSM_PIN_FILE_PATH=/run/secrets/hsm-pin \
    -e STEP_P11KIT_SOCKET_PATH=/run/p11-kit/pkcs11-socket \
    -e STEP_CA_ROOT_PRIVATE_KEY_PKCS11_URI="${root_private_uri}" \
    -e STEP_CA_ROOT_CERT_NAME="${STEP_CA_ROOT_CERT_NAME}" \
    -e STEP_CA_INT_PRIVATE_KEY_PKCS11_URI="${int_private_uri}" \
    -e STEP_CA_INT_CERT_NAME="${STEP_CA_INTERMEDIATE_CERT_NAME}" \
    -v "${STEP_TEST_TMPDIR}/p11-kit:/run/p11-kit:z" \
    -v "${STEP_TEST_TMPDIR}/secrets:/run/secrets:z" \
    -v "${STEP_TEST_TMPDIR}/step:/home/step/.step:z" \
    -v "${STEP_TEST_COMMON_SCRIPTS_DIR}:/usr/local/share/step-p11-kit:ro,z" \
    "${STEP_CA_INIT_TEST_IMAGE}" >/dev/null
}

start_step_ca_p11_kit() {
  local ca_private_uri
  local ca_kms_uri
  local -a raw_dns_names=()
  local -a add_host_args=()
  local dns_name=""

  ca_private_uri="pkcs11:token=${STEP_CA_INTERMEDIATE_TOKEN_LABEL};id=%01;object=intermediate;type=private?module-path=${STEP_P11KIT_CLIENT_MODULE_PATH}&pin-source=file:///run/secrets/hsm-pin"
  ca_kms_uri="pkcs11:token=${STEP_CA_INTERMEDIATE_TOKEN_LABEL}?module-path=${STEP_P11KIT_CLIENT_MODULE_PATH}&pin-source=file:///run/secrets/hsm-pin"

  IFS=',' read -r -a raw_dns_names <<< "${STEP_CA_DNS_NAMES}"
  for raw_dns in "${raw_dns_names[@]}"; do
    dns_name="$(trim_whitespace "${raw_dns}")"
    if [[ -n "${dns_name}" ]]; then
      add_host_args+=(--add-host "${dns_name}:127.0.0.1")
    fi
  done

  podman run -d --rm \
    --name "${STEP_CA_CONTAINER}" \
    --pull=never \
    "${add_host_args[@]}" \
    -e STEP_CA_NAME="${STEP_CA_NAME}" \
    -e STEP_CA_DNS_NAMES="${STEP_CA_DNS_NAMES}" \
    -e STEP_HSM_PIN_FILE_PATH=/run/secrets/hsm-pin \
    -e STEP_P11KIT_SOCKET_PATH=/run/p11-kit/pkcs11-socket \
    -e STEP_CA_PRIVATE_KEY_PKCS11_URI="${ca_private_uri}" \
    -e STEP_CA_KMS_PKCS11_URI="${ca_kms_uri}" \
    -e STEP_ADMIN_PASSWORD_FILE=/run/secrets/admin-password \
    -e STEP_ROOT_CERT_FILE="/home/step/.step/certs/${STEP_CA_ROOT_CERT_NAME}" \
    -e STEP_INTERMEDIATE_CERT_FILE="/home/step/.step/certs/${STEP_CA_INTERMEDIATE_CERT_NAME}" \
    -e STEP_CA_ADDRESS=:9000 \
    -v "${STEP_TEST_TMPDIR}/p11-kit:/run/p11-kit:z" \
    -v "${STEP_TEST_TMPDIR}/secrets:/run/secrets:z" \
    -v "${STEP_TEST_TMPDIR}/step:/home/step/.step:z" \
    -v "${STEP_TEST_COMMON_SCRIPTS_DIR}:/usr/local/share/step-p11-kit:ro,z" \
    "${STEP_CA_TEST_IMAGE}" >/dev/null
}

create_step_ca_deployment() {
  ensure_test_images
  initialize_test_context
  start_softhsm2_p11_kit
  run_step_ca_p11_kit_test_init
  start_step_ca_p11_kit
  wait_for_ca_health "${STEP_CA_CONTAINER}"
}

teardown_step_ca_deployment() {
  podman rm -f "${STEP_CA_CONTAINER}" >/dev/null 2>&1 || true
  podman rm -f "${STEP_INIT_CONTAINER}" >/dev/null 2>&1 || true
  podman rm -f "${STEP_SOFTHSM_CONTAINER}" >/dev/null 2>&1 || true

  if [[ -n "${STEP_TEST_TMPDIR}" && -d "${STEP_TEST_TMPDIR}" ]]; then
    if ! rm -rf "${STEP_TEST_TMPDIR}" >/dev/null 2>&1; then
      podman unshare rm -rf "${STEP_TEST_TMPDIR}" >/dev/null 2>&1 || true
    fi
  fi

  STEP_TEST_ID=""
  STEP_TEST_PIN=""
  STEP_TEST_TMPDIR=""
  STEP_SOFTHSM_CONTAINER=""
  STEP_INIT_CONTAINER=""
  STEP_CA_CONTAINER=""
}
