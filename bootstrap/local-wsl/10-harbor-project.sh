#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/local-wsl/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd curl
require_cmd python3

project_encoded="$(urlencode "${HARBOR_PROJECT}")"
status="$(curl -sS -o /dev/null -w '%{http_code}' -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
  "${HARBOR_URL%/}/api/v2.0/projects/${project_encoded}" || true)"

if [[ "${status}" == "200" ]]; then
  log "Harbor project already exists: ${HARBOR_PROJECT}"
  exit 0
fi

if [[ "${status}" != "404" ]]; then
  die "Harbor project lookup failed for ${HARBOR_PROJECT}; HTTP ${status}. Check HARBOR_URL and admin credentials."
fi

payload="$(python3 -c 'import json, os; print(json.dumps({"project_name": os.environ["HARBOR_PROJECT"], "public": False, "metadata": {"auto_scan": "false"}}))')"
create_status="$(curl -sS -o /tmp/secure-path-harbor-project-create.out -w '%{http_code}' \
  -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${HARBOR_URL%/}/api/v2.0/projects" \
  --data "${payload}" || true)"

case "${create_status}" in
  200|201)
    log "Created Harbor project: ${HARBOR_PROJECT}"
    ;;
  409)
    log "Harbor project already exists after create attempt: ${HARBOR_PROJECT}"
    ;;
  *)
    sed -n '1,200p' /tmp/secure-path-harbor-project-create.out >&2 || true
    die "Harbor project create failed for ${HARBOR_PROJECT}; HTTP ${create_status}."
    ;;
esac
