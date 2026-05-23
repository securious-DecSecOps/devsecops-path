#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/local-wsl/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd curl
require_cmd python3

load_harbor_robot_env
load_sonarqube_token_env

probe_sonar_from_jenkins_container() {
  local candidate="$1"
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  docker inspect "${JENKINS_CONTAINER}" >/dev/null 2>&1 || return 1
  docker exec "${JENKINS_CONTAINER}" sh -lc "command -v curl >/dev/null 2>&1 && curl -fsS --max-time 3 ${candidate%/}/api/system/status >/dev/null" >/dev/null 2>&1
}

detect_sonar_url_for_jenkins() {
  local candidate
  local host_ip
  if [[ -n "${SONAR_HOST_URL_FOR_JENKINS}" ]]; then
    printf '%s\n' "${SONAR_HOST_URL_FOR_JENKINS}"
    return 0
  fi

  for candidate in "${SONAR_HOST_URL}" "http://sonarqube:9000" "http://host.docker.internal:9000" "http://172.17.0.1:9000"; do
    if probe_sonar_from_jenkins_container "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "${host_ip}" ]]; then
    candidate="http://${host_ip}:9000"
    if probe_sonar_from_jenkins_container "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  warn "Could not verify SonarQube reachability from Jenkins container ${JENKINS_CONTAINER}."
  warn "Using ${SONAR_HOST_URL}. If SonarQube scan cannot connect, rerun with SONAR_HOST_URL_FOR_JENKINS=http://host.docker.internal:9000 or http://<WSL-IP>:9000."
  printf '%s\n' "${SONAR_HOST_URL}"
}

crumb_args=()
while IFS= read -r item; do
  crumb_args+=("${item}")
done < <(jenkins_crumb_header_args)

registry_username="${REGISTRY_USERNAME:-${HARBOR_ROBOT_USERNAME:-}}"
registry_password="${REGISTRY_PASSWORD:-${HARBOR_ROBOT_PASSWORD:-}}"
sonar_token="${SONAR_TOKEN:-}"

if [[ -z "${registry_username}" || -z "${registry_password}" ]]; then
  warn "REGISTRY_USERNAME/REGISTRY_PASSWORD were not found. The Jenkins build may fail at docker login."
  warn "Run bootstrap/local-wsl/20-jenkins-credentials.sh first, or export REGISTRY_USERNAME/REGISTRY_PASSWORD."
fi

if [[ -z "${sonar_token}" ]]; then
  warn "SONAR_TOKEN was not found. SonarQube stage will be skipped by the pipeline."
  warn "Run bootstrap/local-wsl/05-install-sonarqube.sh first, or export SONAR_TOKEN."
fi

job_url="${JENKINS_URL%/}/job/$(urlencode "${JENKINS_JOB_NAME}")"
if ! jenkins_curl GET "${job_url}/api/json" >/dev/null 2>&1; then
  die "Jenkins job does not exist: ${JENKINS_JOB_NAME}. Run bootstrap/local-wsl/30-jenkins-job.sh first."
fi

registry_url="${REGISTRY_URL_FOR_JENKINS:-harbor:8082}"
sonar_host_url="$(detect_sonar_url_for_jenkins)"
if [[ -f "${LOCAL_STATE_DIR}/${JENKINS_JOB_NAME}-config.xml" ]]; then
  registry_url="$(python3 - "${LOCAL_STATE_DIR}/${JENKINS_JOB_NAME}-config.xml" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"<name>REGISTRY_URL</name>\s*<description>.*?</description>\s*<defaultValue>(.*?)</defaultValue>", text, re.S)
print(match.group(1) if match else "harbor:8082")
PY
)"
fi

params=(
  --data-urlencode "WORKLOAD_NAME=vulnbank-msa"
  --data-urlencode "APP_NAME=vulnbank-msa"
  --data-urlencode "APP_SOURCE_REPO_URL=${APP_SOURCE_REPO_URL}"
  --data-urlencode "APP_SOURCE_BRANCH=${APP_SOURCE_BRANCH}"
  --data-urlencode "GITOPS_REPO_URL=${GITOPS_REPO_URL}"
  --data-urlencode "GITOPS_BRANCH=${GITOPS_BRANCH}"
  --data-urlencode "MSA_WORKLOAD_DIR=app-source-repo/examples/vulnbank-msa"
  --data-urlencode "SERVICES=user-service,transaction-service,status-service,file-service,settings-service,frontend"
  --data-urlencode "NAMESPACE=${NAMESPACE}"
  --data-urlencode "REGISTRY_URL=${registry_url}"
  --data-urlencode "REGISTRY_PROJECT=${REGISTRY_PROJECT}"
  --data-urlencode "IMAGE_TAG=${IMAGE_TAG}"
  --data-urlencode "KUBECONFIG=/var/jenkins_home/kubeconfig"
  --data-urlencode "DEPLOY_MODE=${DEPLOY_MODE}"
  --data-urlencode "ENFORCE_GATE=false"
  --data-urlencode "HELM_RELEASE=vulnbank-msa"
  --data-urlencode "HELM_CHART_DIR=gitops-manifest-repo/helm/vulnbank-msa"
  --data-urlencode "GITOPS_APP_DIR=gitops-manifest-repo/apps/vulnbank-msa/dev"
  --data-urlencode "ARGOCD_APP_MANIFEST=gitops-manifest-repo/argocd/applications/vulnbank-msa-dev.yaml"
  --data-urlencode "ARGOCD_APP_NAME=${ARGOCD_APP_NAME}"
  --data-urlencode "SONAR_HOST_URL=${sonar_host_url}"
)

if [[ -n "${registry_username}" && -n "${registry_password}" ]]; then
  params+=(--data-urlencode "REGISTRY_USERNAME=${registry_username}")
  params+=(--data-urlencode "REGISTRY_PASSWORD=${registry_password}")
fi

if [[ -n "${sonar_token}" ]]; then
  params+=(--data-urlencode "SONAR_TOKEN=${sonar_token}")
fi

headers_file="${LOCAL_STATE_DIR}/jenkins-trigger-headers.txt"
body_file="${LOCAL_STATE_DIR}/jenkins-trigger-body.txt"
http_code="$(jenkins_curl POST "${job_url}/buildWithParameters" "${crumb_args[@]}" \
  -D "${headers_file}" -o "${body_file}" -w '%{http_code}' "${params[@]}" || true)"

if [[ "${http_code}" != "201" && "${http_code}" != "302" ]]; then
  sed -n '1,200p' "${body_file}" >&2 || true
  die "Jenkins build trigger failed for ${JENKINS_JOB_NAME}; HTTP ${http_code}."
fi

queue_url="$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {gsub(/\r/,""); print $2}' "${headers_file}" | tail -n 1)"
[[ -n "${queue_url}" ]] || die "Jenkins did not return a queue Location header."
log "Triggered Jenkins build; queue=${queue_url}"

build_number=""
for _ in $(seq 1 60); do
  queue_json="$(jenkins_curl GET "${queue_url%/}/api/json")"
  build_number="$(python3 -c 'import json,sys; d=json.load(sys.stdin); e=d.get("executable") or {}; print(e.get("number",""))' <<< "${queue_json}")"
  if [[ -n "${build_number}" ]]; then
    break
  fi
  why="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("why") or "waiting")' <<< "${queue_json}")"
  log "Jenkins queue waiting: ${why}"
  sleep 3
done

[[ -n "${build_number}" ]] || die "Timed out waiting for Jenkins queue item to start."
log "Jenkins build started: ${JENKINS_JOB_NAME} #${build_number}"

for _ in $(seq 1 240); do
  build_json="$(jenkins_curl GET "${job_url}/${build_number}/api/json")"
  building="$(python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("building", False)).lower())' <<< "${build_json}")"
  result="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("result") or "")' <<< "${build_json}")"
  if [[ "${building}" != "true" ]]; then
    log "Jenkins build finished: result=${result}"
    [[ "${result}" == "SUCCESS" ]] || die "Jenkins build failed: ${JENKINS_JOB_NAME} #${build_number} result=${result}"
    exit 0
  fi
  sleep 10
done

die "Timed out waiting for Jenkins build completion: ${JENKINS_JOB_NAME} #${build_number}"
