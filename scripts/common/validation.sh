#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

function die {
  local message="${1:-unknown error}"
  echo "Error: ${message}" >&2
  exit 1
}

function require_env {
  local var_name="${1:?var_name is required}"
  local var_value="${!var_name:-}"
  if [[ -z "${var_value}" ]]; then
    die "${var_name} is required"
  fi
}

function require_file {
  local path="${1:?path is required}"
  if [[ ! -f "${path}" ]]; then
    die "File not found at ${path}"
  fi
}

function require_dir {
  local path="${1:?path is required}"
  if [[ ! -d "${path}" ]]; then
    die "Directory not found at ${path}"
  fi
}

function require_socket {
  local path="${1:?path is required}"
  if [[ ! -S "${path}" ]]; then
    die "Socket not found at ${path}"
  fi
}

function require_command {
  local command_name="${1:?command_name is required}"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    die "Required command not found: ${command_name}"
  fi
}

function require_image {
  local image="${1:?image is required}"
  if ! podman image exists "${image}"; then
    die "required image not found: ${image}"
  fi
}
