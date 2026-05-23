#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SERVICES="user-service,transaction-service,status-service,file-service,settings-service,frontend"
GATE_MAX_CRITICAL="${GATE_MAX_CRITICAL:-0}"
GATE_MAX_HIGH="${GATE_MAX_HIGH:-3}"

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

safe_name() {
  local value="$1"
  value="${value//[^a-zA-Z0-9_.-]/-}"
  echo "${value}"
}

report_path_for_service() {
  local service="$1"
  local service_safe
  service_safe="$(safe_name "${service}")"
  local central="${REPORT_DIR}/trivy/trivy-report-${service_safe}.json"
  local nested="${REPORT_DIR}/services/${service}/trivy/image-scan.json"
  if [[ -f "${central}" ]]; then
    echo "${central}"
  elif [[ -f "${nested}" ]]; then
    echo "${nested}"
  else
    echo ""
  fi
}

evaluate_report() {
  local service="$1"
  local json_file="$2"
  python3 - "${service}" "${json_file}" "${GATE_MAX_CRITICAL}" "${GATE_MAX_HIGH}" <<'PY'
import json
import sys

service = sys.argv[1]
path = sys.argv[2]
max_critical = int(sys.argv[3])
max_high = int(sys.argv[4])

with open(path, "r", encoding="utf-8") as fh:
    report = json.load(fh)

severity_counts = {
    "CRITICAL": 0,
    "HIGH": 0,
    "MEDIUM": 0,
    "LOW": 0,
    "UNKNOWN": 0,
}
violations = []

for result in report.get("Results", []) or []:
    target = result.get("Target", "unknown-target")
    for vuln in result.get("Vulnerabilities") or []:
        severity = str(vuln.get("Severity", "UNKNOWN")).upper()
        severity_counts[severity] = severity_counts.get(severity, 0) + 1
        if severity in ("CRITICAL", "HIGH"):
            violations.append({
                "severity": severity,
                "id": vuln.get("VulnerabilityID", "unknown-cve"),
                "package": vuln.get("PkgName", "unknown-package"),
                "installed": vuln.get("InstalledVersion", ""),
                "fixed": vuln.get("FixedVersion", ""),
                "target": target,
                "title": vuln.get("Title", ""),
            })

critical = severity_counts.get("CRITICAL", 0)
high = severity_counts.get("HIGH", 0)
blocked = critical > max_critical or high > max_high

print(f"SERVICE={service}")
print(f"REPORT={path}")
print(f"CRITICAL_COUNT={critical}")
print(f"HIGH_COUNT={high}")
print(f"MEDIUM_COUNT={severity_counts.get('MEDIUM', 0)}")
print(f"LOW_COUNT={severity_counts.get('LOW', 0)}")
print(f"UNKNOWN_COUNT={severity_counts.get('UNKNOWN', 0)}")
print(f"MAX_CRITICAL={max_critical}")
print(f"MAX_HIGH={max_high}")
print(f"GATE_RESULT={'BLOCK' if blocked else 'PASS'}")

if blocked:
    print("BLOCK_REASONS_BEGIN")
    if critical > max_critical:
        print(f"- CRITICAL_COUNT {critical} exceeds allowed maximum {max_critical}")
    if high > max_high:
        print(f"- HIGH_COUNT {high} exceeds allowed maximum {max_high}")
    print("BLOCK_REASONS_END")
    print("VIOLATIONS_BEGIN")
    for item in violations[:50]:
        fixed = item["fixed"] if item["fixed"] else "not-fixed-or-unknown"
        title = item["title"].replace("\n", " ")[:180]
        print(
            f"- {item['severity']} {item['id']} service={service} "
            f"target={item['target']} package={item['package']} "
            f"installed={item['installed']} fixed={fixed} title={title}"
        )
    if len(violations) > 50:
        print(f"- additional_high_or_critical_findings={len(violations) - 50}")
    print("VIOLATIONS_END")
PY
}

require_env REPORT_DIR
require_cmd python3

SERVICES="${SERVICES:-${DEFAULT_SERVICES}}"
ENFORCE_GATE="${ENFORCE_GATE:-true}"

if [[ -z "$(service_names)" ]]; then
  echo "ERROR: SERVICES did not contain any valid service names." >&2
  exit 1
fi

if ! [[ "${GATE_MAX_CRITICAL}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: GATE_MAX_CRITICAL must be a non-negative integer: ${GATE_MAX_CRITICAL}" >&2
  exit 1
fi

if ! [[ "${GATE_MAX_HIGH}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: GATE_MAX_HIGH must be a non-negative integer: ${GATE_MAX_HIGH}" >&2
  exit 1
fi

gate_root="${REPORT_DIR}/gate"
summary="${gate_root}/msa-gate-summary.txt"
compat_gate="${gate_root}/gate-result.txt"
mkdir -p "${gate_root}"
: > "${summary}"

overall_result="PASS"
blocked_services=0

{
  echo "MSA Security Gate Policy"
  echo "SERVICES=${SERVICES}"
  echo "GATE_MAX_CRITICAL=${GATE_MAX_CRITICAL}"
  echo "GATE_MAX_HIGH=${GATE_MAX_HIGH}"
  echo "ENFORCE_GATE=${ENFORCE_GATE}"
} | tee -a "${summary}"

for service in $(service_names); do
  json_file="$(report_path_for_service "${service}")"
  gate_dir="${REPORT_DIR}/services/${service}/gate"
  gate_file="${gate_dir}/gate-result.txt"
  mkdir -p "${gate_dir}"

  if [[ -z "${json_file}" ]]; then
    echo "ERROR: Trivy JSON report not found for service ${service}" | tee -a "${summary}" >&2
    exit 1
  fi

  echo "Evaluating security gate for service=${service} report=${json_file}" | tee -a "${summary}"
  result_text="$(evaluate_report "${service}" "${json_file}")"
  printf '%s\n' "${result_text}" | tee "${gate_file}" | tee -a "${summary}"

  service_result="$(printf '%s\n' "${result_text}" | awk -F= '$1 == "GATE_RESULT" { print $2; exit }')"
  if [[ "${service_result}" == "BLOCK" ]]; then
    overall_result="BLOCK"
    blocked_services=$((blocked_services + 1))
  fi
done

{
  echo "OVERALL_GATE_RESULT=${overall_result}"
  echo "BLOCKED_SERVICE_COUNT=${blocked_services}"
} | tee -a "${summary}"

{
  echo "GATE_STATUS=${overall_result}"
  echo "OVERALL_GATE_RESULT=${overall_result}"
  echo "BLOCKED_SERVICE_COUNT=${blocked_services}"
  echo "GATE_MAX_CRITICAL=${GATE_MAX_CRITICAL}"
  echo "GATE_MAX_HIGH=${GATE_MAX_HIGH}"
  echo "ENFORCE_GATE=${ENFORCE_GATE}"
  echo "SUMMARY_FILE=${summary}"
} > "${compat_gate}"

if [[ "${overall_result}" == "BLOCK" ]]; then
  if [[ "${ENFORCE_GATE}" == "true" ]]; then
    echo "ERROR: MSA security gate blocked this build before registry push." >&2
    echo "ERROR: See ${summary} for service-level details." >&2
    exit 1
  else
    echo "WARN: MSA security gate result is BLOCK, but ENFORCE_GATE=${ENFORCE_GATE} allows continuation." >&2
    echo "WARN: See ${summary} for service-level details. Findings are recorded in the build evidence." >&2
  fi
fi

echo "MSA security gate evaluation complete (result=${overall_result}, enforce=${ENFORCE_GATE})."
