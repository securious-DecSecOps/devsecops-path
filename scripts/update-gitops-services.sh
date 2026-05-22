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

service_names_csv() {
  local raw_services
  local service
  local output=""
  local raw="${SERVICES:-${DEFAULT_SERVICES}}"
  IFS=',' read -r -a raw_services <<< "${raw}"
  for service in "${raw_services[@]}"; do
    service="${service//[[:space:]]/}"
    if [[ -n "${service}" ]]; then
      if [[ -z "${output}" ]]; then
        output="${service}"
      else
        output="${output},${service}"
      fi
    fi
  done
  echo "${output}"
}

require_env APP_NAME
require_env REGISTRY_URL
require_env REGISTRY_PROJECT
require_env IMAGE_TAG
require_env GITOPS_APP_DIR
require_env REPORT_DIR
require_cmd python3

SERVICES="$(service_names_csv)"
if [[ -z "${SERVICES}" ]]; then
  echo "ERROR: SERVICES did not contain any valid service names." >&2
  exit 1
fi

values_file="${GITOPS_APP_DIR}/values.yaml"
if [[ ! -f "${values_file}" ]]; then
  echo "ERROR: GitOps values file not found: ${values_file}" >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}/gitops"
before_file="$(mktemp)"
after_summary="${REPORT_DIR}/gitops/updated-images.txt"
cp "${values_file}" "${before_file}"

python3 - "${values_file}" "${after_summary}" <<'PY'
import os
import sys

values_path = sys.argv[1]
summary_path = sys.argv[2]
services = [item.strip() for item in os.environ["SERVICES"].split(",") if item.strip()]
registry_url = os.environ["REGISTRY_URL"].rstrip("/")
registry_project = os.environ["REGISTRY_PROJECT"].strip("/")
app_name = os.environ["APP_NAME"]
image_tag = os.environ["IMAGE_TAG"]

if not image_tag:
    print("ERROR: IMAGE_TAG is empty", file=sys.stderr)
    sys.exit(1)

with open(values_path, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

current_service = None
seen = {service: {"repository": False, "tag": False} for service in services}
updated = []
updates = []

for line in lines:
    stripped = line.strip()

    if line.startswith("  ") and not line.startswith("    ") and stripped.endswith(":"):
        candidate = stripped[:-1]
        current_service = candidate if candidate in seen else None

    if current_service and stripped.startswith("repository:"):
        indent = line[: len(line) - len(line.lstrip())]
        repository = f"{registry_url}/{registry_project}/{app_name}-{current_service}"
        updated.append(f"{indent}repository: {repository}\n")
        seen[current_service]["repository"] = True
        updates.append(f"{current_service}.repository={repository}")
        continue

    if current_service and stripped.startswith("tag:"):
        indent = line[: len(line) - len(line.lstrip())]
        updated.append(f"{indent}tag: {image_tag}\n")
        seen[current_service]["tag"] = True
        updates.append(f"{current_service}.tag={image_tag}")
        continue

    updated.append(line)

missing = []
for service, flags in seen.items():
    if not flags["repository"]:
        missing.append(f"{service}.image.repository")
    if not flags["tag"]:
        missing.append(f"{service}.image.tag")

if missing:
    print("ERROR: GitOps values file is missing required image fields:", file=sys.stderr)
    for item in missing:
        print(f"- {item}", file=sys.stderr)
    sys.exit(1)

with open(values_path, "w", encoding="utf-8") as fh:
    fh.writelines(updated)

with open(summary_path, "w", encoding="utf-8") as fh:
    fh.write(f"APP_NAME={app_name}\n")
    fh.write(f"REGISTRY_URL={registry_url}\n")
    fh.write(f"REGISTRY_PROJECT={registry_project}\n")
    fh.write(f"IMAGE_TAG={image_tag}\n")
    fh.write(f"SERVICES={','.join(services)}\n")
    for item in updates:
        fh.write(item + "\n")
PY

diff -u "${before_file}" "${values_file}" > "${REPORT_DIR}/gitops/diff.txt" || true
rm -f "${before_file}"

echo "Updated MSA GitOps image values in ${values_file}"
echo "Updated image summary written to ${after_summary}"
echo "Diff written to ${REPORT_DIR}/gitops/diff.txt"
echo "INFO: This script does not git commit or push by default. Commit/push must be an explicit CI policy decision."
