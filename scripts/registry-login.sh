#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

require_env REGISTRY_URL
require_env REPORT_DIR

mkdir -p "${REPORT_DIR}/registry"
login_log="${REPORT_DIR}/registry/login.log"

if [[ -n "${REGISTRY_USERNAME:-}" && -n "${REGISTRY_PASSWORD:-}" ]]; then
  echo "Logging in to registry ${REGISTRY_URL} as ${REGISTRY_USERNAME}" | tee "${login_log}"
  if ! printf '%s' "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_URL}" --username "${REGISTRY_USERNAME}" --password-stdin 2>&1 | tee -a "${login_log}"; then
    echo "ERROR: docker login failed for ${REGISTRY_URL}." >&2
    exit 1
  fi
else
  {
    echo "WARN: REGISTRY_USERNAME or REGISTRY_PASSWORD is not set."
    echo "WARN: Skipping docker login. This may work only when Jenkins already has registry access or an insecure local registry is configured."
    echo "WARN: Production should use Jenkins Credentials, Harbor Robot Account, or ECR IAM auth."
  } | tee "${login_log}"
fi

