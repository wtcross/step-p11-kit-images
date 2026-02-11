#!/usr/bin/env bash

assert_status_eq() {
  local expected="${1:?expected status is required}"
  if [[ "${status}" -ne "${expected}" ]]; then
    echo "Expected status ${expected}, got ${status}" >&2
    echo "Output: ${output}" >&2
    return 1
  fi
}

assert_status_ne() {
  local unexpected="${1:?unexpected status is required}"
  if [[ "${status}" -eq "${unexpected}" ]]; then
    echo "Expected status not equal to ${unexpected}" >&2
    echo "Output: ${output}" >&2
    return 1
  fi
}

assert_output_contains() {
  local expected="${1:?expected substring is required}"
  if [[ "${output}" != *"${expected}"* ]]; then
    echo "Expected output to contain: ${expected}" >&2
    echo "Output: ${output}" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="${1:?path is required}"
  if [[ ! -e "${path}" ]]; then
    echo "Expected file to exist: ${path}" >&2
    return 1
  fi
}

assert_file_nonempty() {
  local path="${1:?path is required}"
  if [[ ! -s "${path}" ]]; then
    echo "Expected non-empty file: ${path}" >&2
    return 1
  fi
}
