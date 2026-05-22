# Registry Notes

이 템플릿의 local compatibility registry 기본값은 아래와 같습니다.

```text
localhost:9092
```

local registry project 기본값:

```text
secure-delivery
```

이 값들은 local 기본값일 뿐이며 프로젝트 정체성이 아닙니다.

## Port Isolation

기존 로컬 실습 환경이 이미 `localhost` port `8082`에서 Harbor를 노출할 수 있습니다. 그래서 `secure-k8s-delivery-path`는 local profile 기본값으로 `localhost:9092`를 사용합니다.

`9090`은 Prometheus에서 자주 쓰이므로 이 템플릿의 기본 registry port로 사용하지 않습니다.

local compose service를 실행하기 전에 host port 충돌을 확인하세요.

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

compose 파일은 host port `9092`를 registry container port `5000`에 매핑합니다. local endpoint를 바꿔야 한다면 Helm/ArgoCD 구조를 바꾸지 말고 env/profile 값을 바꾸세요.

## kind Pull Behavior

kind node 내부에서 `localhost:9092`는 Docker host registry가 아니라 node container 자신을 가리킵니다. 실제 kind image pull 검증에는 containerd registry mirror가 필요할 수 있습니다.

기존 실습 환경에 port `8082` mirror가 이미 있다면, 이 템플릿은 `secure-path-dev` namespace와 별도 `9092` mirror entry로 분리해서 테스트하세요.

## Credentials

`scripts/registry-login.sh`는 아래 환경변수를 지원합니다.

```text
REGISTRY_USERNAME
REGISTRY_PASSWORD
```

두 값이 모두 있으면 script가 `docker login`을 수행합니다.

둘 중 하나라도 없으면 warning을 출력하고 계속 진행합니다. local lab에서 Docker가 이미 로그인되어 있거나 insecure registry가 설정된 경우를 지원하기 위함입니다.

운영 환경에서는 아래 방식을 권장합니다.

- Jenkins Credentials
- Harbor Robot Account
- ECR IAM auth

## AWS

AWS profile에서는 `localhost:9092`가 아니라 ECR 또는 DNS 기반 Harbor를 사용해야 합니다.

