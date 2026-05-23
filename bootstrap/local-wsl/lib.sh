#!/usr/bin/env bash
set -euo pipefail

export JENKINS_URL="${JENKINS_URL:-http://localhost:8083}"
export JENKINS_USER="${JENKINS_USER:-}"
export JENKINS_TOKEN="${JENKINS_TOKEN:-}"
export JENKINS_CONTAINER="${JENKINS_CONTAINER:-secubank-jenkins}"
export JENKINS_JOB_NAME="${JENKINS_JOB_NAME:-vulnbank-msa-dev}"
export JENKINS_CREDENTIAL_ID="${JENKINS_CREDENTIAL_ID:-harbor-secubank-robot}"

export HARBOR_URL="${HARBOR_URL:-http://localhost:8082}"
export HARBOR_ADMIN_USER="${HARBOR_ADMIN_USER:-admin}"
export HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
export HARBOR_PROJECT="${HARBOR_PROJECT:-secubank}"
export HARBOR_ROBOT_NAME="${HARBOR_ROBOT_NAME:-vulnbank-msa-jenkins}"

export ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
export ARGOCD_APP_NAME="${ARGOCD_APP_NAME:-secubank-vulnbank-msa-dev}"
export ARGOCD_DEST_NAMESPACE="${ARGOCD_DEST_NAMESPACE:-secure-path-dev}"
export GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/securious-DecSecOps/gitops-manifest-repo.git}"
export GITOPS_BRANCH="${GITOPS_BRANCH:-main}"
export GITOPS_TARGET_REVISION="${GITOPS_TARGET_REVISION:-main}"
export GITOPS_APP_PATH="${GITOPS_APP_PATH:-apps/vulnbank-msa/dev}"
export APP_SOURCE_REPO_URL="${APP_SOURCE_REPO_URL:-https://github.com/securious-DecSecOps/app-source-repo.git}"
export APP_SOURCE_BRANCH="${APP_SOURCE_BRANCH:-main}"

export PIPELINE_REPO_URL="${PIPELINE_REPO_URL:-}"
export PIPELINE_BRANCH="${PIPELINE_BRANCH:-main}"

export REGISTRY_PROJECT="${REGISTRY_PROJECT:-${HARBOR_PROJECT}}"
export REGISTRY_URL_FOR_JENKINS="${REGISTRY_URL_FOR_JENKINS:-}"
export NAMESPACE="${NAMESPACE:-secure-path-dev}"
export DEPLOY_MODE="${DEPLOY_MODE:-argocd}"
export IMAGE_TAG="${IMAGE_TAG:-}"

export LOCAL_STATE_DIR="${LOCAL_STATE_DIR:-.local/wsl-poc}"
export HARBOR_ROBOT_ENV_FILE="${HARBOR_ROBOT_ENV_FILE:-${LOCAL_STATE_DIR}/harbor-robot.env}"

log() {
  printf '[local-wsl] %s\n' "$*"
}

warn() {
  printf '[local-wsl][WARN] %s\n' "$*" >&2
}

die() {
  printf '[local-wsl][ERROR] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "required command not found: ${cmd}"
}

ensure_state_dir() {
  mkdir -p "${LOCAL_STATE_DIR}"
  chmod 700 "${LOCAL_STATE_DIR}"
}

curl_auth_args() {
  if [[ -n "${JENKINS_USER}" && -n "${JENKINS_TOKEN}" ]]; then
    printf '%s\n' "-u" "${JENKINS_USER}:${JENKINS_TOKEN}"
  fi
}

jenkins_curl() {
  local method="$1"
  local url="$2"
  shift 2
  local auth_args=()
  if [[ -n "${JENKINS_USER}" && -n "${JENKINS_TOKEN}" ]]; then
    auth_args=(-u "${JENKINS_USER}:${JENKINS_TOKEN}")
  fi
  curl -fsS "${auth_args[@]}" -X "${method}" "${url}" "$@"
}

jenkins_crumb_header_args() {
  local crumb_json
  local crumb
  if ! crumb_json="$(jenkins_curl GET "${JENKINS_URL%/}/crumbIssuer/api/json" 2>/dev/null)"; then
    return 0
  fi
  crumb="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("crumbRequestField","Jenkins-Crumb") + ":" + d.get("crumb",""))' <<< "${crumb_json}")"
  if [[ "${crumb}" != *: ]]; then
    printf '%s\n' "-H" "${crumb}"
  fi
}

harbor_curl() {
  local method="$1"
  local path="$2"
  shift 2
  curl -fsS -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" -X "${method}" "${HARBOR_URL%/}${path}" "$@"
}

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

detect_pipeline_repo_url() {
  if [[ -n "${PIPELINE_REPO_URL}" ]]; then
    printf '%s\n' "${PIPELINE_REPO_URL}"
    return 0
  fi
  if git config --get remote.origin.url >/dev/null 2>&1; then
    git config --get remote.origin.url
    return 0
  fi
  printf '%s\n' "https://github.com/securious-DecSecOps/secure-k8s-delivery-path.git"
}

load_harbor_robot_env() {
  if [[ -f "${HARBOR_ROBOT_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${HARBOR_ROBOT_ENV_FILE}"
  fi
}
