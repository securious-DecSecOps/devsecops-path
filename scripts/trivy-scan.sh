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

if ! command -v trivy >/dev/null 2>&1; then
  echo "ERROR: trivy is required but was not found in PATH." >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}/trivy"

json_report="${REPORT_DIR}/trivy/image-scan.json"
txt_report="${REPORT_DIR}/trivy/image-scan.txt"

echo "Running Trivy image scan for ${IMAGE}"

if ! trivy image --exit-code 0 --format json --output "${json_report}" "${IMAGE}"; then
  echo "ERROR: Trivy JSON scan failed for ${IMAGE}. Partial reports may remain in ${REPORT_DIR}/trivy." >&2
  exit 1
fi

if ! trivy image --exit-code 0 --format table --output "${txt_report}" "${IMAGE}"; then
  echo "ERROR: Trivy text scan failed for ${IMAGE}. JSON report is at ${json_report}." >&2
  exit 1
fi

echo "Trivy reports written:"
echo "- ${json_report}"
echo "- ${txt_report}"

