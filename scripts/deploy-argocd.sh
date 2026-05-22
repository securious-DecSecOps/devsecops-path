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

ARGOCD_APP_MANIFEST="${ARGOCD_APP_MANIFEST:-argocd/applications/simple-web-dev.yaml}"
ARGOCD_APP_NAME="${ARGOCD_APP_NAME:-simple-web-dev}"

mkdir -p "${REPORT_DIR}/argocd"
status_file="${REPORT_DIR}/argocd/app-status.txt"

{
  echo "ARGOCD_APP_MANIFEST=${ARGOCD_APP_MANIFEST}"
  echo "ARGOCD_APP_NAME=${ARGOCD_APP_NAME}"
} | tee "${status_file}"

if [[ ! -f "${ARGOCD_APP_MANIFEST}" ]]; then
  echo "ERROR: ArgoCD Application manifest not found: ${ARGOCD_APP_MANIFEST}" | tee -a "${status_file}" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "WARN: kubectl not found. Cannot apply ArgoCD Application manifest." | tee -a "${status_file}" >&2
  exit 0
fi

if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  echo "Applying ArgoCD Application manifest." | tee -a "${status_file}"
  if kubectl apply -f "${ARGOCD_APP_MANIFEST}" 2>&1 | tee -a "${status_file}"; then
    echo "ArgoCD Application apply completed." | tee -a "${status_file}"
  else
    echo "WARN: Failed to apply ArgoCD Application. Check ArgoCD namespace, CRDs, and repoURL placeholder." | tee -a "${status_file}" >&2
    exit 0
  fi
else
  {
    echo "WARN: ArgoCD CRD applications.argoproj.io was not found."
    echo "WARN: Install ArgoCD, replace repoURL in ${ARGOCD_APP_MANIFEST}, then apply the manifest."
    echo "NEXT: kubectl apply -f ${ARGOCD_APP_MANIFEST}"
  } | tee -a "${status_file}" >&2
  exit 0
fi

if command -v argocd >/dev/null 2>&1; then
  echo "Running best-effort ArgoCD status check." | tee -a "${status_file}"
  argocd app get "${ARGOCD_APP_NAME}" 2>&1 | tee -a "${status_file}" || true
else
  echo "WARN: argocd CLI not installed. Use ArgoCD UI or install CLI for sync/health checks." | tee -a "${status_file}" >&2
fi

