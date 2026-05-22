#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

service_names() {
  local raw
  IFS=',' read -r -a raw_services <<< "${SERVICES}"
  for raw in "${raw_services[@]}"; do
    raw="${raw//[[:space:]]/}"
    if [[ -n "${raw}" ]]; then
      echo "${raw}"
    fi
  done
}

require_env SERVICES
require_env APP_NAME
require_env NAMESPACE
require_env REPORT_DIR
require_env HELM_RELEASE
require_env HELM_CHART_DIR
require_env GITOPS_APP_DIR

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

values_file="${GITOPS_APP_DIR}/values.yaml"
if [[ ! -f "${values_file}" ]]; then
  echo "ERROR: GitOps values file not found: ${values_file}" >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}/helm" "${REPORT_DIR}/kubernetes"

helm template "${HELM_RELEASE}" "${HELM_CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --values "${values_file}" \
  --set "namespace=${NAMESPACE}" \
  > "${REPORT_DIR}/helm/rendered.yaml"

helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${values_file}" \
  --set "namespace=${NAMESPACE}" 2>&1 | tee "${REPORT_DIR}/helm/upgrade.log"

helm status "${HELM_RELEASE}" -n "${NAMESPACE}" > "${REPORT_DIR}/helm/status.txt"

for service in $(service_names); do
  kubectl rollout status "deployment/${service}" -n "${NAMESPACE}" --timeout=180s 2>&1 | tee "${REPORT_DIR}/kubernetes/rollout-${service}.log"
done

kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/part-of=${APP_NAME}" -o wide > "${REPORT_DIR}/kubernetes/pods.txt" || true
kubectl get services -n "${NAMESPACE}" -l "app.kubernetes.io/part-of=${APP_NAME}" -o wide > "${REPORT_DIR}/kubernetes/services.txt" || true
kubectl get deployments -n "${NAMESPACE}" -l "app.kubernetes.io/part-of=${APP_NAME}" -o wide > "${REPORT_DIR}/kubernetes/deployments.txt" || true

echo "MSA Helm deployment completed for ${HELM_RELEASE} in namespace ${NAMESPACE}."
