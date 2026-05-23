#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SERVICES="user-service,transaction-service,status-service,file-service,settings-service,frontend"
GATE_MAX_CRITICAL="${GATE_MAX_CRITICAL:-0}"
GATE_MAX_HIGH="${GATE_MAX_HIGH:-3}"
CHECKOV_MAX_CRITICAL="${CHECKOV_MAX_CRITICAL:-0}"
GITLEAKS_MAX_FINDINGS="${GITLEAKS_MAX_FINDINGS:-0}"

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

evaluate_trivy_report() {
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

severity_counts = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "UNKNOWN": 0}
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

evaluate_checkov_reports() {
  local checkov_dir="${REPORT_DIR}/checkov"
  python3 - "${checkov_dir}" "${CHECKOV_MAX_CRITICAL}" <<'PY'
import glob
import json
import os
import sys

checkov_dir = sys.argv[1]
max_critical = int(sys.argv[2])
files = sorted(glob.glob(os.path.join(checkov_dir, "*.json"))) if os.path.isdir(checkov_dir) else []
critical_count = 0
failed_count = 0
scan_error_count = 0
violations = []

def iter_failed_checks(data):
    if isinstance(data, list):
        for item in data:
            yield from iter_failed_checks(item)
    elif isinstance(data, dict):
        if "scan_error" in data:
            return
        results = data.get("results")
        if isinstance(results, dict):
            for check in results.get("failed_checks") or []:
                yield check
        for value in data.values():
            if isinstance(value, (dict, list)):
                yield from iter_failed_checks(value)

for path in files:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        scan_error_count += 1
        continue

    if isinstance(data, dict) and data.get("scan_error"):
        scan_error_count += 1
        continue

    for check in iter_failed_checks(data):
        failed_count += 1
        severity = str(
            check.get("severity")
            or (check.get("severity_details") or {}).get("severity")
            or "UNKNOWN"
        ).upper()
        if severity == "CRITICAL":
            critical_count += 1
            violations.append({
                "file": os.path.basename(path),
                "check_id": check.get("check_id", "unknown-check"),
                "check_name": check.get("check_name", ""),
                "resource": check.get("resource", ""),
                "file_path": check.get("file_path", ""),
            })

blocked = critical_count > max_critical
print(f"CHECKOV_REPORT_COUNT={len(files)}")
print(f"CHECKOV_FAILED_COUNT={failed_count}")
print(f"CHECKOV_CRITICAL_COUNT={critical_count}")
print(f"CHECKOV_SCAN_ERROR_COUNT={scan_error_count}")
print(f"CHECKOV_MAX_CRITICAL={max_critical}")
print(f"CHECKOV_GATE_RESULT={'BLOCK' if blocked else 'PASS'}")
if blocked:
    print("CHECKOV_VIOLATIONS_BEGIN")
    for item in violations[:50]:
        name = str(item["check_name"]).replace("\n", " ")[:180]
        print(
            f"- CRITICAL {item['check_id']} report={item['file']} "
            f"resource={item['resource']} file={item['file_path']} name={name}"
        )
    if len(violations) > 50:
        print(f"- additional_checkov_critical_findings={len(violations) - 50}")
    print("CHECKOV_VIOLATIONS_END")
PY
}

evaluate_gitleaks_reports() {
  local gitleaks_dir="${REPORT_DIR}/gitleaks"
  python3 - "${gitleaks_dir}" "${GITLEAKS_MAX_FINDINGS}" <<'PY'
import glob
import json
import os
import sys

gitleaks_dir = sys.argv[1]
max_findings = int(sys.argv[2])
files = sorted(glob.glob(os.path.join(gitleaks_dir, "*.json"))) if os.path.isdir(gitleaks_dir) else []
findings = []
scan_error_count = 0

for path in files:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        scan_error_count += 1
        continue

    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        continue

    for item in data:
        if isinstance(item, dict) and item.get("scan_error"):
            scan_error_count += 1
            continue
        if isinstance(item, dict):
            findings.append((os.path.basename(path), item))

blocked = len(findings) > max_findings
print(f"GITLEAKS_REPORT_COUNT={len(files)}")
print(f"GITLEAKS_FINDING_COUNT={len(findings)}")
print(f"GITLEAKS_SCAN_ERROR_COUNT={scan_error_count}")
print(f"GITLEAKS_MAX_FINDINGS={max_findings}")
print(f"GITLEAKS_GATE_RESULT={'BLOCK' if blocked else 'PASS'}")
if blocked:
    print("GITLEAKS_FINDINGS_BEGIN")
    for report, item in findings[:50]:
        rule = item.get("RuleID") or item.get("Rule") or "unknown-rule"
        file_path = item.get("File") or item.get("file") or ""
        line = item.get("StartLine") or item.get("Line") or ""
        desc = str(item.get("Description") or "").replace("\n", " ")[:180]
        print(f"- SECRET rule={rule} report={report} file={file_path} line={line} description={desc}")
    if len(findings) > 50:
        print(f"- additional_gitleaks_findings={len(findings) - 50}")
    print("GITLEAKS_FINDINGS_END")
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

for numeric_name in GATE_MAX_CRITICAL GATE_MAX_HIGH CHECKOV_MAX_CRITICAL GITLEAKS_MAX_FINDINGS; do
  if ! [[ "${!numeric_name}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: ${numeric_name} must be a non-negative integer: ${!numeric_name}" >&2
    exit 1
  fi
done

gate_root="${REPORT_DIR}/gate"
summary="${gate_root}/msa-gate-summary.txt"
aggregated="${gate_root}/aggregated-summary.txt"
compat_gate="${gate_root}/gate-result.txt"
mkdir -p "${gate_root}"
: > "${summary}"
: > "${aggregated}"

overall_result="PASS"
blocked_services=0
checkov_result="PASS"
gitleaks_result="PASS"

{
  echo "MSA Security Gate Policy"
  echo "SERVICES=${SERVICES}"
  echo "GATE_MAX_CRITICAL=${GATE_MAX_CRITICAL}"
  echo "GATE_MAX_HIGH=${GATE_MAX_HIGH}"
  echo "CHECKOV_MAX_CRITICAL=${CHECKOV_MAX_CRITICAL}"
  echo "GITLEAKS_MAX_FINDINGS=${GITLEAKS_MAX_FINDINGS}"
  echo "ENFORCE_GATE=${ENFORCE_GATE}"
} | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null

echo "TRIVY_RESULTS_BEGIN" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null
for service in $(service_names); do
  json_file="$(report_path_for_service "${service}")"
  gate_dir="${REPORT_DIR}/services/${service}/gate"
  gate_file="${gate_dir}/gate-result.txt"
  mkdir -p "${gate_dir}"

  if [[ -z "${json_file}" ]]; then
    echo "ERROR: Trivy JSON report not found for service ${service}" | tee -a "${summary}" >&2
    exit 1
  fi

  echo "Evaluating Trivy gate for service=${service} report=${json_file}" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null
  result_text="$(evaluate_trivy_report "${service}" "${json_file}")"
  printf '%s\n' "${result_text}" | tee "${gate_file}" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null

  service_result="$(printf '%s\n' "${result_text}" | awk -F= '$1 == "GATE_RESULT" { print $2; exit }')"
  if [[ "${service_result}" == "BLOCK" ]]; then
    overall_result="BLOCK"
    blocked_services=$((blocked_services + 1))
  fi
done
echo "TRIVY_RESULTS_END" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null

echo "CHECKOV_RESULTS_BEGIN" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null
checkov_text="$(evaluate_checkov_reports)"
printf '%s\n' "${checkov_text}" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null
checkov_result="$(printf '%s\n' "${checkov_text}" | awk -F= '$1 == "CHECKOV_GATE_RESULT" { print $2; exit }')"
if [[ "${checkov_result}" == "BLOCK" ]]; then
  overall_result="BLOCK"
fi
echo "CHECKOV_RESULTS_END" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null

echo "GITLEAKS_RESULTS_BEGIN" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null
gitleaks_text="$(evaluate_gitleaks_reports)"
printf '%s\n' "${gitleaks_text}" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null
gitleaks_result="$(printf '%s\n' "${gitleaks_text}" | awk -F= '$1 == "GITLEAKS_GATE_RESULT" { print $2; exit }')"
if [[ "${gitleaks_result}" == "BLOCK" ]]; then
  overall_result="BLOCK"
fi
echo "GITLEAKS_RESULTS_END" | tee -a "${summary}" | tee -a "${aggregated}" >/dev/null

{
  echo "OVERALL_GATE_RESULT=${overall_result}"
  echo "BLOCKED_SERVICE_COUNT=${blocked_services}"
  echo "CHECKOV_GATE_RESULT=${checkov_result}"
  echo "GITLEAKS_GATE_RESULT=${gitleaks_result}"
  echo "AGGREGATED_SUMMARY_FILE=${aggregated}"
} | tee -a "${summary}" | tee -a "${aggregated}"

{
  echo "GATE_STATUS=${overall_result}"
  echo "OVERALL_GATE_RESULT=${overall_result}"
  echo "BLOCKED_SERVICE_COUNT=${blocked_services}"
  echo "CHECKOV_GATE_RESULT=${checkov_result}"
  echo "GITLEAKS_GATE_RESULT=${gitleaks_result}"
  echo "GATE_MAX_CRITICAL=${GATE_MAX_CRITICAL}"
  echo "GATE_MAX_HIGH=${GATE_MAX_HIGH}"
  echo "CHECKOV_MAX_CRITICAL=${CHECKOV_MAX_CRITICAL}"
  echo "GITLEAKS_MAX_FINDINGS=${GITLEAKS_MAX_FINDINGS}"
  echo "ENFORCE_GATE=${ENFORCE_GATE}"
  echo "SUMMARY_FILE=${summary}"
  echo "AGGREGATED_SUMMARY_FILE=${aggregated}"
} > "${compat_gate}"

if [[ "${overall_result}" == "BLOCK" ]]; then
  if [[ "${ENFORCE_GATE}" == "true" ]]; then
    echo "ERROR: MSA security gate blocked this build before registry push." >&2
    echo "ERROR: See ${summary} and ${aggregated} for details." >&2
    exit 1
  else
    echo "WARN: MSA security gate result is BLOCK, but ENFORCE_GATE=${ENFORCE_GATE} allows continuation." >&2
    echo "WARN: See ${summary} and ${aggregated} for details. Findings are recorded in the build evidence." >&2
  fi
fi

echo "MSA security gate evaluation complete (result=${overall_result}, enforce=${ENFORCE_GATE})."
