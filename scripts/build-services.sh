#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

service_names() {
  local raw
  IFS=',' read -r -a raw_services <<< "${SERVICES}"
  for raw in "${raw_services[@]}"; do
    raw="${raw//[[:space:]]/}"
    if [[ -n "${raw}" ]]; then
      echo "${raw}"
    fi
  done
}

service_image() {
  local service="$1"
  echo "${REGISTRY_URL}/${REGISTRY_PROJECT}/${APP_NAME}-${service}:${IMAGE_TAG}"
}

require_env APP_NAME
require_env MSA_WORKLOAD_DIR
require_env SERVICES
require_env REGISTRY_URL
require_env REGISTRY_PROJECT
require_env IMAGE_TAG
require_env REPORT_DIR

for service in $(service_names); do
  context="${MSA_WORKLOAD_DIR}"
  dockerfile="${MSA_WORKLOAD_DIR}/services/${service}/Dockerfile"
  image="$(service_image "${service}")"
  log_dir="${REPORT_DIR}/services/${service}/docker"

  if [[ ! -f "${dockerfile}" ]]; then
    echo "ERROR: Dockerfile not found for service ${service}: ${dockerfile}" >&2
    exit 1
  fi

  mkdir -p "${log_dir}"
  echo "Building ${service}: ${image}"
  if docker build -f "${dockerfile}" -t "${image}" "${context}" > "${log_dir}/build.log" 2>&1; then
    echo "Build completed for ${service}"
  else
    echo "ERROR: docker build failed for ${service}. See ${log_dir}/build.log" >&2
    exit 1
  fi
done
