#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/local-wsl/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd curl
require_cmd python3
ensure_state_dir

pipeline_repo_url="$(detect_pipeline_repo_url)"

probe_from_jenkins_container() {
  local candidate="$1"
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  docker inspect "${JENKINS_CONTAINER}" >/dev/null 2>&1 || return 1
  docker exec "${JENKINS_CONTAINER}" sh -lc "command -v curl >/dev/null 2>&1 && curl -fsS --max-time 3 http://${candidate}/api/v2.0/ping >/dev/null" >/dev/null 2>&1
}

detect_registry_url_for_jenkins() {
  if [[ -n "${REGISTRY_URL_FOR_JENKINS}" ]]; then
    printf '%s\n' "${REGISTRY_URL_FOR_JENKINS}"
    return 0
  fi

  # IMPORTANT: docker push from Jenkins runs through the host's docker daemon
  # (Jenkins mounts /var/run/docker.sock). So REGISTRY_URL must be a value the
  # HOST daemon trusts in its insecure-registries list (typically 127.0.0.0/8).
  # A curl-based probe from inside the Jenkins container can pick a URL that
  # is curl-reachable (e.g., <WSL-IP>:8082) but is NOT in the daemon's
  # insecure list — causing "http: server gave HTTP response to HTTPS client".
  #
  # For the WSL local PoC we therefore default to "localhost:8082" without
  # any probe. Override with REGISTRY_URL_FOR_JENKINS for other environments.
  printf '%s\n' "localhost:8082"
}

registry_url="$(detect_registry_url_for_jenkins)"
job_xml="${LOCAL_STATE_DIR}/${JENKINS_JOB_NAME}-config.xml"
export PIPELINE_REPO_URL_RESOLVED="${pipeline_repo_url}"
export REGISTRY_URL_RESOLVED="${registry_url}"

python3 - "${job_xml}" <<'PY'
import os
import sys
import xml.sax.saxutils as x

job_name = os.environ["JENKINS_JOB_NAME"]
repo_url = os.environ["PIPELINE_REPO_URL_RESOLVED"]
branch = os.environ["PIPELINE_BRANCH"]
registry_url = os.environ["REGISTRY_URL_RESOLVED"]
registry_project = os.environ["REGISTRY_PROJECT"]
namespace = os.environ["NAMESPACE"]
deploy_mode = os.environ["DEPLOY_MODE"]
argocd_app_name = os.environ["ARGOCD_APP_NAME"]
credential_id = os.environ["JENKINS_CREDENTIAL_ID"]
git_credentials_id = os.environ.get("GIT_CREDENTIALS_ID", "")
app_source_repo_url = os.environ["APP_SOURCE_REPO_URL"]
app_source_branch = os.environ["APP_SOURCE_BRANCH"]
gitops_repo_url = os.environ["GITOPS_REPO_URL"]
gitops_branch = os.environ["GITOPS_BRANCH"]
sonar_host_url = os.environ["SONAR_HOST_URL"]

def esc(value):
    return x.escape(value)

def string_param(name, default, desc):
    return f"""          <hudson.model.StringParameterDefinition>
            <name>{esc(name)}</name>
            <description>{esc(desc)}</description>
            <defaultValue>{esc(default)}</defaultValue>
            <trim>true</trim>
          </hudson.model.StringParameterDefinition>
"""

def bool_param(name, default, desc):
    return f"""          <hudson.model.BooleanParameterDefinition>
            <name>{esc(name)}</name>
            <description>{esc(desc)}</description>
            <defaultValue>{str(default).lower()}</defaultValue>
          </hudson.model.BooleanParameterDefinition>
"""

def choice_param(name, choices, default, desc):
    ordered = [default] + [c for c in choices if c != default]
    choice_xml = "".join(f"              <string>{esc(c)}</string>\n" for c in ordered)
    return f"""          <hudson.model.ChoiceParameterDefinition>
            <name>{esc(name)}</name>
            <description>{esc(desc)}</description>
            <choices class=\"java.util.Arrays$ArrayList\">
              <a class=\"string-array\">
{choice_xml}              </a>
            </choices>
          </hudson.model.ChoiceParameterDefinition>
"""

def password_param(name, default, desc):
    return f"""          <hudson.model.PasswordParameterDefinition>
            <name>{esc(name)}</name>
            <description>{esc(desc)}</description>
            <defaultValue>{esc(default)}</defaultValue>
          </hudson.model.PasswordParameterDefinition>
"""

params = ""
params += string_param("WORKLOAD_NAME", "vulnbank-msa", "MSA workload profile name.")
params += string_param("APP_NAME", "vulnbank-msa", "Application/release prefix.")
params += string_param("APP_SOURCE_REPO_URL", app_source_repo_url, "GitHub URL of the app-source-repo (examples/vulnbank-msa).")
params += string_param("APP_SOURCE_BRANCH", app_source_branch, "Branch to check out from app-source-repo.")
params += string_param("GITOPS_REPO_URL", gitops_repo_url, "GitHub URL of gitops-manifest-repo (helm chart + apps overlay).")
params += string_param("GITOPS_BRANCH", gitops_branch, "Branch to check out from gitops-manifest-repo.")
params += string_param("MSA_WORKLOAD_DIR", "app-source-repo/examples/vulnbank-msa", "MSA workload root directory.")
params += string_param("SERVICES", "user-service,transaction-service,status-service,file-service,settings-service,frontend", "Comma-separated service list.")
params += string_param("NAMESPACE", namespace, "Target Kubernetes namespace.")
params += string_param("REGISTRY_URL", registry_url, "Registry endpoint as seen from the Jenkins container.")
params += string_param("REGISTRY_PROJECT", registry_project, "Harbor project.")
params += string_param("IMAGE_TAG", "", "Image tag. Defaults to BUILD_NUMBER when blank.")
params += string_param("KUBECONFIG", "/var/jenkins_home/kubeconfig", "Kubeconfig path in the Jenkins container.")
params += choice_param("DEPLOY_MODE", ["helm", "argocd"], deploy_mode, "MSA deployment mode.")
params += bool_param("ENFORCE_GATE", False, "Fail the pipeline when the security gate blocks.")
params += string_param("HELM_RELEASE", "vulnbank-msa", "Helm release name.")
params += string_param("HELM_CHART_DIR", "gitops-manifest-repo/helm/vulnbank-msa", "Helm chart directory.")
params += string_param("GITOPS_APP_DIR", "gitops-manifest-repo/apps/vulnbank-msa/dev", "GitOps app environment directory in the checked-out GitOps repo.")
params += string_param("ARGOCD_APP_MANIFEST", "gitops-manifest-repo/argocd/applications/vulnbank-msa-dev.yaml", "ArgoCD Application manifest.")
params += string_param("ARGOCD_APP_NAME", argocd_app_name, "ArgoCD Application name.")
params += string_param("SONAR_HOST_URL", sonar_host_url, "SonarQube URL as seen from the Jenkins container.")
params += password_param("SONAR_TOKEN", "", "SonarQube token for the vulnbank-msa project.")
params += string_param("REGISTRY_USERNAME", "", f"Runtime registry username. Trigger script passes Harbor robot from Jenkins credential {credential_id}.")
params += password_param("REGISTRY_PASSWORD", "", f"Runtime registry password/token. Trigger script passes Harbor robot from Jenkins credential {credential_id}.")

credentials_xml = f"<credentialsId>{esc(git_credentials_id)}</credentialsId>" if git_credentials_id else ""

xml = f"""<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin=\"workflow-job\">
  <actions/>
  <description>VulnBank MSA DevSecOps Golden Path: Jenkins build, Harbor push, GitOps update, ArgoCD sync, kind deploy, evidence.</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
{params}      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class=\"org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition\" plugin=\"workflow-cps\">
    <scm class=\"hudson.plugins.git.GitSCM\" plugin=\"git\">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>{esc(repo_url)}</url>
          {credentials_xml}
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/{esc(branch)}</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class=\"empty-list\"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile.msa</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
"""

with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write(xml)
print(f"wrote {sys.argv[1]} for {job_name}")
PY

crumb_args=()
while IFS= read -r item; do
  crumb_args+=("${item}")
done < <(jenkins_crumb_header_args)

job_url="${JENKINS_URL%/}/job/$(urlencode "${JENKINS_JOB_NAME}")"
if jenkins_curl GET "${job_url}/api/json" >/dev/null 2>&1; then
  jenkins_curl POST "${job_url}/config.xml" "${crumb_args[@]}" \
    -H 'Content-Type: application/xml' \
    --data-binary @"${job_xml}" >/dev/null
  log "Updated Jenkins Pipeline job: ${JENKINS_JOB_NAME}"
else
  jenkins_curl POST "${JENKINS_URL%/}/createItem?name=$(urlencode "${JENKINS_JOB_NAME}")" "${crumb_args[@]}" \
    -H 'Content-Type: application/xml' \
    --data-binary @"${job_xml}" >/dev/null
  log "Created Jenkins Pipeline job: ${JENKINS_JOB_NAME}"
fi

log "Pipeline repo: ${pipeline_repo_url}"
log "Jenkins REGISTRY_URL default: ${registry_url}"
