#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${STEP_P11KIT_CLIENT_MODULE_PATH:=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so}"
: "${STEP_P11KIT_SOCKET_PATH:=/run/p11-kit/pkcs11-socket}"
: "${STEP_HSM_PIN_FILE_PATH:=/run/secrets/hsm-pin}"

function pkcs11_format_key_id {
  local key_id="${1:?key_id is required}"
  if [[ "${key_id}" =~ ^% ]]; then
    echo "${key_id}"
  else
    echo "%${key_id}"
  fi
}

function pkcs11_key_id_for_pkcs11_tool {
  local key_id="${1:?key_id is required}"
  key_id="${key_id//%/}"
  echo "${key_id}"
}

function pkcs11_pin_source_uri {
  local pin_path="${1:?pin_path is required}"
  if [[ "${pin_path}" =~ ^file:// ]]; then
    echo "${pin_path}"
  else
    echo "file://${pin_path}"
  fi
}

function pkcs11_build_private_key_uri {
  local token_label="${1:?token_label is required}"
  local key_id="${2:?key_id is required}"
  local key_label="${3:?key_label is required}"
  local pin_path="${4:?pin_path is required}"
  local module_path="${5:-${STEP_P11KIT_CLIENT_MODULE_PATH}}"
  local pin_source

  pin_source="$(pkcs11_pin_source_uri "${pin_path}")"
  echo "pkcs11:token=${token_label};id=$(pkcs11_format_key_id "${key_id}");object=${key_label};type=private?module-path=${module_path}&pin-source=${pin_source}"
}

function pkcs11_build_kms_uri {
  local token_label="${1:?token_label is required}"
  local pin_path="${2:?pin_path is required}"
  local module_path="${3:-${STEP_P11KIT_CLIENT_MODULE_PATH}}"
  local pin_source

  pin_source="$(pkcs11_pin_source_uri "${pin_path}")"
  echo "pkcs11:token=${token_label}?module-path=${module_path}&pin-source=${pin_source}"
}

function pkcs11_parse_uri_attr {
  local uri="${1:?uri is required}"
  local attr_name="${2:?attr_name is required}"
  local body path_part query_part key value
  local path_field query_field

  body="${uri#pkcs11:}"
  path_part="${body%%\?*}"
  query_part=""

  if [[ "${body}" == *\?* ]]; then
    query_part="${body#*\?}"
  fi

  IFS=';' read -r -a path_field <<< "${path_part}"
  for field in "${path_field[@]}"; do
    if [[ "${field}" != *=* ]]; then
      continue
    fi
    key="${field%%=*}"
    value="${field#*=}"
    if [[ "${key}" == "${attr_name}" ]]; then
      echo "${value}"
      return 0
    fi
  done

  IFS='&' read -r -a query_field <<< "${query_part}"
  for field in "${query_field[@]}"; do
    if [[ "${field}" != *=* ]]; then
      continue
    fi
    key="${field%%=*}"
    value="${field#*=}"
    if [[ "${key}" == "${attr_name}" ]]; then
      echo "${value}"
      return 0
    fi
  done

  return 1
}

function pkcs11_derive_kms_uri_from_private_key_uri {
  local private_key_uri="${1:?private_key_uri is required}"
  local token_label=""
  local module_path=""
  local pin_source=""

  if ! token_label="$(pkcs11_parse_uri_attr "${private_key_uri}" "token")"; then
    echo "PKCS#11 URI is missing required attribute 'token': ${private_key_uri}" >&2
    return 1
  fi

  if ! module_path="$(pkcs11_parse_uri_attr "${private_key_uri}" "module-path")"; then
    echo "PKCS#11 URI is missing required attribute 'module-path': ${private_key_uri}" >&2
    return 1
  fi

  if ! pin_source="$(pkcs11_parse_uri_attr "${private_key_uri}" "pin-source")"; then
    echo "PKCS#11 URI is missing required attribute 'pin-source': ${private_key_uri}" >&2
    return 1
  fi

  pkcs11_build_kms_uri "${token_label}" "${pin_source}" "${module_path}"
}

function pkcs11_read_pin {
  local pin_file="${1:?pin_file is required}"
  head -n 1 "${pin_file}"
}
