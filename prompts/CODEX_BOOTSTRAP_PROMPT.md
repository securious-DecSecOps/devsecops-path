# Codex Bootstrap Prompt

You are a DevSecOps/Kubernetes implementation agent.

The current working directory is:

```text
/home/wngus/secure-k8s-delivery-path
```

Treat the current directory as the repository root.

Before implementing, read these files if present:

```text
CODEX_CONTEXT.md
docs/PROJECT_DIRECTION.md
docs/CURRENT_STATUS.md
docs/LOCAL_KIND_HARBOR_NOTE.md
docs/AWS_MIGRATION_CONTEXT.md
docs/CODEX_IMPLEMENTATION_REQUIREMENTS.md
```

## Hard rules

- Do not modify `/home/wngus/devsecops`.
- Do not modify `/home/wngus/devsecops/local-mvp`.
- Do not modify `/home/wngus/devsecops/microservices-demo`.
- Do not reconfigure Jenkins/Harbor/kind unless explicitly asked.
- Do not use `secubank` as the core project name.
- Keep the core project domain-neutral: `secure-k8s-delivery-path`.
- `secubank` may only remain in historical notes about the older local lab.

## Build the repository

Create the full repository structure described in:

```text
docs/CODEX_IMPLEMENTATION_REQUIREMENTS.md
```

Implement a local-kind Jenkins Pipeline MVP:

```text
Checkout
→ Docker Build
→ Trivy Scan
→ Security Gate
→ Registry Login
→ Registry Push
→ Deploy using DEPLOY_MODE=kubectl|helm|argocd
→ Collect Evidence
→ Archive Evidence
```

Use local compatibility defaults:

```text
APP_NAME=myapp
NAMESPACE=secure-path-dev
REGISTRY_URL=localhost:9092
REGISTRY_PROJECT=secure-delivery
IMAGE_TAG=${BUILD_NUMBER}
KUBECONFIG=/var/jenkins_home/kubeconfig
REPORT_DIR=reports/dev/${BUILD_NUMBER}
ENFORCE_GATE=false
REGISTRY_USERNAME=admin
REGISTRY_PASSWORD=Harbor12345
```

The local password fallback is MVP-only. Document that production must use Jenkins Credentials, Harbor Robot Account, or ECR IAM auth.

Helm and ArgoCD are part of the standard deployment path and must be included
from the first repository implementation. Do not treat them as future-only
components.

After implementation, print:

1. File tree
2. How to chmod scripts
3. How to git init/add/commit
4. How to configure Jenkins Pipeline script from SCM
5. Local MVP success criteria
