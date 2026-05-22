#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

count_severity() {
  local severity="$1"
  local report="$2"

  if command -v jq >/dev/null 2>&1; then
    jq --arg severity "${severity}" '[.Results[]? | .Vulnerabilities[]? | select(.Severity == $severity)] | length' "${report}"
  else
    python3 - "${severity}" "${report}" <<'PY'
import json
import sys

severity = sys.argv[1]
path = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

count = 0
for result in data.get("Results", []) or []:
    for vuln in result.get("Vulnerabilities", []) or []:
        if vuln.get("Severity") == severity:
            count += 1
print(count)
PY
  fi
}

require_env REPORT_DIR

ENFORCE_GATE="${ENFORCE_GATE:-false}"
scan_report="${REPORT_DIR}/trivy/image-scan.json"
gate_report="${REPORT_DIR}/gate/gate-result.txt"

if [[ ! -f "${scan_report}" ]]; then
  echo "ERROR: Trivy JSON report not found: ${scan_report}" >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}/gate"

critical_count="$(count_severity CRITICAL "${scan_report}")"
high_count="$(count_severity HIGH "${scan_report}")"

if [[ "${critical_count}" -gt 0 ]]; then
  gate_status="BLOCK"
else
  gate_status="PASS"
fi

{
  echo "GATE_STATUS=${gate_status}"
  echo "CRITICAL_COUNT=${critical_count}"
  echo "HIGH_COUNT=${high_count}"
  echo "HIGH_POLICY=WARN_ACCEPTED_RISK_IN_V1"
  echo "ENFORCE_GATE=${ENFORCE_GATE}"
  echo "SCAN_REPORT=${scan_report}"
} | tee "${gate_report}"

if [[ "${gate_status}" == "BLOCK" && "${ENFORCE_GATE}" == "true" ]]; then
  echo "ERROR: Security gate blocked this build and ENFORCE_GATE=true." >&2
  exit 1
fi

if [[ "${gate_status}" == "BLOCK" ]]; then
  echo "WARN: Security gate result is BLOCK, but ENFORCE_GATE=${ENFORCE_GATE}; continuing." >&2
fi

