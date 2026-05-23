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

gate_result() {
  local summary="${REPORT_DIR}/gate/msa-gate-summary.txt"
  local compat="${REPORT_DIR}/gate/gate-result.txt"
  if [[ -f "${summary}" ]]; then
    awk -F= '$1 == "OVERALL_GATE_RESULT" { value=$2 } END { if (value) print value }' "${summary}"
  elif [[ -f "${compat}" ]]; then
    awk -F= '$1 == "OVERALL_GATE_RESULT" || $1 == "GATE_STATUS" { value=$2 } END { if (value) print value }' "${compat}"
  else
    echo ""
  fi
}

require_env APP_NAME
require_env REGISTRY_URL
require_env REGISTRY_PROJECT
require_env IMAGE_TAG
require_env REPORT_DIR
require_cmd docker

SERVICES="${SERVICES:-${DEFAULT_SERVICES}}"

if [[ -z "$(service_names)" ]]; then
  echo "ERROR: SERVICES did not contain any valid service names." >&2
  exit 1
fi

gate_status="$(gate_result)"
if [[ -z "${gate_status}" ]]; then
  echo "ERROR: security gate result was not found under ${REPORT_DIR}/gate. Refusing to push service images." >&2
  exit 1
fi

if [[ "${gate_status}" != "PASS" ]]; then
  if [[ "${ENFORCE_GATE:-true}" == "true" ]]; then
    echo "ERROR: security gate result is ${gate_status} and ENFORCE_GATE=true. Refusing to push service images." >&2
    if [[ -f "${REPORT_DIR}/gate/msa-gate-summary.txt" ]]; then
      sed -n '1,240p' "${REPORT_DIR}/gate/msa-gate-summary.txt" >&2
    fi
    exit 1
  else
    echo "WARN: security gate result is ${gate_status} but ENFORCE_GATE=false. Proceeding with push; findings remain in evidence." >&2
  fi
fi

registry_root="${REPORT_DIR}/registry"
summary="${registry_root}/push-services-summary.txt"
mkdir -p "${registry_root}"
: > "${summary}"

echo "Pushing MSA service images after security gate PASS" | tee -a "${summary}"
echo "APP_NAME=${APP_NAME}" | tee -a "${summary}"
echo "REGISTRY_URL=${REGISTRY_URL}" | tee -a "${summary}"
echo "REGISTRY_PROJECT=${REGISTRY_PROJECT}" | tee -a "${summary}"
echo "IMAGE_TAG=${IMAGE_TAG}" | tee -a "${summary}"
echo "SERVICES=${SERVICES}" | tee -a "${summary}"

for service in $(service_names); do
  image="$(service_image "${service}")"
  push_dir="${REPORT_DIR}/services/${service}/registry"
  push_log="${push_dir}/push.log"
  mkdir -p "${push_dir}"

  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    echo "ERROR: Docker image does not exist locally for service ${service}: ${image}" | tee -a "${summary}" >&2
    exit 1
  fi

  echo "Pushing service=${service} image=${image}" | tee -a "${summary}"
  if docker push "${image}" > "${push_log}" 2>&1; then
    cp "${push_log}" "${registry_root}/push-${service}.log"
    echo "Push completed for service=${service}" | tee -a "${summary}"
  else
    echo "ERROR: docker push failed for service ${service}. See ${push_log}" | tee -a "${summary}" >&2
    exit 1
  fi
done

echo "MSA service image push completed" | tee -a "${summary}"
