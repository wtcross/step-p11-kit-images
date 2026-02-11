#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

function _log_timestamp {
  date '+%Y-%m-%d %H:%M:%S'
}

function _log_line {
  local level="${1:?level is required}"
  local component="${2:?component is required}"
  local message="${3:?message is required}"
  local timestamp

  timestamp="$(_log_timestamp)"
  echo "[${timestamp}] [${component}] [${level}] ${message}"
}

function log_info {
  local component="${1:?component is required}"
  local message="${2:?message is required}"
  _log_line "INFO" "${component}" "${message}"
}

function log_warn {
  local component="${1:?component is required}"
  local message="${2:?message is required}"
  _log_line "WARN" "${component}" "${message}"
}

function log_error {
  local component="${1:?component is required}"
  local message="${2:?message is required}"
  _log_line "ERROR" "${component}" "${message}" >&2
}
