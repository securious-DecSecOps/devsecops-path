# Golden Path

이 저장소는 특정 앱 하나를 배포하기 위한 repo가 아니라 Golden Path 템플릿입니다.

목표는 여러 취약/실습 워크로드를 하나의 표준 Kubernetes DevSecOps 경로에 태우는 것입니다.

```text
Source Code
-> Jenkins Pipeline
-> Docker Build
-> Trivy Scan
-> Security Gate
-> Harbor Registry
-> Helm Chart
-> GitOps Repo image tag update
-> ArgoCD Sync
-> Kubernetes Deploy
-> Evidence Reports
```

## Local MVP와 표준 경로

local MVP에서는 `DEPLOY_MODE=kubectl`을 사용해 kind 환경에서 registry-to-runtime 경로를 빠르게 검증할 수 있습니다.

그렇다고 Helm과 ArgoCD가 future-only 컴포넌트라는 뜻은 아닙니다. 공식 profile은 아래 세 가지 배포 모드를 모두 지원합니다.

- `kubectl`
- `helm`
- `argocd`

local profile은 기존 로컬 실습 환경과 충돌하지 않도록 아래 값을 기본으로 사용합니다.

```text
REGISTRY_URL=localhost:9092
REGISTRY_PROJECT=secure-delivery
NAMESPACE=secure-path-dev
```

local, Helm, ArgoCD 경로를 오갈 때는 구조를 바꾸기보다 registry endpoint와 profile 값만 바꾸는 방식을 지향합니다.

## 이 구조를 쓰는 이유

모든 워크로드가 같은 최소 통제를 재사용해야 합니다.

- 하나의 build contract
- 하나의 scan contract
- 하나의 gate policy
- 하나의 image naming pattern
- 하나의 deployment profile model
- 하나의 evidence map

이렇게 해야 `vulnbank`, `wrongsecrets`, `online-boutique` 같은 워크로드가 각각 별도 프로젝트처럼 흩어지지 않습니다.

## Policy Extension Points

기본 템플릿은 Trivy 기반의 최소 security gate만 구현합니다. 팀 상황에 따라 같은 경로에 아래 정책 입력을 추가할 수 있습니다.

- SBOM 생성 및 추후 SBOM 재분석
- manifest/IaC 검사
- secret scanning
- image signing 및 verification
- alerting
- DAST/runtime validation evidence

이 항목들은 local MVP 필수 서비스가 아니라 확장 포인트입니다.

## GitOps Commit Push

`DEPLOY_MODE=argocd`에서 GitOps loop를 닫으려면 Jenkins가 `gitops-manifest-repo`의 image tag 변경을 GitHub로 commit/push할 수 있어야 합니다.

필요한 credential은 GitHub PAT입니다.

```text
Required repo permission:
- gitops-manifest-repo Contents Read/Write
```

로컬 WSL PoC에서는 다음 파일에 저장합니다. 이 경로는 `.gitignore` 대상입니다.

```bash
cat > .local/wsl-poc/github-pat.env <<'EOF'
GITHUB_USER=<github-username>
GITHUB_PAT=<github-personal-access-token>
EOF
chmod 600 .local/wsl-poc/github-pat.env
```

이후 bootstrap을 다시 실행하면 Jenkins credential이 등록됩니다.

```bash
RUN_BUILD=false WAIT_ARGOCD=false bash bootstrap/local-wsl/configure.sh
```

Jenkinsfile.msa는 `DEPLOY_MODE=argocd`일 때만 `GitOps Commit Push` stage를 실행합니다.

```text
Jenkins build
-> Harbor push
-> update-gitops-services.sh
-> gitops-commit-push.sh
-> GitHub gitops-manifest-repo commit
-> ArgoCD auto-sync
-> Kubernetes rollout
```

`DEPLOY_MODE=helm`에서는 직접 Helm 배포 흐름이므로 GitOps commit/push stage가 skip됩니다.
