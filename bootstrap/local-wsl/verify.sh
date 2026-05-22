#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/local-wsl/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd kubectl
require_cmd bash

FRONTEND_LOCAL_PORT="${FRONTEND_LOCAL_PORT:-18080}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:${FRONTEND_LOCAL_PORT}}"
REPORT_DIR="${REPORT_DIR:-reports/dev/wsl-poc}"
mkdir -p "$(dirname "${REPORT_DIR}")"

pf_pid=""
cleanup() {
  if [[ -n "${pf_pid}" ]] && kill -0 "${pf_pid}" >/dev/null 2>&1; then
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if ! kubectl -n "${NAMESPACE}" get svc vulnbank-msa-frontend >/dev/null 2>&1; then
  die "Service not found: ${NAMESPACE}/vulnbank-msa-frontend. Wait for ArgoCD sync or check Application health."
fi

if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :${FRONTEND_LOCAL_PORT} )" 2>/dev/null | grep -q ":${FRONTEND_LOCAL_PORT}"; then
  die "Local port ${FRONTEND_LOCAL_PORT} is already in use. Stop the existing process or set FRONTEND_LOCAL_PORT."
fi

kubectl -n "${NAMESPACE}" port-forward svc/vulnbank-msa-frontend "${FRONTEND_LOCAL_PORT}:8080" > "${REPORT_DIR}.port-forward.log" 2>&1 &
pf_pid="$!"
sleep 3

if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
  sed -n '1,120p' "${REPORT_DIR}.port-forward.log" >&2 || true
  die "port-forward failed for ${NAMESPACE}/vulnbank-msa-frontend."
fi

log "Running MSA integration test against ${FRONTEND_URL}"
FRONTEND_URL="${FRONTEND_URL}" bash scripts/test-msa-integration.sh

log "Collecting WSL PoC evidence into ${REPORT_DIR}"
REPORT_DIR="${REPORT_DIR}" \
WORKLOAD_NAME=vulnbank-msa \
APP_NAME=vulnbank-msa \
SERVICES=user-service,transaction-service,status-service,file-service,settings-service,frontend \
NAMESPACE="${NAMESPACE}" \
DEPLOY_MODE=argocd \
IMAGE_TAG="${IMAGE_TAG:-wsl-poc}" \
FRONTEND_URL="${FRONTEND_URL}" \
bash scripts/collect-msa-evidence.sh

summary="${REPORT_DIR}/evidence/summary.txt"
[[ -f "${summary}" ]] || die "Evidence summary was not generated: ${summary}"

pass_count="$(grep -c ': PASS' "${summary}" || true)"
if [[ "${pass_count}" -lt 7 ]]; then
  sed -n '1,220p' "${summary}" >&2
  die "Expected at least 7 PASS checks, got ${pass_count}."
fi

log "Verification completed. Evidence summary:"
sed -n '1,220p' "${summary}"
