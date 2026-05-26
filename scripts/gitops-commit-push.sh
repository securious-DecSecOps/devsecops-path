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
  python3 - "${input_file}" <<'PY'
import os
import sys

path = sys.argv[1]
user = os.environ.get("GITHUB_USER", "")
token = os.environ.get("GITHUB_PAT", "")
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
  # GitOps push failure is an infrastructure/deployment failure, not a
  # vulnerability policy decision. ENFORCE_GATE only controls whether security
  # findings block the build; it must never turn a failed GitOps push into a
  # successful Jenkins build because ArgoCD would keep running the old image.
  echo "ERROR: gitops-manifest-repo push failed after all retries." >&2
  sanitize_git_output "${output_file}" >&2 || true
  exit 1
}

setup_git_askpass() {
  # Do not put the GitHub PAT in the remote URL. A URL such as
  # https://user:token@github.com/... leaks through process argv and /proc.
  # GIT_ASKPASS lets Git obtain credentials from environment variables without
  # exposing the token in the git push command line.
  askpass_file="$(mktemp)"
  chmod 700 "${askpass_file}"
  cat > "${askpass_file}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*|*username*)
    printf '%s\n' "${GIT_USER:-}"
    ;;
  *Password*|*password*)
    printf '%s\n' "${GIT_PAT:-}"
    ;;
  *)
    printf '\n'
    ;;
esac
EOF
  export GIT_ASKPASS="${askpass_file}"
  export GIT_TERMINAL_PROMPT=0
  export GIT_USER="${GITHUB_USER}"
  export GIT_PAT="${GITHUB_PAT}"
}

cleanup() {
  if [[ -n "${askpass_file:-}" ]]; then
    rm -f "${askpass_file}"
  fi
  if [[ -n "${commit_message_file:-}" ]]; then
    rm -f "${commit_message_file}"
  fi
  if [[ -n "${push_output:-}" ]]; then
    rm -f "${push_output}"
  fi
}

push_once() {
  local output_file="$1"
  git push "${GITOPS_PUSH_REPO_URL}" "HEAD:${GITOPS_BRANCH}" > "${output_file}" 2>&1
}

rebase_from_remote() {
  local output_file="$1"
  if ! git fetch "${GITOPS_PUSH_REPO_URL}" "${GITOPS_BRANCH}" >> "${output_file}" 2>&1; then
    return 1
  fi
  git rebase FETCH_HEAD >> "${output_file}" 2>&1
}

require_env IMAGE_TAG
require_env GITHUB_USER
require_env GITHUB_PAT

GITOPS_REPO_DIR="${GITOPS_REPO_DIR:-gitops-manifest-repo}"
GITOPS_BRANCH="${GITOPS_BRANCH:-main}"
GITOPS_COMMIT_EMAIL="${GITOPS_COMMIT_EMAIL:-jenkins@secubank.local}"
GITOPS_COMMIT_NAME="${GITOPS_COMMIT_NAME:-Jenkins CI (vulnbank-msa)}"
GITOPS_PUSH_REPO_URL="${GITOPS_PUSH_REPO_URL:-https://github.com/securious-DecSecOps/gitops-manifest-repo.git}"
GITOPS_PUSH_MAX_ATTEMPTS="${GITOPS_PUSH_MAX_ATTEMPTS:-5}"
BUILD_NUMBER="${BUILD_NUMBER:-unknown}"
JOB_NAME="${JOB_NAME:-unknown-job}"
askpass_file=""
commit_message_file=""
push_output=""

trap cleanup EXIT

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

if ! [[ "${GITOPS_PUSH_MAX_ATTEMPTS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: GITOPS_PUSH_MAX_ATTEMPTS must be a positive integer: ${GITOPS_PUSH_MAX_ATTEMPTS}" >&2
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
push_output="$(mktemp)"
setup_git_askpass

echo "Pushing GitOps values update to gitops-manifest-repo branch ${GITOPS_BRANCH}"
for attempt in $(seq 1 "${GITOPS_PUSH_MAX_ATTEMPTS}"); do
  : > "${push_output}"
  if push_once "${push_output}"; then
    if [[ "${attempt}" -eq 1 ]]; then
      echo "GitOps push completed."
    else
      echo "GitOps push completed after rebase attempt ${attempt}."
    fi
    exit 0
  fi

  echo "WARN: GitOps push attempt ${attempt}/${GITOPS_PUSH_MAX_ATTEMPTS} failed." >&2
  sanitize_git_output "${push_output}" >&2 || true

  if [[ "${attempt}" -ge "${GITOPS_PUSH_MAX_ATTEMPTS}" ]]; then
    break
  fi

  echo "WARN: rebasing on ${GITOPS_BRANCH} before retry $((attempt + 1))." >&2
  if ! rebase_from_remote "${push_output}"; then
    echo "WARN: rebase attempt ${attempt} failed; aborting any in-progress rebase." >&2
    git rebase --abort >> "${push_output}" 2>&1 || true
    sanitize_git_output "${push_output}" >&2 || true
  fi

  backoff=$((2 ** attempt))
  echo "WARN: waiting ${backoff}s before GitOps push retry $((attempt + 1))." >&2
  sleep "${backoff}"
done

handle_push_failure "${push_output}"
