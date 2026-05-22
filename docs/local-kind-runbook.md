# Local kind Runbook

이 문서는 `simple-web`을 `DEPLOY_MODE=kubectl`로 검증하는 local-kind 실행 가이드입니다.

## 가정

- Docker Desktop이 실행 중입니다.
- Jenkins가 Docker에 접근할 수 있습니다.
- 템플릿 registry endpoint가 Jenkins 환경에서 `localhost:9092`로 접근 가능합니다.
- kind cluster가 이미 준비되어 있습니다.
- Jenkins 컨테이너 안에 `/var/jenkins_home/kubeconfig`가 있습니다.

이 저장소는 기존 Jenkins, Harbor, kind, Docker Desktop 설정을 수정하지 않습니다.

## Local Environment

`env/local-kind.env.example`을 기준 profile로 사용합니다.

```text
WORKLOAD_NAME=simple-web
APP_NAME=simple-web
NAMESPACE=secure-path-dev
REGISTRY_URL=localhost:9092
REGISTRY_PROJECT=secure-delivery
DEPLOY_MODE=kubectl
ENFORCE_GATE=false
```

앱 이름 충돌까지 피하고 싶으면 아래처럼 override할 수 있습니다.

```text
APP_NAME=secure-path-simple-web
```

기존 로컬 실습 환경이 `localhost` port `8082`와 별도 개발 namespace를 사용할 수 있습니다. 이 템플릿은 충돌을 피하기 위해 `localhost:9092`, `secure-path-dev`, `secure-delivery`를 사용합니다.

`9090`은 Prometheus에서 자주 사용되므로 이 템플릿의 registry port로 쓰지 않습니다.

compose 실행 전 포트 충돌을 확인하세요.

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

## Jenkins 설정

Jenkins에서 새 Pipeline item을 만들고 아래처럼 설정합니다.

```text
Pipeline Definition: Pipeline script from SCM
SCM: Git
Repository URL: https://github.com/<YOUR_ID>/secure-k8s-delivery-path.git
Branch Specifier: */main
Script Path: Jenkinsfile
```

이후 `Build Now`를 실행합니다.

## Harbor/Registry와 kind 주의사항

`localhost:9092`는 local compatibility 기본값입니다. 하지만 kind node 컨테이너 내부에서 `localhost`는 WSL host가 아니라 node 컨테이너 자신을 의미합니다.

실제 kind image pull 검증에는 `localhost:9092`를 Docker host registry 주소로 매핑하는 containerd registry mirror가 필요할 수 있습니다. 기존 실습 환경에 `8082` mirror가 이미 있다면, 이 템플릿은 별도 `9092` mirror와 `secure-path-dev` namespace로 분리해서 테스트하세요.

이 저장소는 이 내용을 문서화만 하며, kind containerd 설정을 자동으로 바꾸지 않습니다.

registry endpoint 변경은 env/profile 값으로 처리해야 합니다. Helm/ArgoCD 표준 경로 자체를 바꿀 필요는 없습니다.

## Local Validation Commands

```bash
bash -n scripts/*.sh
helm lint helm/simple-web
helm template simple-web helm/simple-web
kubectl kustomize k8s/overlays/local-kind --load-restrictor=LoadRestrictionsNone
kubectl kustomize --enable-helm gitops/apps/simple-web/dev
kubectl apply --dry-run=client -f k8s/base
trivy --version
docker build -t simple-web:test examples/simple-web
```

일부 `kubectl apply --dry-run=client` 버전은 client dry-run이어도 현재 cluster API discovery를 시도할 수 있습니다. shell에서 cluster 접근이 안 되면 `kubectl kustomize`와 `helm template`으로 offline rendering을 먼저 확인하고, dry-run은 Jenkins/kubeconfig 환경에서 다시 실행하세요.

## 성공 기준

- Docker build 성공
- Trivy report archive
- Gate result 기록
- Image registry push
- Deployment rollout 성공
- Pod `Running`
- `evidence-map.md`에서 Git SHA, image, gate, registry, deploy status 연결 확인

