#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

require_env WORKLOAD_DIR
require_env DOCKERFILE_PATH
require_env BUILD_CONTEXT
require_env IMAGE
require_env REPORT_DIR

if [[ ! -d "${WORKLOAD_DIR}" ]]; then
  echo "ERROR: WORKLOAD_DIR does not exist: ${WORKLOAD_DIR}" >&2
  exit 1
fi

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "ERROR: DOCKERFILE_PATH does not exist: ${DOCKERFILE_PATH}" >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}/docker"

echo "Building image: ${IMAGE}"
echo "Dockerfile: ${DOCKERFILE_PATH}"
echo "Build context: ${BUILD_CONTEXT}"

docker build \
  --file "${DOCKERFILE_PATH}" \
  --tag "${IMAGE}" \
  "${BUILD_CONTEXT}" 2>&1 | tee "${REPORT_DIR}/docker/build.log"

