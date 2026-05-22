# Workload Onboarding

새 워크로드를 Golden Path에 추가할 때는 아래 순서로 진행합니다.

1. `examples/<workload>` 디렉터리를 만듭니다.
2. Dockerfile과 애플리케이션 소스를 준비합니다.
3. Kubernetes manifest 또는 Helm values를 준비합니다.
4. 환경 profile을 만들거나 기존 profile을 수정합니다.
5. Jenkins parameter를 워크로드에 맞게 바꿉니다.
6. Trivy scan 결과를 확인합니다.
7. Security Gate 결과를 확인합니다.
8. `DEPLOY_MODE=kubectl`, `DEPLOY_MODE=helm`, `DEPLOY_MODE=argocd` 중 하나를 선택합니다.
9. Evidence report를 확인합니다.

## Minimum Workload Contract

각 워크로드는 최소한 아래 값을 정의할 수 있어야 합니다.

```text
WORKLOAD_NAME=<workload>
WORKLOAD_DIR=examples/<workload>
APP_NAME=<kubernetes-app-name>
DOCKERFILE_PATH=examples/<workload>/Dockerfile
BUILD_CONTEXT=examples/<workload>
NAMESPACE=<target-namespace>
REGISTRY_URL=<registry>
REGISTRY_PROJECT=<project>
DEPLOY_MODE=<kubectl|helm|argocd>
```

## Current Workloads

`simple-web`은 local MVP에서 실제로 실행 가능한 워크로드입니다.

`vulnbank`는 AWS VM/k3s에서 첫 실전 워크로드로 온보딩할 adapter 후보입니다.

`wrongsecrets`와 `online-boutique`는 future onboarding placeholder입니다.

