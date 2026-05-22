#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

require_env APP_NAME
require_env NAMESPACE
require_env IMAGE
require_env REPORT_DIR

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required but was not found in PATH." >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}/kubernetes"
rendered="${REPORT_DIR}/kubernetes/rendered-kubectl.yaml"

echo "Rendering k8s/base for APP_NAME=${APP_NAME}, NAMESPACE=${NAMESPACE}, IMAGE=${IMAGE}"

python3 - "${APP_NAME}" "${NAMESPACE}" "${IMAGE}" "${rendered}" <<'PY'
from pathlib import Path
import sys

app_name, namespace, image, rendered_path = sys.argv[1:5]
base_files = [
    Path("k8s/base/namespace.yaml"),
    Path("k8s/base/deployment.yaml"),
    Path("k8s/base/service.yaml"),
]

documents = []
for path in base_files:
    text = path.read_text(encoding="utf-8")
    text = text.replace("simple-web", app_name)
    text = text.replace("secure-path-dev", namespace)
    if path.name == "deployment.yaml":
        lines = []
        for line in text.splitlines():
            if line.strip().startswith("image: "):
                indent = line[: len(line) - len(line.lstrip())]
                lines.append(f"{indent}image: {image}")
            else:
                lines.append(line)
        text = "\n".join(lines) + "\n"
    documents.append(text)

Path(rendered_path).write_text("---\n" + "---\n".join(documents), encoding="utf-8")
PY

kubectl apply -f "${rendered}" 2>&1 | tee "${REPORT_DIR}/kubernetes/apply.log"
kubectl rollout status "deployment/${APP_NAME}" -n "${NAMESPACE}" --timeout=180s 2>&1 | tee "${REPORT_DIR}/kubernetes/rollout.log"

kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${APP_NAME}" -o wide > "${REPORT_DIR}/kubernetes/pods.txt"
kubectl get service "${APP_NAME}" -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/service.txt"
kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/deployment.txt"

echo "kubectl deployment completed for ${APP_NAME} in namespace ${NAMESPACE}."

