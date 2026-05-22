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
require_env HELM_RELEASE
require_env HELM_CHART_DIR

if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -d "${HELM_CHART_DIR}" ]]; then
  echo "ERROR: HELM_CHART_DIR does not exist: ${HELM_CHART_DIR}" >&2
  exit 1
fi

image_repository="${IMAGE%:*}"
image_tag="${IMAGE##*:}"

mkdir -p "${REPORT_DIR}/helm" "${REPORT_DIR}/kubernetes"

echo "Deploying Helm release ${HELM_RELEASE} from ${HELM_CHART_DIR}"
echo "Image repository: ${image_repository}"
echo "Image tag: ${image_tag}"

helm template "${HELM_RELEASE}" "${HELM_CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --set "nameOverride=${APP_NAME}" \
  --set "namespace=${NAMESPACE}" \
  --set "image.repository=${image_repository}" \
  --set "image.tag=${image_tag}" \
  > "${REPORT_DIR}/helm/rendered.yaml"

helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set "nameOverride=${APP_NAME}" \
  --set "namespace=${NAMESPACE}" \
  --set "image.repository=${image_repository}" \
  --set "image.tag=${image_tag}" 2>&1 | tee "${REPORT_DIR}/helm/upgrade.log"

helm status "${HELM_RELEASE}" -n "${NAMESPACE}" > "${REPORT_DIR}/helm/status.txt"
kubectl rollout status "deployment/${APP_NAME}" -n "${NAMESPACE}" --timeout=180s 2>&1 | tee "${REPORT_DIR}/kubernetes/rollout.log"

kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${APP_NAME}" -o wide > "${REPORT_DIR}/kubernetes/pods.txt"
kubectl get service "${APP_NAME}" -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/service.txt"
kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/deployment.txt"

echo "Helm deployment completed for ${APP_NAME} in namespace ${NAMESPACE}."

