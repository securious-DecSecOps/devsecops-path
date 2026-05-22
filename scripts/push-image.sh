#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

require_env IMAGE
require_env REPORT_DIR

mkdir -p "${REPORT_DIR}/registry"

echo "Pushing image: ${IMAGE}"
docker push "${IMAGE}" 2>&1 | tee "${REPORT_DIR}/registry/push.log"

