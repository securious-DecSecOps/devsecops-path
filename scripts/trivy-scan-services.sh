#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SERVICES="user-service,transaction-service,status-service,file-service,settings-service,frontend"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

service_names() {
  local raw_services
  local service
  local raw="${SERVICES:-${DEFAULT_SERVICES}}"
  IFS=',' read -r -a raw_services <<< "${raw}"
  for service in "${raw_services[@]}"; do
    service="${service//[[:space:]]/}"
    if [[ -n "${service}" ]]; then
      echo "${service}"
    fi
  done
}

service_image() {
  local service="$1"
  echo "${REGISTRY_URL}/${REGISTRY_PROJECT}/${APP_NAME}-${service}:${IMAGE_TAG}"
}

safe_name() {
  local value="$1"
  value="${value//[^a-zA-Z0-9_.-]/-}"
  echo "${value}"
}

require_env APP_NAME
require_env REGISTRY_URL
require_env REGISTRY_PROJECT
require_env IMAGE_TAG
require_env REPORT_DIR
require_cmd docker
require_cmd trivy

SERVICES="${SERVICES:-${DEFAULT_SERVICES}}"

if [[ -z "$(service_names)" ]]; then
  echo "ERROR: SERVICES did not contain any valid service names." >&2
  exit 1
fi

trivy_root="${REPORT_DIR}/trivy"
summary_file="${trivy_root}/scan-summary.txt"
mkdir -p "${trivy_root}"
: > "${summary_file}"

echo "Trivy service image scan started"
echo "APP_NAME=${APP_NAME}" | tee -a "${summary_file}"
echo "REGISTRY_URL=${REGISTRY_URL}" | tee -a "${summary_file}"
echo "REGISTRY_PROJECT=${REGISTRY_PROJECT}" | tee -a "${summary_file}"
echo "IMAGE_TAG=${IMAGE_TAG}" | tee -a "${summary_file}"
echo "SERVICES=${SERVICES}" | tee -a "${summary_file}"

for service in $(service_names); do
  image="$(service_image "${service}")"
  service_safe="$(safe_name "${service}")"
  service_trivy_dir="${REPORT_DIR}/services/${service}/trivy"
  json_report="${trivy_root}/trivy-report-${service_safe}.json"
  table_report="${trivy_root}/trivy-report-${service_safe}.txt"
  scan_error="${trivy_root}/trivy-report-${service_safe}.err"

  mkdir -p "${service_trivy_dir}"

  echo "Scanning service=${service} image=${image}" | tee -a "${summary_file}"

  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    echo "ERROR: Docker image does not exist locally for service ${service}: ${image}" | tee -a "${summary_file}" >&2
    exit 1
  fi

  if ! trivy image \
      --exit-code 0 \
      --no-progress \
      --format json \
      --output "${json_report}" \
      "${image}" > "${scan_error}" 2>&1; then
    echo "ERROR: Trivy JSON scan failed for ${service}. See ${scan_error}" | tee -a "${summary_file}" >&2
    exit 1
  fi

  if ! trivy image \
      --exit-code 0 \
      --no-progress \
      --format table \
      --output "${table_report}" \
      "${image}" >> "${scan_error}" 2>&1; then
    echo "ERROR: Trivy table scan failed for ${service}. See ${scan_error}" | tee -a "${summary_file}" >&2
    exit 1
  fi

  cp "${json_report}" "${service_trivy_dir}/image-scan.json"
  cp "${table_report}" "${service_trivy_dir}/image-scan.txt"
  cp "${scan_error}" "${service_trivy_dir}/scan.err"

  echo "Report JSON=${json_report}" | tee -a "${summary_file}"
  echo "Report TXT=${table_report}" | tee -a "${summary_file}"
done

echo "Trivy service image scan completed" | tee -a "${summary_file}"
