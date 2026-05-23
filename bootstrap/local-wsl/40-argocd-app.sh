#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/local-wsl/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd kubectl
require_cmd python3
ensure_state_dir

if command -v git >/dev/null 2>&1; then
  if ! git ls-remote "${GITOPS_REPO_URL}" "${GITOPS_TARGET_REVISION}" >/dev/null 2>&1; then
    die "GitOps repo is not reachable: ${GITOPS_REPO_URL}. Create gitops-manifest-repo on GitHub, push apps/vulnbank-msa/dev, then rerun with GITOPS_REPO_URL=<repo-url>."
  fi
else
  warn "git command not found; skipping remote GitOps repo reachability check."
fi

if ! kubectl get namespace "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  die "ArgoCD namespace does not exist: ${ARGOCD_NAMESPACE}"
fi

if ! kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  die "ArgoCD Application CRD was not found. Existing ArgoCD must be installed before running this script."
fi

manifest="${LOCAL_STATE_DIR}/${ARGOCD_APP_NAME}.yaml"
python3 - "${manifest}" <<'PY'
import os
import sys

# ArgoCD-native Helm source. Avoids needing kustomize.buildOptions=--enable-helm
# on the existing cluster's argocd-cm. valuesFiles paths are resolved relative
# to the chart directory in the same repo.
helm_chart_path = os.environ.get("GITOPS_HELM_CHART_PATH", "helm/vulnbank-msa")
values_path = os.environ.get("GITOPS_APP_PATH", "apps/vulnbank-msa/dev")
# Relative path from the chart dir up to repo root, then into the values dir.
chart_depth = helm_chart_path.count("/") + 1
relative_values_file = ("../" * chart_depth) + values_path + "/values.yaml"

manifest = f"""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {os.environ["ARGOCD_APP_NAME"]}
  namespace: {os.environ["ARGOCD_NAMESPACE"]}
spec:
  project: default
  source:
    repoURL: {os.environ["GITOPS_REPO_URL"]}
    targetRevision: {os.environ["GITOPS_TARGET_REVISION"]}
    path: {helm_chart_path}
    helm:
      releaseName: {os.environ.get("HELM_RELEASE", "vulnbank-msa")}
      valueFiles:
        - {relative_values_file}
  destination:
    server: https://kubernetes.default.svc
    namespace: {os.environ["ARGOCD_DEST_NAMESPACE"]}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
"""
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write(manifest)
PY

kubectl apply -f "${manifest}"
log "Applied ArgoCD Application ${ARGOCD_APP_NAME} from ${GITOPS_REPO_URL}/${GITOPS_APP_PATH}"

if [[ "${WAIT_ARGOCD:-true}" != "true" ]]; then
  log "WAIT_ARGOCD=false; skipping sync/health wait."
  exit 0
fi

log "Waiting for ArgoCD Application ${ARGOCD_APP_NAME} to become Synced + Healthy."
for _ in $(seq 1 60); do
  sync_status="$(kubectl -n "${ARGOCD_NAMESPACE}" get application "${ARGOCD_APP_NAME}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health_status="$(kubectl -n "${ARGOCD_NAMESPACE}" get application "${ARGOCD_APP_NAME}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  if [[ "${sync_status}" == "Synced" && "${health_status}" == "Healthy" ]]; then
    log "ArgoCD Application is Synced + Healthy: ${ARGOCD_APP_NAME}"
    exit 0
  fi
  log "ArgoCD status: sync=${sync_status:-unknown}, health=${health_status:-unknown}; waiting..."
  sleep 5
done

kubectl -n "${ARGOCD_NAMESPACE}" get application "${ARGOCD_APP_NAME}" -o wide || true
die "ArgoCD Application did not become Synced + Healthy within timeout. Check repoURL/path, repository credentials, and image pull access."
