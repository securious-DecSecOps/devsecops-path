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

image_digest() {
  local image="$1"
  docker image inspect --format='{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}{{.Id}}{{end}}' "${image}" 2>/dev/null || true
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

sbom_root="${REPORT_DIR}/sbom"
summary_file="${sbom_root}/sbom-summary.txt"
mkdir -p "${sbom_root}"
: > "${summary_file}"

echo "SBOM generation started" | tee -a "${summary_file}"
echo "APP_NAME=${APP_NAME}" | tee -a "${summary_file}"
echo "REGISTRY_URL=${REGISTRY_URL}" | tee -a "${summary_file}"
echo "REGISTRY_PROJECT=${REGISTRY_PROJECT}" | tee -a "${summary_file}"
echo "IMAGE_TAG=${IMAGE_TAG}" | tee -a "${summary_file}"
echo "SERVICES=${SERVICES}" | tee -a "${summary_file}"
echo "Formats: SPDX (ISO standard) + CycloneDX (Dependency-Track compatible)" | tee -a "${summary_file}"
echo "" | tee -a "${summary_file}"

for service in $(service_names); do
  image="$(service_image "${service}")"
  service_safe="$(safe_name "${service}")"
  service_sbom_dir="${REPORT_DIR}/services/${service}/sbom"
  spdx_file="${sbom_root}/${service_safe}.spdx.json"
  cdx_file="${sbom_root}/${service_safe}.cdx.json"
  sbom_error="${sbom_root}/${service_safe}.err"

  mkdir -p "${service_sbom_dir}"

  echo "Generating SBOM service=${service} image=${image}" | tee -a "${summary_file}"

  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    echo "ERROR: Docker image does not exist locally for service ${service}: ${image}" | tee -a "${summary_file}" >&2
    exit 1
  fi

  digest="$(image_digest "${image}")"
  if [[ -n "${digest}" ]]; then
    echo "  image digest: ${digest}" | tee -a "${summary_file}"
  fi

  if ! trivy image \
      --no-progress \
      --format spdx-json \
      --output "${spdx_file}" \
      "${image}" > "${sbom_error}" 2>&1; then
    echo "ERROR: Trivy SPDX SBOM generation failed for ${service}. See ${sbom_error}" | tee -a "${summary_file}" >&2
    exit 1
  fi

  if ! trivy image \
      --no-progress \
      --format cyclonedx \
      --output "${cdx_file}" \
      "${image}" >> "${sbom_error}" 2>&1; then
    echo "ERROR: Trivy CycloneDX SBOM generation failed for ${service}. See ${sbom_error}" | tee -a "${summary_file}" >&2
    exit 1
  fi

  cp "${spdx_file}" "${service_sbom_dir}/sbom.spdx.json"
  cp "${cdx_file}" "${service_sbom_dir}/sbom.cdx.json"

  if command -v python3 >/dev/null 2>&1; then
    pkg_count="$(python3 - "${spdx_file}" <<'PY' 2>/dev/null || echo "?"
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    print(len(d.get("packages", [])))
except Exception:
    print("?")
PY
)"
    echo "  SPDX packages: ${pkg_count}" | tee -a "${summary_file}"
  fi

  echo "  SPDX:      ${spdx_file}" | tee -a "${summary_file}"
  echo "  CycloneDX: ${cdx_file}" | tee -a "${summary_file}"
  echo "" | tee -a "${summary_file}"
done

echo "SBOM generation completed" | tee -a "${summary_file}"
echo "SBOM artifacts root: ${sbom_root}" | tee -a "${summary_file}"
