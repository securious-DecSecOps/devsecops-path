# WSL Local PoC Wiring Guide

이 문서는 기존 WSL 실습 환경에 VulnBank MSA PoC를 추가로 연결하는 절차입니다.

대상 흐름은 다음입니다.

```text
Jenkins build
-> Harbor push
-> GitOps image tag update
-> ArgoCD sync
-> kind deploy
-> integration test and evidence
```

기존 monolith ArgoCD App인 `secubank-myapp-dev`, `secubank-online-boutique-dev`, `secubank-vulnbank-dev`는 건드리지 않습니다. MSA는 4번째 App인 `secubank-vulnbank-msa-dev`로 추가합니다.

## Prerequisites

실행 전 확인할 항목입니다.

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
kubectl config current-context
kubectl get ns argocd
kubectl -n argocd get applications.argoproj.io
curl -fsS http://localhost:8082/api/v2.0/ping
curl -fsS http://localhost:8083/login >/dev/null
```

기대 환경:

```text
Jenkins container: secubank-jenkins
Jenkins URL: http://localhost:8083
Harbor URL: http://localhost:8082
Harbor default admin: admin / Harbor12345
kind cluster: devsecops
kubectl context: kind-devsecops
ArgoCD namespace: argocd
MSA target namespace: secure-path-dev
```

GitOps repo도 먼저 GitHub에 있어야 합니다. 기본값은 아래 URL입니다.

```bash
export GITOPS_REPO_URL=https://github.com/securious-DecSecOps/gitops-manifest-repo.git
```

이 repo에는 최소한 다음 경로가 있어야 합니다.

```text
apps/vulnbank-msa/dev
```

해당 경로는 Helm chart를 참조하는 Kustomize/Helm 구조여야 하며, 현재 source repo의 `gitops/apps/vulnbank-msa/dev` 구조를 기준으로 준비합니다.

## Configure

Jenkins API 인증이 필요한 환경이면 먼저 Jenkins API token을 export합니다.

```bash
export JENKINS_URL=http://localhost:8083
export JENKINS_USER=<jenkins-user>
export JENKINS_TOKEN=<jenkins-api-token>
```

Harbor 기본값은 local PoC 기본값으로 이미 들어 있습니다.

```bash
export HARBOR_URL=http://localhost:8082
export HARBOR_ADMIN_USER=admin
export HARBOR_ADMIN_PASSWORD=Harbor12345
```

전체 wiring:

```bash
bash bootstrap/local-wsl/configure.sh
```

configure는 다음을 순서대로 수행합니다.

```text
1. Harbor secubank project 생성 또는 skip
2. Harbor robot account 생성 또는 cached credential 사용
3. Jenkins credential 등록 또는 갱신
4. Jenkins Pipeline job vulnbank-msa-dev 생성 또는 갱신
5. Jenkins build trigger
6. ArgoCD Application secubank-vulnbank-msa-dev apply
7. ArgoCD Synced + Healthy 대기
```

Jenkins build까지는 아직 실행하지 않고 configuration만 추가하려면 다음처럼 실행합니다.

```bash
RUN_BUILD=false WAIT_ARGOCD=false bash bootstrap/local-wsl/configure.sh
```

Jenkins 컨테이너에서 Harbor를 `harbor:8082`로 볼 수 없으면 script가 다음 후보를 자동 확인합니다.

```text
harbor:8082
host.docker.internal:8082
<WSL host IP>:8082
```

자동 확인이 실패하면 수동으로 지정합니다.

```bash
export REGISTRY_URL_FOR_JENKINS=host.docker.internal:8082
bash bootstrap/local-wsl/configure.sh
```

## Verify

ArgoCD sync 이후 통합 테스트와 evidence 수집을 실행합니다.

```bash
bash bootstrap/local-wsl/verify.sh
```

verify는 다음을 수행합니다.

```text
1. kubectl -n secure-path-dev port-forward svc/vulnbank-msa-frontend 18080:8080
2. scripts/test-msa-integration.sh 실행
3. scripts/collect-msa-evidence.sh 실행
4. reports/dev/wsl-poc/evidence/summary.txt 7/7 PASS 확인
```

포트가 이미 사용 중이면 다른 포트를 지정합니다.

```bash
FRONTEND_LOCAL_PORT=18081 bash bootstrap/local-wsl/verify.sh
```

## Troubleshooting

### GitOps repo가 없거나 비어 있음

증상:

```text
GitOps repo is not reachable
Application did not become Synced + Healthy
```

해결:

```bash
export GITOPS_REPO_URL=<your-gitops-manifest-repo-url>
git ls-remote "${GITOPS_REPO_URL}" main
```

GitOps repo 안에 `apps/vulnbank-msa/dev`가 있는지 확인합니다.

### Jenkins API 인증 실패

증상:

```text
Jenkins build trigger failed
HTTP 401 또는 403
```

해결:

```bash
export JENKINS_USER=<jenkins-user>
export JENKINS_TOKEN=<jenkins-api-token>
bash bootstrap/local-wsl/configure.sh
```

### Harbor robot secret을 다시 알 수 없음

Harbor는 기존 robot account secret을 다시 보여주지 않습니다. 이 repo의 bootstrap은 생성 직후 secret을 `.local/wsl-poc/harbor-robot.env`에 저장합니다. 이 경로는 `.gitignore`에 포함되어야 하며 Git에 올리면 안 됩니다.

해당 파일이 없고 robot account가 이미 있으면 다음 중 하나를 선택합니다.

```bash
export HARBOR_ROBOT_USERNAME=<robot-account-name>
export HARBOR_ROBOT_PASSWORD=<robot-secret>
bash bootstrap/local-wsl/20-jenkins-credentials.sh
```

또는 Harbor UI에서 이 PoC용 robot만 재생성합니다.

### Jenkins 컨테이너에서 Harbor 접근 실패

증상:

```text
docker login harbor:8082 실패
```

해결:

```bash
export REGISTRY_URL_FOR_JENKINS=host.docker.internal:8082
bash bootstrap/local-wsl/30-jenkins-job.sh
```

WSL host IP를 직접 지정할 수도 있습니다.

```bash
export REGISTRY_URL_FOR_JENKINS=<wsl-host-ip>:8082
```

### kind context가 다름

증상:

```text
Current kubectl context is not kind-devsecops
```

해결:

```bash
kubectl config use-context kind-devsecops
```

### 18080 포트 충돌

증상:

```text
Local port 18080 is already in use
```

해결:

```bash
FRONTEND_LOCAL_PORT=18081 bash bootstrap/local-wsl/verify.sh
```

## What This Does Not Do

이 bootstrap은 도구를 새로 설치하지 않습니다.

```text
apt install 하지 않음
docker run new container 하지 않음
kind create cluster 하지 않음
helm install 하지 않음
Jenkins/Harbor/kind/ArgoCD 재설치 또는 재시작하지 않음
기존 monolith ArgoCD App 수정하지 않음
```

ArgoCD가 Helm/Kustomize를 실행해서 desired state를 적용합니다.
