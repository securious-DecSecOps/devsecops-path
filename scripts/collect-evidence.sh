#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

require_env REPORT_DIR
require_env APP_NAME
require_env NAMESPACE
require_env IMAGE
require_env WORKLOAD_NAME
require_env DEPLOY_MODE

mkdir -p "${REPORT_DIR}/kubernetes" "${REPORT_DIR}/events"

build_number="${BUILD_NUMBER:-local}"
git_sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
git_sha="${git_sha:-unknown}"

gate_result_file="${REPORT_DIR}/gate/gate-result.txt"
trivy_result="missing"
gate_result="missing"
registry_push_status="missing"
kubernetes_status="unknown"
helm_status="not-applicable"
argocd_status="not-applicable"

if [[ -f "${REPORT_DIR}/trivy/image-scan.json" ]]; then
  trivy_result="present"
fi

if [[ -f "${gate_result_file}" ]]; then
  gate_result="$(grep '^GATE_STATUS=' "${gate_result_file}" | cut -d= -f2- || true)"
  gate_result="${gate_result:-unknown}"
fi

if [[ -s "${REPORT_DIR}/registry/push.log" ]]; then
  registry_push_status="present"
fi

{
  echo "BUILD_NUMBER=${build_number}"
  echo "GIT_SHA=${git_sha}"
  echo "WORKLOAD_NAME=${WORKLOAD_NAME}"
  echo "APP_NAME=${APP_NAME}"
  echo "IMAGE=${IMAGE}"
  echo "NAMESPACE=${NAMESPACE}"
  echo "DEPLOY_MODE=${DEPLOY_MODE}"
  echo "REPORT_DIR=${REPORT_DIR}"
} > "${REPORT_DIR}/metadata.txt"

if command -v kubectl >/dev/null 2>&1; then
  kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${APP_NAME}" -o wide > "${REPORT_DIR}/kubernetes/pods.txt" 2>&1 || true
  kubectl get service "${APP_NAME}" -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/service.txt" 2>&1 || true
  kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/deployment.txt" 2>&1 || true

  if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    kubernetes_status="$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null || true)"
    kubernetes_status="${kubernetes_status:-present}"
    kubectl describe deployment "${APP_NAME}" -n "${NAMESPACE}" > "${REPORT_DIR}/events/pod-describe.txt" 2>&1 || true
  else
    echo "Deployment ${APP_NAME} not found in namespace ${NAMESPACE}." > "${REPORT_DIR}/events/pod-describe.txt"
  fi

  kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp > "${REPORT_DIR}/events/image-pull-events.txt" 2>&1 || true
else
  echo "kubectl not found." > "${REPORT_DIR}/kubernetes/pods.txt"
  echo "kubectl not found." > "${REPORT_DIR}/kubernetes/service.txt"
  echo "kubectl not found." > "${REPORT_DIR}/kubernetes/deployment.txt"
  echo "kubectl not found." > "${REPORT_DIR}/events/pod-describe.txt"
  echo "kubectl not found." > "${REPORT_DIR}/events/image-pull-events.txt"
fi

if [[ "${DEPLOY_MODE}" == "helm" && -f "${REPORT_DIR}/helm/status.txt" ]]; then
  helm_status="present"
fi

if [[ "${DEPLOY_MODE}" == "argocd" && -f "${REPORT_DIR}/argocd/app-status.txt" ]]; then
  argocd_status="present"
fi

find "${REPORT_DIR}" -type f | sort > "${REPORT_DIR}/evidence-files.txt"

cat > "${REPORT_DIR}/evidence-map.md" <<EOF
# Evidence Map

| Field | Value |
| --- | --- |
| Build Number | ${build_number} |
| Git SHA | ${git_sha} |
| Workload Name | ${WORKLOAD_NAME} |
| App Name | ${APP_NAME} |
| Image | ${IMAGE} |
| Namespace | ${NAMESPACE} |
| Deploy Mode | ${DEPLOY_MODE} |
| Trivy result | ${trivy_result} |
| Gate result | ${gate_result} |
| Registry push status | ${registry_push_status} |
| Kubernetes deployment status | ${kubernetes_status} |
| Helm release status | ${helm_status} |
| ArgoCD status | ${argocd_status} |
| Evidence path | ${REPORT_DIR} |

## Key Files

- ${REPORT_DIR}/metadata.txt
- ${REPORT_DIR}/trivy/image-scan.json
- ${REPORT_DIR}/trivy/image-scan.txt
- ${REPORT_DIR}/gate/gate-result.txt
- ${REPORT_DIR}/registry/push.log
- ${REPORT_DIR}/kubernetes/pods.txt
- ${REPORT_DIR}/kubernetes/service.txt
- ${REPORT_DIR}/kubernetes/deployment.txt
- ${REPORT_DIR}/events/pod-describe.txt
- ${REPORT_DIR}/events/image-pull-events.txt
EOF

echo "Evidence collected in ${REPORT_DIR}"

