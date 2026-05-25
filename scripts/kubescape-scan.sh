#!/usr/bin/env bash
set -euo pipefail

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

ensure_kubescape() {
  export PATH="${HOME}/.local/bin:${PATH}"
  if command -v kubescape >/dev/null 2>&1; then
    return 0
  fi

  require_cmd curl

  # Kubescape release asset naming: kubescape_<version>_linux_amd64.tar.gz
  # (이전의 kubescape-ubuntu-latest 패턴은 deprecated, 404 발생)
  # latest tag를 API로 조회 후 정확한 tar.gz URL을 구성한다. 네트워크 차단 환경 대비
  # KUBESCAPE_VERSION env 변수로 override 가능 (예: v4.0.8).
  local version="${KUBESCAPE_VERSION:-}"
  if [[ -z "${version}" ]]; then
    version="$(curl -fsSL https://api.github.com/repos/kubescape/kubescape/releases/latest \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)"
  fi
  if [[ -z "${version}" ]]; then
    version="v4.0.8"  # PoC 시점 검증된 버전 — API 호출 실패 시 fallback
    echo "WARN: kubescape latest version 조회 실패, fallback ${version} 사용"
  fi
  local version_num="${version#v}"
  local arch="amd64"
  case "$(uname -m)" in
    aarch64|arm64) arch="arm64" ;;
  esac

  local asset="kubescape_${version_num}_linux_${arch}.tar.gz"
  local url="https://github.com/kubescape/kubescape/releases/download/${version}/${asset}"
  local tmp_tar="/tmp/${asset}"
  local tmp_dir="/tmp/kubescape-extract"

  echo "kubescape command not found; installing ${version} (${arch}) from ${url}"
  if ! curl -fsSL "${url}" -o "${tmp_tar}"; then
    echo "ERROR: failed to download kubescape tarball from ${url}" >&2
    return 1
  fi

  rm -rf "${tmp_dir}" && mkdir -p "${tmp_dir}"
  if ! tar -xzf "${tmp_tar}" -C "${tmp_dir}"; then
    echo "ERROR: failed to extract ${tmp_tar}" >&2
    rm -f "${tmp_tar}"
    return 1
  fi
  rm -f "${tmp_tar}"

  # tarball 안에 kubescape 바이너리가 있다. 디렉토리 구조가 버전마다 다를 수 있으니 find로 위치 확인.
  local bin_path
  bin_path="$(find "${tmp_dir}" -type f -name "kubescape" -perm -u+x 2>/dev/null | head -1)"
  if [[ -z "${bin_path}" ]]; then
    bin_path="$(find "${tmp_dir}" -type f -name "kubescape" 2>/dev/null | head -1)"
  fi
  if [[ -z "${bin_path}" || ! -f "${bin_path}" ]]; then
    echo "ERROR: extracted tarball does not contain kubescape binary" >&2
    ls -la "${tmp_dir}" >&2 || true
    return 1
  fi
  chmod 755 "${bin_path}"

  if [[ -w /usr/local/bin ]]; then
    mv "${bin_path}" /usr/local/bin/kubescape
  else
    mkdir -p "${HOME}/.local/bin"
    mv "${bin_path}" "${HOME}/.local/bin/kubescape"
  fi
  rm -rf "${tmp_dir}"

  command -v kubescape >/dev/null 2>&1
}

framework_name() {
  local preferred="$1"
  local fallback="$2"
  local frameworks_file="$3"
  if grep -qE "(^|[[:space:]])${preferred}($|[[:space:]])" "${frameworks_file}" 2>/dev/null; then
    echo "${preferred}"
  elif [[ -n "${fallback}" ]] && grep -qE "(^|[[:space:]])${fallback}($|[[:space:]])" "${frameworks_file}" 2>/dev/null; then
    echo "${fallback}"
  else
    echo "${preferred}"
  fi
}

run_framework_scan() {
  local label="$1"
  local framework="$2"
  local output_json="$3"
  local output_err="$4"
  local status_file="$5"
  local status

  echo "Running Kubescape framework scan label=${label} framework=${framework} chart=${HELM_CHART_DIR}"
  set +e
  kubescape scan framework "${framework}" "${HELM_CHART_DIR}" --format json --output "${output_json}" >"${output_err}" 2>&1
  status=$?
  set -e

  echo "kubescape_exit_code=${status}" > "${status_file}"
  if [[ ! -s "${output_json}" ]]; then
    python3 - "${output_json}" "${label}" "${framework}" "${status}" <<'PY'
import json
import sys

path, label, framework, status = sys.argv[1:]
with open(path, "w", encoding="utf-8") as fh:
    json.dump({
        "scan_error": "kubescape produced no JSON output",
        "label": label,
        "framework": framework,
        "exit_code": int(status),
    }, fh, indent=2)
    fh.write("\n")
PY
  fi

  return 0
}

write_summary() {
  local summary_file="$1"
  shift
  python3 - "${summary_file}" "$@" <<'PY'
import json
import os
import sys

summary_file = sys.argv[1]
items = sys.argv[2:]

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)

def count_framework(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        return {"error": str(exc), "total": 0, "passed": 0, "failed": 0, "resources": 0}

    if isinstance(data, dict) and data.get("scan_error"):
        return {"error": data.get("scan_error"), "total": 0, "passed": 0, "failed": 0, "resources": 0}

    controls = {}
    failed = 0
    passed = 0
    resources = set()

    for node in walk(data):
        kind = node.get("kind") or node.get("resourceKind")
        metadata = node.get("metadata") if isinstance(node.get("metadata"), dict) else {}
        name = metadata.get("name") or node.get("name") or node.get("resourceName")
        namespace = metadata.get("namespace") or node.get("namespace") or ""
        if kind and name:
            resources.add((str(namespace), str(kind), str(name)))

        control_id = node.get("controlID") or node.get("controlId") or node.get("id")
        control_name = node.get("controlName") or node.get("name")
        status = node.get("status") or node.get("scoreFactorStatus") or node.get("complianceStatus")
        if control_id and control_name and status is not None:
            controls[str(control_id)] = str(status).lower()

    for status_text in controls.values():
        if any(token in status_text for token in ("fail", "failed", "warning")):
            failed += 1
        elif any(token in status_text for token in ("pass", "passed")):
            passed += 1

    total = len(controls)

    if total == 0:
        for node in walk(data):
            if not isinstance(node, dict):
                continue
            if "failedControls" in node or "passedControls" in node:
                try:
                    failed = max(failed, int(node.get("failedControls", 0) or 0))
                    passed = max(passed, int(node.get("passedControls", 0) or 0))
                    total = max(total, failed + passed)
                except Exception:
                    pass

    return {"error": "", "total": total, "passed": passed, "failed": failed, "resources": len(resources)}

lines = ["Kubescape scan summary"]
for item in items:
    label, framework, path, err_path, meta_path = item.split("|", 4)
    result = count_framework(path)
    exit_code = "unknown"
    if os.path.exists(meta_path):
        with open(meta_path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("kubescape_exit_code="):
                    exit_code = line.strip().split("=", 1)[1]
                    break
    if result["error"]:
        lines.append(f"{label}: framework={framework}, exit={exit_code}, error={result['error']}, file={path}")
    else:
        lines.append(
            f"{label}: framework={framework}, exit={exit_code}, "
            f"passed={result['passed']}/{result['total']} controls, "
            f"failed={result['failed']}, resources={result['resources']}, file={path}"
        )
    if os.path.exists(err_path) and os.path.getsize(err_path) > 0:
        lines.append(f"  stderr: {err_path}")

with open(summary_file, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))
    fh.write("\n")
print("\n".join(lines))
PY
}

require_env HELM_CHART_DIR
require_env REPORT_DIR
require_cmd python3

kubescape_dir="${REPORT_DIR}/kubescape"
mkdir -p "${kubescape_dir}"

if [[ ! -d "${HELM_CHART_DIR}" ]]; then
  echo "ERROR: HELM_CHART_DIR does not exist: ${HELM_CHART_DIR}" >&2
  exit 1
fi

if ! ensure_kubescape; then
  echo "ERROR: kubescape installation failed." >&2
  exit 1
fi

kubescape version > "${kubescape_dir}/kubescape-version.txt" 2>&1 || true
kubescape list frameworks > "${kubescape_dir}/frameworks.txt" 2>&1 || true

nsa_framework="$(framework_name nsa nsa-cisa "${kubescape_dir}/frameworks.txt")"
mitre_framework="$(framework_name mitre mitre-attack "${kubescape_dir}/frameworks.txt")"
cis_framework="$(framework_name cis-v1.12.0 cis-v1.10.0 "${kubescape_dir}/frameworks.txt")"

run_framework_scan "NSA" "${nsa_framework}" "${kubescape_dir}/nsa.json" "${kubescape_dir}/nsa.err" "${kubescape_dir}/nsa.meta"
run_framework_scan "MITRE" "${mitre_framework}" "${kubescape_dir}/mitre.json" "${kubescape_dir}/mitre.err" "${kubescape_dir}/mitre.meta"
run_framework_scan "CIS" "${cis_framework}" "${kubescape_dir}/cis.json" "${kubescape_dir}/cis.err" "${kubescape_dir}/cis.meta"

write_summary \
  "${kubescape_dir}/kubescape-summary.txt" \
  "NSA|${nsa_framework}|${kubescape_dir}/nsa.json|${kubescape_dir}/nsa.err|${kubescape_dir}/nsa.meta" \
  "MITRE|${mitre_framework}|${kubescape_dir}/mitre.json|${kubescape_dir}/mitre.err|${kubescape_dir}/mitre.meta" \
  "CIS|${cis_framework}|${kubescape_dir}/cis.json|${kubescape_dir}/cis.err|${kubescape_dir}/cis.meta"

echo "Kubescape scan artifacts written to ${kubescape_dir}"
exit 0
