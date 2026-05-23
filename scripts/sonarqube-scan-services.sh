#!/usr/bin/env bash
set -euo pipefail

SONAR_SCANNER_VERSION="${SONAR_SCANNER_VERSION:-7.2.0.5079}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-vulnbank-msa}"
SONAR_HOST_URL="${SONAR_HOST_URL:-http://sonarqube:9000}"
SONAR_QUALITY_GATE_TIMEOUT_SECONDS="${SONAR_QUALITY_GATE_TIMEOUT_SECONDS:-60}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

ensure_local_bin() {
  mkdir -p "${HOME}/.local/bin" "${HOME}/.local/sonar"
  export PATH="${HOME}/.local/bin:${PATH}"
}

# sonar-scanner needs a JRE. The Jenkins LTS-jdk17 image ships JDK at
# /opt/java/openjdk but Jenkins sh-steps don't always export JAVA_HOME.
# Detect a usable java and export both PATH + JAVA_HOME for sonar-scanner.
ensure_java() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    export PATH="${JAVA_HOME}/bin:${PATH}"
    return 0
  fi
  local candidate
  for candidate in /opt/java/openjdk /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/default-java; do
    if [[ -x "${candidate}/bin/java" ]]; then
      export JAVA_HOME="${candidate}"
      export PATH="${candidate}/bin:${PATH}"
      return 0
    fi
  done
  if command -v java >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: java runtime not found. sonar-scanner requires a JRE." >&2
  return 1
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "x64" ;;
  esac
}

ensure_sonar_scanner() {
  ensure_local_bin
  if command -v sonar-scanner >/dev/null 2>&1; then
    # Even when the scanner is already cached, re-assert exec bits. Past builds
    # extracted the embedded JRE without preserving Unix perms, and a workspace
    # cleanup elsewhere can also strip x-bits. This is a 1-second safety net.
    local scanner_path
    scanner_path="$(command -v sonar-scanner)"
    local scanner_real
    scanner_real="$(readlink -f "${scanner_path}" 2>/dev/null || echo "${scanner_path}")"
    local scanner_root
    scanner_root="$(dirname "$(dirname "${scanner_real}")")"
    if [[ -d "${scanner_root}/bin" ]]; then
      chmod +x "${scanner_root}/bin/"* 2>/dev/null || true
    fi
    if [[ -d "${scanner_root}/jre/bin" ]]; then
      chmod +x "${scanner_root}/jre/bin/"* 2>/dev/null || true
    fi
    return 0
  fi

  local arch
  local file_name
  local url
  local zip_path
  local install_dir
  arch="$(detect_arch)"
  # SonarSource zip filename uses "sonar-scanner-cli-<ver>-linux-<arch>.zip"
  # but starting from 7.x the directory inside the zip is named WITHOUT the
  # "-cli-" segment (just "sonar-scanner-<ver>-linux-<arch>"). Detect the
  # extracted dir name from the zip's first entry instead of guessing.
  file_name="sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-${arch}"
  url="${SONAR_SCANNER_URL:-https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/${file_name}.zip}"
  zip_path="${HOME}/.local/sonar/${file_name}.zip"

  if [[ ! -f "${zip_path}" ]]; then
    if command -v wget >/dev/null 2>&1; then
      wget -q -O "${zip_path}" "${url}"
    elif command -v curl >/dev/null 2>&1; then
      curl -fsSL -o "${zip_path}" "${url}"
    else
      echo "ERROR: wget or curl is required to install sonar-scanner." >&2
      return 1
    fi
  fi

  # Resolve the actual top-level directory inside the zip (it differs per
  # SonarSource release: 6.x = sonar-scanner-cli-*, 7.x = sonar-scanner-*).
  install_dir_name="$(python3 - "${zip_path}" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as zf:
    names = zf.namelist()
top_dirs = {n.split("/", 1)[0] for n in names if "/" in n}
top_dirs.discard("")
# Prefer one that contains "sonar-scanner".
candidates = sorted(d for d in top_dirs if "sonar-scanner" in d)
print(candidates[0] if candidates else "")
PY
)"
  if [[ -z "${install_dir_name}" ]]; then
    echo "ERROR: could not determine sonar-scanner top-level dir from zip ${zip_path}" >&2
    return 1
  fi
  install_dir="${HOME}/.local/sonar/${install_dir_name}"

  if [[ ! -x "${install_dir}/bin/sonar-scanner" ]]; then
    # Prefer `unzip` CLI if available: it preserves Unix perms reliably and
    # handles JRE binaries (java launcher, jspawnhelper, .so libs) correctly.
    # Python zipfile.extractall() lost x-bit on JRE binaries and even after
    # an explicit chmod, sonar-scanner's ProcessBuilder still failed with
    # EACCES on the extracted java — likely missed files/links.
    if command -v unzip >/dev/null 2>&1; then
      ( cd "${HOME}/.local/sonar" && unzip -q -o "${zip_path}" )
    else
      python3 - "${zip_path}" "${HOME}/.local/sonar" <<'PY'
import os
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as zf:
    for info in zf.infolist():
        out_path = zf.extract(info, sys.argv[2])
        if info.is_dir():
            continue
        mode = (info.external_attr >> 16) & 0xFFFF
        if mode:
            try:
                os.chmod(out_path, mode)
            except OSError:
                pass
PY
    fi
    # Safety net: ensure key binaries are executable even if zip metadata lied.
    chmod +x "${install_dir}/bin/sonar-scanner" 2>/dev/null || true
    if [[ -d "${install_dir}/jre/bin" ]]; then
      chmod +x "${install_dir}/jre/bin/"* 2>/dev/null || true
    fi
    if [[ -f "${install_dir}/jre/lib/jspawnhelper" ]]; then
      chmod +x "${install_dir}/jre/lib/jspawnhelper" 2>/dev/null || true
    fi
  fi

  if [[ ! -x "${install_dir}/bin/sonar-scanner" ]]; then
    echo "ERROR: sonar-scanner binary not found at ${install_dir}/bin/sonar-scanner after extract" >&2
    return 1
  fi

  ln -sfn "${install_dir}/bin/sonar-scanner" "${HOME}/.local/bin/sonar-scanner"
  command -v sonar-scanner >/dev/null 2>&1
}

write_status() {
  local status_file="$1"
  shift
  printf '%s\n' "$@" | tee -a "${status_file}"
}

quality_gate_poll() {
  local report_task_file="$1"
  local status_file="$2"
  python3 - "${report_task_file}" "${status_file}" "${SONAR_TOKEN}" "${SONAR_QUALITY_GATE_TIMEOUT_SECONDS}" <<'PY'
import base64
import json
import sys
import time
import urllib.parse
import urllib.request

report_task_file, status_file, token, timeout_s = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
props = {}
with open(report_task_file, "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if "=" in line:
            key, value = line.split("=", 1)
            props[key] = value

ce_task_url = props.get("ceTaskUrl")
server_url = props.get("serverUrl")
project_key = props.get("projectKey")
if not ce_task_url or not server_url:
    raise SystemExit("report-task.txt did not include ceTaskUrl/serverUrl")

auth = base64.b64encode((token + ":").encode()).decode()

def get_json(url):
    req = urllib.request.Request(url, headers={"Authorization": "Basic " + auth})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode())

deadline = time.time() + timeout_s
analysis_id = None
ce_status = "UNKNOWN"
while time.time() < deadline:
    data = get_json(ce_task_url)
    task = data.get("task", {})
    ce_status = task.get("status", "UNKNOWN")
    if ce_status in ("SUCCESS", "FAILED", "CANCELED"):
        analysis_id = task.get("analysisId")
        break
    time.sleep(5)

with open(status_file, "a", encoding="utf-8") as fh:
    fh.write(f"CE_TASK_STATUS={ce_status}\n")
    if analysis_id:
        fh.write(f"ANALYSIS_ID={analysis_id}\n")

if ce_status != "SUCCESS" or not analysis_id:
    raise SystemExit(f"SonarQube CE task did not finish successfully: {ce_status}")

query = urllib.parse.urlencode({"analysisId": analysis_id})
qg = get_json(server_url.rstrip("/") + "/api/qualitygates/project_status?" + query)
project_status = qg.get("projectStatus", {})
gate_status = project_status.get("status", "UNKNOWN")

with open(status_file, "a", encoding="utf-8") as fh:
    fh.write(f"QUALITY_GATE_STATUS={gate_status}\n")
    fh.write(f"PROJECT_KEY={project_key or ''}\n")
    fh.write(json.dumps(project_status, indent=2) + "\n")

if gate_status != "OK":
    raise SystemExit(f"SonarQube quality gate status is {gate_status}")
PY
}

require_env REPORT_DIR
require_env MSA_WORKLOAD_DIR

sonar_dir="${REPORT_DIR}/sonarqube"
status_file="${sonar_dir}/sonarqube-status.txt"
mkdir -p "${sonar_dir}"
: > "${status_file}"

write_status "${status_file}" \
  "SONAR_HOST_URL=${SONAR_HOST_URL}" \
  "SONAR_PROJECT_KEY=${SONAR_PROJECT_KEY}" \
  "ENFORCE_GATE=${ENFORCE_GATE:-false}"

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  write_status "${status_file}" "SONAR_SCAN_RESULT=SKIPPED" "SKIP_REASON=SONAR_TOKEN is empty"
  echo "WARN: SONAR_TOKEN is empty; skipping SonarQube scan." >&2
  exit 0
fi

if ! ensure_java; then
  write_status "${status_file}" "SONAR_SCAN_RESULT=JAVA_MISSING"
  if [[ "${ENFORCE_GATE:-false}" == "true" ]]; then
    exit 1
  fi
  echo "WARN: java runtime missing; continuing because ENFORCE_GATE=${ENFORCE_GATE:-false}." >&2
  exit 0
fi

if ! ensure_sonar_scanner; then
  write_status "${status_file}" "SONAR_SCAN_RESULT=INSTALL_FAILED"
  if [[ "${ENFORCE_GATE:-false}" == "true" ]]; then
    exit 1
  fi
  echo "WARN: sonar-scanner installation failed; continuing because ENFORCE_GATE=${ENFORCE_GATE:-false}." >&2
  exit 0
fi

project_file="${sonar_dir}/sonar-project.properties"
work_dir="${sonar_dir}/.scannerwork"
mkdir -p "${work_dir}"

cat > "${project_file}" <<EOF
sonar.projectKey=${SONAR_PROJECT_KEY}
sonar.projectName=VulnBank MSA
sonar.projectVersion=${IMAGE_TAG:-dev}
sonar.sources=${MSA_WORKLOAD_DIR}/services,scripts,bootstrap/local-wsl
sonar.exclusions=**/vendor/**,**/node_modules/**,**/reports/**,**/.git/**
sonar.sourceEncoding=UTF-8
sonar.host.url=${SONAR_HOST_URL}
sonar.working.directory=${work_dir}
# Skip JRE auto-provisioning from the SonarQube server. The scanner ships with
# its own embedded JRE which we chmod'd correctly in ensure_sonar_scanner.
# Without this flag, scanner downloads JRE into ~/.sonar/cache and the
# extracted java loses Unix exec bits (same root cause as the scanner zip).
sonar.scanner.skipJreProvisioning=true
EOF

scanner_log="${sonar_dir}/sonar-scanner.log"
if SONAR_TOKEN="${SONAR_TOKEN}" sonar-scanner \
  -Dproject.settings="${project_file}" \
  -Dsonar.scanner.skipJreProvisioning=true \
  -Dsonar.token="${SONAR_TOKEN}" > "${scanner_log}" 2>&1; then
  write_status "${status_file}" "SONAR_SCAN_RESULT=SCAN_SUBMITTED"
else
  write_status "${status_file}" "SONAR_SCAN_RESULT=SCAN_FAILED" "SCANNER_LOG=${scanner_log}"
  if [[ "${ENFORCE_GATE:-false}" == "true" ]]; then
    sed -n '1,220p' "${scanner_log}" >&2
    exit 1
  fi
  echo "WARN: sonar-scanner failed; continuing because ENFORCE_GATE=${ENFORCE_GATE:-false}. See ${scanner_log}" >&2
  exit 0
fi

report_task_file="${work_dir}/report-task.txt"
if [[ ! -f "${report_task_file}" ]]; then
  write_status "${status_file}" "SONAR_QUALITY_GATE_RESULT=UNKNOWN" "REASON=report-task.txt not found"
  if [[ "${ENFORCE_GATE:-false}" == "true" ]]; then
    exit 1
  fi
  echo "WARN: SonarQube report-task.txt not found; continuing because ENFORCE_GATE=${ENFORCE_GATE:-false}." >&2
  exit 0
fi

if quality_gate_poll "${report_task_file}" "${status_file}"; then
  write_status "${status_file}" "SONAR_QUALITY_GATE_RESULT=PASS"
else
  write_status "${status_file}" "SONAR_QUALITY_GATE_RESULT=BLOCK"
  if [[ "${ENFORCE_GATE:-false}" == "true" ]]; then
    exit 1
  fi
  echo "WARN: SonarQube quality gate blocked, but ENFORCE_GATE=${ENFORCE_GATE:-false} allows continuation." >&2
fi

echo "SonarQube scan artifacts written to ${sonar_dir}"
exit 0
