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
require_env GITOPS_APP_DIR

values_file="${GITOPS_APP_DIR}/values.yaml"

if [[ ! -f "${values_file}" ]]; then
  echo "ERROR: GitOps values file not found: ${values_file}" >&2
  exit 1
fi

image_repository="${IMAGE%:*}"
image_tag="${IMAGE##*:}"

mkdir -p "${REPORT_DIR}/gitops"
before_file="${REPORT_DIR}/gitops/values.before.yaml"
cp "${values_file}" "${before_file}"

echo "Updating GitOps image in ${values_file}"
echo "image.repository=${image_repository}"
echo "image.tag=${image_tag}"

python3 - "${values_file}" "${image_repository}" "${image_tag}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
repository = sys.argv[2]
tag = sys.argv[3]

lines = path.read_text(encoding="utf-8").splitlines()
out = []
in_image = False

for line in lines:
    stripped = line.strip()
    if stripped == "image:":
        in_image = True
        out.append(line)
        continue
    if in_image and line and not line.startswith(" "):
        in_image = False
    if in_image and stripped.startswith("repository:"):
        indent = line[: len(line) - len(line.lstrip())]
        out.append(f"{indent}repository: {repository}")
    elif in_image and stripped.startswith("tag:"):
        indent = line[: len(line) - len(line.lstrip())]
        out.append(f'{indent}tag: "{tag}"')
    else:
        out.append(line)

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

diff -u "${before_file}" "${values_file}" > "${REPORT_DIR}/gitops/diff.txt" || true

if [[ "${GITOPS_COMMIT_PUSH:-false}" == "true" ]]; then
  echo "GITOPS_COMMIT_PUSH=true requested."
  echo "This template intentionally does not push by default. Configure credentials and remote policy before enabling git commit/push in CI." | tee -a "${REPORT_DIR}/gitops/diff.txt"
else
  echo "GitOps image update completed without commit/push. Set GITOPS_COMMIT_PUSH=true only after adding safe CI git credentials."
fi

