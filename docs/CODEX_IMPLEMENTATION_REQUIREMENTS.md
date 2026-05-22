# Codex Implementation Requirements

## Required repository structure

```text
README.md
Jenkinsfile
.gitignore
jenkins/Dockerfile
jenkins/README.md
compose/docker-compose.local.yml
examples/simple-web/Dockerfile
examples/simple-web/index.html
examples/vulnbank/README.md
examples/wrongsecrets/README.md
examples/online-boutique/README.md
k8s/base/namespace.yaml
k8s/base/deployment.yaml
k8s/base/service.yaml
k8s/overlays/local-kind/kustomization.yaml
k8s/overlays/aws-k3s/kustomization.yaml
helm/simple-web/Chart.yaml
helm/simple-web/values.yaml
helm/simple-web/templates/deployment.yaml
helm/simple-web/templates/service.yaml
helm/simple-web/templates/namespace.yaml
gitops/apps/simple-web/dev/values.yaml
gitops/apps/simple-web/dev/kustomization.yaml
argocd/applications/simple-web-dev.yaml
scripts/build-image.sh
scripts/trivy-scan.sh
scripts/security-gate.sh
scripts/registry-login.sh
scripts/push-image.sh
scripts/deploy-helm.sh
scripts/update-gitops-image.sh
scripts/deploy-argocd.sh
scripts/deploy-kubectl.sh
scripts/collect-evidence.sh
env/local-kind.env.example
env/aws-k3s.env.example
docs/architecture.md
docs/golden-path.md
docs/workload-onboarding.md
docs/local-kind-runbook.md
docs/helm-runbook.md
docs/argocd-gitops-runbook.md
docs/aws-k3s-runbook.md
docs/registry-notes.md
docs/security-gate-policy.md
docs/evidence-policy.md
docs/cve-rescan-pipeline.md
docs/alerting-policy.md
docs/dast-runtime-validation.md
docs/future-sonarqube.md
docs/future-cilium-runtime-security.md
docs/troubleshooting.md
reports/.gitkeep
```

## Jenkinsfile stages

Required stages:

```text
Checkout
Preflight Tools
Prepare Metadata
Docker Build
Trivy Scan
Security Gate
Registry Login
Registry Push
Deploy
Collect Evidence
Archive Evidence
```

## Script requirements

Every script must include:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Scripts must use environment variables with sensible defaults.

Helm and ArgoCD are required parts of the standard deployment path. The
repository should still keep raw Kubernetes manifests useful for local
debugging and migration, but the primary deployable artifact is the Helm chart
referenced by ArgoCD Application manifests.

The Deploy stage must support:

```text
DEPLOY_MODE=kubectl -> scripts/deploy-kubectl.sh
DEPLOY_MODE=helm    -> scripts/deploy-helm.sh
DEPLOY_MODE=argocd  -> scripts/update-gitops-image.sh + scripts/deploy-argocd.sh
```

## Security gate

Policy:

```text
Critical > 0 => BLOCK
Critical = 0 => PASS
High => WARN / Accepted Risk in MVP
```

If `ENFORCE_GATE=false`, the pipeline should record BLOCK but not necessarily stop immediately.

## Evidence

Use:

```text
reports/dev/<build-number>/
```

Expected evidence:

```text
metadata.txt
docker/build.log
trivy/image-scan.json
trivy/image-scan.txt
gate/gate-result.txt
registry/login.log
registry/push.log
helm/rendered.yaml
helm/upgrade.log
helm/status.txt
gitops/diff.txt
argocd/app-status.txt
kubernetes/pods.txt
kubernetes/service.txt
kubernetes/deployment.txt
events/pod-describe.txt
events/image-pull-events.txt
evidence-files.txt
evidence-map.md
```
