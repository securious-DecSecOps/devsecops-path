# CODEX_CONTEXT — Secure K8s Delivery Path

## 1. Project Identity

Core project name:

```text
secure-k8s-delivery-path
```

Display name:

```text
Secure K8s Delivery Path
```

This project is a reusable, domain-neutral DevSecOps delivery path template for Kubernetes workloads.

It must not be branded as a banking-only project.

## 2. Important Naming Decision

`secubank` is **not** the core project name.

`secubank` may appear only as:

- historical local lab context
- example workload or demo scenario
- historical graduation project context

The open-source template itself must stay domain-neutral.

Correct framing:

```text
Core template: secure-k8s-delivery-path
Example workloads: simple-web, vuln-bank, wrongsecrets, online-boutique
```

Incorrect framing:

```text
Core template: secubank-platform-template
```

## 3. Project Goal

The goal is to create a reproducible secure delivery pipeline:

```text
Source Code
→ Jenkins Pipeline
→ Docker Build
→ Trivy Scan
→ Security Gate
→ Registry Push
→ Helm Render/Package
→ GitOps Repo Image Tag Update
→ ArgoCD GitOps Deploy
→ Evidence Reports
```

This should become a reusable template that supports:

```text
local-kind
aws-k3s
aws-2vm
argocd-gitops
```

## 4. Current Local Environment

The user is working on WSL2 Ubuntu.

Existing local runtime/lab environment:

```text
WSL2 Ubuntu
Docker Desktop
kind cluster: devsecops
Jenkins container: secubank-jenkins
Harbor: localhost port 8082 in the older lab
Kubernetes namespace: older secubank development namespace
Template local registry default: localhost:9092
Template local namespace default: secure-path-dev
```

Existing project/lab path:

```text
/home/wngus/devsecops
```

New open-source template path:

```text
/home/wngus/secure-k8s-delivery-path
```

The new project path is separate from the existing graduation-project lab path.

## 5. Existing Manual Proof Already Completed

The user has manually verified the critical registry-to-runtime path.

Verified flow:

```text
Jenkins
→ Harbor Registry
→ kind node containerd image pull
→ Kubernetes Deployment
→ Pod Running
```

Manual proof details:

- Jenkins container could login to local Harbor.
- Jenkins container could push an image to Harbor.
- Harbor API confirmed image tag existence.
- kind node containerd mirror for the older local Harbor endpoint was configured.
- `crictl pull` succeeded on all kind nodes for the older local proof image.
- Kubernetes Deployment successfully rolled out.
- Pod reached `1/1 Running`.
- Pod image pull events showed:
  - `Pulling image`
  - `Successfully pulled image`
  - `Started container`
- Pod Image ID matched Harbor digest.

This is not the final pipeline yet. It is manual proof that the registry-to-Kubernetes runtime path works.

## 6. Current Next Step

The next step is to convert the manual proof into a Jenkins Pipeline MVP using:

```text
Pipeline script from SCM
```

Meaning:

- Jenkins should not store the full pipeline inline in the UI.
- Jenkins should read `Jenkinsfile` from the Git repository.
- The pipeline should become version-controlled and reusable.

## 7. Local MVP Target

The local-kind MVP should perform:

```text
Checkout from Git
→ Docker Build
→ Trivy Scan
→ Security Gate
→ Registry Login
→ Registry Push
→ Helm Render/Package
→ GitOps Repo Image Tag Update
→ ArgoCD GitOps Deploy
→ Evidence Collection
→ Archive Evidence
```

## 8. Local Compatibility Defaults

For current local compatibility, use these defaults:

```text
APP_NAME=myapp
NAMESPACE=secure-path-dev
REGISTRY_URL=localhost:9092
REGISTRY_PROJECT=secure-delivery
IMAGE_TAG=${BUILD_NUMBER}
KUBECONFIG=/var/jenkins_home/kubeconfig
REPORT_DIR=reports/dev/${BUILD_NUMBER}
ENFORCE_GATE=false
```

These defaults are for the local-kind MVP only.

## 9. Security Warning

The local MVP may use:

```text
REGISTRY_USERNAME=admin
REGISTRY_PASSWORD=Harbor12345
```

only as a local smoke-test fallback.

The docs must clearly state:

- This is MVP-only.
- Do not commit production secrets.
- Production should use Jenkins Credentials.
- Harbor should use Robot Account.
- AWS should use ECR IAM auth or proper imagePullSecret.

## 10. What Must Not Be Modified

Do not modify or delete:

```text
/home/wngus/devsecops/local-mvp
/home/wngus/devsecops/microservices-demo
/home/wngus/devsecops
```

Do not attempt to reconfigure existing Jenkins/Harbor/kind unless explicitly asked.

The new project should be built in:

```text
/home/wngus/secure-k8s-delivery-path
```

## 11. Standard Path and Future Direction

Planned phases:

```text
Phase 1: local-kind MVP with Jenkins, Trivy, Helm, and ArgoCD
Phase 2: aws-k3s profile
Phase 3: aws-2vm structure
Phase 4: additional example workloads
Phase 5: additional supply-chain tools such as SonarQube
Phase 6: runtime security tools such as Cilium/Falco
```

Helm and ArgoCD are part of the standard delivery path from the beginning.
Do not treat them as future-only components.

Future phases may add more workloads, AWS profiles, SonarQube, Cilium, Falco,
policy enforcement, and runtime observability.
