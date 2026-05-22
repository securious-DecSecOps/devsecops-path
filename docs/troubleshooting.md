# Troubleshooting

## Docker Build 실패

확인:

```bash
docker --version
docker build -t simple-web:test examples/simple-web
```

Jenkins가 Docker에 접근하지 못하면 Docker socket 권한을 확인하세요.

## Trivy Scan 실패

확인:

```bash
trivy --version
trivy image simple-web:test
```

Trivy DB 업데이트가 실패하면 Jenkins container에서 네트워크 접근이 가능한지 확인하세요.

## Registry Push 실패

확인:

```bash
docker login localhost:9092
docker push localhost:9092/secure-delivery/simple-web:<tag>
```

local compose service를 시작하기 전에 host port 충돌을 확인하세요.

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

이 템플릿은 기존 로컬 실습 환경이 port `8082`를 사용할 수 있어 `9092`를 사용합니다. `9090`은 Prometheus에서 자주 쓰이므로 피합니다.

운영 환경에서는 Jenkins Credentials, Harbor Robot Account, ECR IAM auth를 사용하세요.

## kind가 localhost:9092에서 image pull을 못하는 경우

kind node 내부에서 `localhost`는 node container 자신을 의미합니다. `localhost:9092`로 image pull을 하려면 containerd mirror workaround가 필요할 수 있습니다.

다른 실습 환경에 port `8082` mirror가 이미 있다면, 이 템플릿은 `secure-path-dev` namespace와 별도 `9092` mirror로 분리해서 테스트하세요.

## Helm 실패

확인:

```bash
helm lint helm/simple-web
helm template simple-web helm/simple-web
```

## ArgoCD Sync 실패

확인:

```bash
kubectl get crd applications.argoproj.io
kubectl get application simple-web-dev -n argocd
```

또한 아래 파일의 placeholder repo URL을 실제 GitHub repo URL로 바꿨는지 확인하세요.

```text
argocd/applications/simple-web-dev.yaml
```

## Gate가 Pipeline을 차단하는 경우

아래 파일을 확인하세요.

```text
reports/dev/<build-number>/gate/gate-result.txt
```

local evidence 수집 목적이면 `ENFORCE_GATE=false`를 사용하고, 더 엄격한 CI에서는 `ENFORCE_GATE=true`를 유지합니다.

