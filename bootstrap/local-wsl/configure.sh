#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/local-wsl/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd curl
require_cmd python3
require_cmd kubectl

log "Starting local WSL wiring for VulnBank MSA."
log "Jenkins URL: ${JENKINS_URL}"
log "Harbor URL: ${HARBOR_URL}"
log "ArgoCD namespace: ${ARGOCD_NAMESPACE}"
log "GitOps repo: ${GITOPS_REPO_URL}"
log "ArgoCD app: ${ARGOCD_APP_NAME}"

current_context="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${current_context}" != "kind-devsecops" ]]; then
  warn "Current kubectl context is '${current_context:-unknown}', expected 'kind-devsecops'. Continuing because the user may intentionally target another context."
fi

"${SCRIPT_DIR}/10-harbor-project.sh"
"${SCRIPT_DIR}/05-install-sonarqube.sh"
"${SCRIPT_DIR}/20-jenkins-credentials.sh"
"${SCRIPT_DIR}/30-jenkins-job.sh"

if [[ "${RUN_BUILD:-true}" == "true" ]]; then
  "${SCRIPT_DIR}/50-trigger-build.sh"
else
  log "RUN_BUILD=false; Jenkins build trigger skipped."
fi

"${SCRIPT_DIR}/40-argocd-app.sh"

log "Local WSL wiring completed."
log "Next: bash bootstrap/local-wsl/verify.sh"
