#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required environment variable is not set: ${name}" >&2
    exit 1
  fi
}

sanitize_git_output() {
  local input_file="$1"
  python3 - "${input_file}" "${GITHUB_USER:-}" "${GITHUB_PAT:-}" <<'PY'
import sys

path, user, token = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8", errors="replace") as fh:
    text = fh.read()

for secret in (token,):
    if secret:
        text = text.replace(secret, "***")
if user and token:
    text = text.replace(f"{user}:***@", "***:***@")
    text = text.replace(f"{user}:{token}@", "***:***@")

sys.stdout.write(text)
PY
}

handle_push_failure() {
  local output_file="$1"
  echo "ERROR: gitops-manifest-repo push failed after retry." >&2
  sanitize_git_output "${output_file}" >&2 || true
  if [[ "${ENFORCE_GATE:-false}" == "true" ]]; then
    exit 1
  fi
  echo "WARN: ENFORCE_GATE=${ENFORCE_GATE:-false}; continuing after GitOps push failure." >&2
  exit 0
}

require_env IMAGE_TAG
require_env GITHUB_USER
require_env GITHUB_PAT

GITOPS_REPO_DIR="${GITOPS_REPO_DIR:-gitops-manifest-repo}"
GITOPS_BRANCH="${GITOPS_BRANCH:-main}"
GITOPS_COMMIT_EMAIL="${GITOPS_COMMIT_EMAIL:-jenkins@secubank.local}"
GITOPS_COMMIT_NAME="${GITOPS_COMMIT_NAME:-Jenkins CI (vulnbank-msa)}"
BUILD_NUMBER="${BUILD_NUMBER:-unknown}"
JOB_NAME="${JOB_NAME:-unknown-job}"

if [[ -n "${GITOPS_VALUES_FILE:-}" ]]; then
  values_file="${GITOPS_VALUES_FILE}"
elif [[ -n "${GITOPS_APP_DIR:-}" ]]; then
  values_file="${GITOPS_APP_DIR#${GITOPS_REPO_DIR}/}/values.yaml"
else
  values_file="apps/vulnbank-msa/dev/values.yaml"
fi

if [[ ! -d "${GITOPS_REPO_DIR}/.git" ]]; then
  echo "ERROR: GitOps repo checkout not found: ${GITOPS_REPO_DIR}" >&2
  exit 1
fi

cd "${GITOPS_REPO_DIR}"

if [[ ! -f "${values_file}" ]]; then
  echo "ERROR: GitOps values file not found: ${GITOPS_REPO_DIR}/${values_file}" >&2
  exit 1
fi

if git diff --quiet -- "${values_file}"; then
  echo "no values.yaml changes"
  exit 0
fi

git config user.email "${GITOPS_COMMIT_EMAIL}"
git config user.name "${GITOPS_COMMIT_NAME}"
git add "${values_file}"

commit_message_file="$(mktemp)"
cat > "${commit_message_file}" <<EOF
ci: bump vulnbank-msa to image tag ${IMAGE_TAG} (build #${BUILD_NUMBER})

Source: ${JOB_NAME} #${BUILD_NUMBER}
GitOps target: apps/vulnbank-msa/dev
Image tag: ${IMAGE_TAG}
Triggered by: Jenkinsfile.msa post-update-gitops stage
EOF

if git diff --cached --quiet -- "${values_file}"; then
  echo "no staged values.yaml changes"
  rm -f "${commit_message_file}"
  exit 0
fi

git commit -F "${commit_message_file}"
rm -f "${commit_message_file}"

remote_url="https://${GITHUB_USER}:${GITHUB_PAT}@github.com/securious-DecSecOps/gitops-manifest-repo.git"
push_output="$(mktemp)"

echo "Pushing GitOps values update to gitops-manifest-repo branch ${GITOPS_BRANCH}"
if git push "${remote_url}" "HEAD:${GITOPS_BRANCH}" > "${push_output}" 2>&1; then
  echo "GitOps push completed."
  rm -f "${push_output}"
  exit 0
fi

echo "WARN: initial GitOps push failed; attempting git pull --rebase and one retry." >&2
sanitize_git_output "${push_output}" >&2 || true

if ! git pull --rebase origin "${GITOPS_BRANCH}" >> "${push_output}" 2>&1; then
  handle_push_failure "${push_output}"
fi

if git push "${remote_url}" "HEAD:${GITOPS_BRANCH}" > "${push_output}" 2>&1; then
  echo "GitOps push completed after rebase."
  rm -f "${push_output}"
  exit 0
fi

handle_push_failure "${push_output}"
