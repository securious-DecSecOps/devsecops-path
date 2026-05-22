# Secure K8s Delivery Path

`secure-k8s-delivery-path`는 여러 취약/실습 워크로드를 동일한 Kubernetes DevSecOps Golden Path에 반복적으로 온보딩하기 위한 오픈소스 템플릿 repo다.

현재 핵심 워크로드는 `examples/vulnbank-msa`이며, 이는 완전 독립형 Cloud-Native MSA가 아니라 기존 VulnBank PHP 모놀리스를 서비스별 컨테이너와 API 경계로 1차 분해한 **Shared-DB 기반 MSA 전환 PoC**다.

표준 경로:

```text
Source Code
-> Jenkins Pipeline
-> Docker Build
-> Trivy Scan
-> Security Gate
-> Registry Push
-> GitOps Image Tag Update
-> Helm 또는 ArgoCD Deploy
-> Kubernetes Runtime
-> Evidence Reports
```

## 1. Quickstart

### 1.1 로컬 전제 조건

이 repo는 기존 Docker, Jenkins, Harbor, kind, K3s 설정을 자동으로 변경하지 않는다.

필요 도구:

```bash
docker --version
kubectl version --client=true
helm version
trivy --version
python3 --version
git --version
```

로컬 기본값:

```text
NAMESPACE=secure-path-dev
REGISTRY_URL=localhost:9092
REGISTRY_PROJECT=secure-delivery
APP_NAME=vulnbank-msa
SERVICES=user-service,transaction-service,status-service,file-service,settings-service,frontend
```

기존 실습 Harbor가 `localhost:8082`를 쓰는 경우를 피하기 위해 이 템플릿의 local registry 기본 포트는 `9092`다.

### 1.2 MSA 이미지 빌드

```bash
cd /home/wngus/secure-k8s-delivery-path
chmod +x scripts/*.sh

APP_NAME=vulnbank-msa \
MSA_WORKLOAD_DIR=examples/vulnbank-msa \
SERVICES=user-service,transaction-service,status-service,file-service,settings-service,frontend \
REGISTRY_URL=localhost:9092 \
REGISTRY_PROJECT=secure-delivery \
IMAGE_TAG=dev \
REPORT_DIR=reports/dev/manual \
bash scripts/build-services.sh
```

### 1.3 Helm 렌더링 검증

```bash
helm lint helm/vulnbank-msa
helm template vulnbank-msa helm/vulnbank-msa
```

### 1.4 Helm 배포

```bash
helm upgrade --install vulnbank-msa helm/vulnbank-msa \
  --namespace secure-path-dev \
  --create-namespace \
  --set namespace=secure-path-dev
```

배포 확인:

```bash
kubectl get pods -n secure-path-dev
kubectl get services -n secure-path-dev
kubectl rollout status deployment/user-service -n secure-path-dev
kubectl rollout status deployment/transaction-service -n secure-path-dev
kubectl rollout status deployment/settings-service -n secure-path-dev
kubectl rollout status deployment/file-service -n secure-path-dev
kubectl rollout status deployment/status-service -n secure-path-dev
kubectl rollout status deployment/frontend -n secure-path-dev
```

### 1.5 포트포워딩

```bash
kubectl -n secure-path-dev port-forward svc/vulnbank-msa-frontend 8080:8080
```

브라우저 또는 curl 대상:

```text
http://localhost:8080
```

### 1.6 통합 취약점 재현 테스트

```bash
FRONTEND_URL=http://localhost:8080 bash scripts/test-msa-integration.sh
```

## 2. Architecture

### 2.1 현재 아키텍처 정의

`examples/vulnbank-msa`는 **Shared-DB 기반 MSA 전환 PoC**다.

정확한 의미:

```text
기존 VulnBank 모놀리식 PHP 레거시
-> 서비스별 Docker image 분리
-> 서비스별 API entrypoint 분리
-> Kubernetes Service 분리
-> 단일 vulnbank-db 공유
```

현재 서비스:

| 서비스 | 역할 |
| --- | --- |
| `frontend` | 원본 UI와 gateway/router |
| `user-service` | 로그인, 회원가입, 세션 확인 |
| `transaction-service` | 송금, 잔액 조회, 거래내역 조회 |
| `settings-service` | 회원정보 변경, 비밀번호 변경, 설정 |
| `file-service` | 프로필 파일 업로드 및 파일 제공 |
| `status-service` | 상태 점검, 대시보드 통계 |
| `vulnbank-db` | shared MariaDB schema |

라우팅:

```text
/api/v1/auth/*          -> user-service
/api/v1/transactions/*  -> transaction-service
/api/v1/settings/*      -> settings-service
/api/v1/files/*         -> file-service
/api/v1/status/*        -> status-service
```

### 2.2 명확한 한계

이 구조는 완전 독립형 Cloud-Native MSA가 아니다.

현재 제약:

- 모든 백엔드 서비스가 단일 `vulnbank-db`를 공유한다.
- 여러 서비스가 `shared/php/inc/` 공통 PHP 모듈을 공유한다.
- 서비스별 독립 DB ownership은 아직 없다.
- 이벤트 기반 데이터 동기화는 아직 없다.
- 서비스 간 API contract 검증은 아직 제한적이다.
- 데이터 계층의 느슨한 결합은 아직 달성하지 못했다.

따라서 발표나 문서에서는 다음 표현을 사용한다.

```text
Shared-DB 패턴 기반의 VulnBank MSA 전환 PoC
```

상세 문서:

```text
docs/vulnbank-msa-migration.md
```

### 2.3 AWS K3s 이관 관점

AWS VM에서는 local registry 값인 `localhost:9092`를 사용하지 않는다.

AWS에서 바꿀 핵심 값:

```text
REGISTRY_URL=<ECR 또는 Harbor DNS>
REGISTRY_PROJECT=secure-delivery
IMAGE_TAG=<Jenkins build number 또는 Git SHA>
KUBECONFIG=/var/jenkins_home/kubeconfig
NAMESPACE=security-lab
DEPLOY_MODE=argocd
```

AWS profile 예시:

```text
env/aws-k3s.env.example
```

## 3. Jenkins Pipeline Flow

단일 앱은 `Jenkinsfile`을 사용하고, VulnBank MSA PoC는 `Jenkinsfile.msa`를 사용한다.

`Jenkinsfile.msa` 단계:

```text
Checkout
-> Preflight Tools
-> Prepare Metadata
-> Docker Build Services
-> Trivy Scan Services
-> Security Gate
-> Registry Login
-> Registry Push Services
-> Deploy
-> Collect Evidence
-> Archive Evidence
```

주요 Jenkins 파라미터:

```text
WORKLOAD_NAME=vulnbank-msa
APP_NAME=vulnbank-msa
MSA_WORKLOAD_DIR=examples/vulnbank-msa
SERVICES=user-service,transaction-service,status-service,file-service,settings-service,frontend
NAMESPACE=secure-path-dev
REGISTRY_URL=localhost:9092
REGISTRY_PROJECT=secure-delivery
DEPLOY_MODE=helm
HELM_CHART_DIR=helm/vulnbank-msa
GITOPS_APP_DIR=gitops/apps/vulnbank-msa/dev
ARGOCD_APP_MANIFEST=argocd/applications/vulnbank-msa-dev.yaml
```

보안 단계:

```text
scripts/trivy-scan-services.sh
scripts/security-gate-services.sh
```

기본 MSA gate 정책:

```text
GATE_MAX_CRITICAL=0
GATE_MAX_HIGH=3
```

GitOps와 배포 단계:

```text
scripts/update-gitops-services.sh
scripts/deploy-msa-helm.sh
scripts/deploy-argocd.sh
```

Registry push는 security gate가 PASS일 때만 진행된다.

```text
scripts/push-services.sh
```

## 4. Evidence-as-Code

Pipeline 증적은 기본적으로 아래 경로에 저장된다.

```text
reports/dev/<build-number>/
```

MSA 핵심 증적:

```text
reports/dev/<build-number>/metadata.txt
reports/dev/<build-number>/trivy/trivy-report-user-service.json
reports/dev/<build-number>/trivy/trivy-report-transaction-service.json
reports/dev/<build-number>/trivy/trivy-report-settings-service.json
reports/dev/<build-number>/trivy/trivy-report-file-service.json
reports/dev/<build-number>/trivy/trivy-report-status-service.json
reports/dev/<build-number>/trivy/trivy-report-frontend.json
reports/dev/<build-number>/gate/msa-gate-summary.txt
reports/dev/<build-number>/registry/push-services-summary.txt
reports/dev/<build-number>/gitops/diff.txt
reports/dev/<build-number>/gitops/updated-images.txt
reports/dev/<build-number>/kubernetes/pods.txt
reports/dev/<build-number>/kubernetes/services.txt
reports/dev/<build-number>/kubernetes/deployments.txt
reports/dev/<build-number>/events/pod-describe.txt
reports/dev/<build-number>/events/image-pull-events.txt
reports/dev/<build-number>/evidence/msa-vulnerability-evidence.json
reports/dev/<build-number>/evidence/summary.txt
reports/dev/<build-number>/evidence-map.md
reports/dev/<build-number>/evidence-files.txt
```

`scripts/collect-msa-evidence.sh`는 다음 의도된 취약점 재현 결과를 수집한다.

| 증적 | 목적 |
| --- | --- |
| 음수 송금 | 금융 로직 검증 실패 재현 |
| IDOR 거래내역 조회 | 타인 계좌 거래내역 조회 재현 |
| IDOR 회원정보 변경 | 타인 사용자 정보 변경 재현 |
| `.php` 파일 업로드 및 실행 | 파일 업로드 검증 부재 재현 |

수동 실행:

```bash
REPORT_DIR=reports/dev/manual \
WORKLOAD_NAME=vulnbank-msa \
APP_NAME=vulnbank-msa \
SERVICES=user-service,transaction-service,status-service,file-service,settings-service,frontend \
NAMESPACE=secure-path-dev \
DEPLOY_MODE=helm \
IMAGE_TAG=dev \
FRONTEND_URL=http://localhost:8080 \
bash scripts/collect-msa-evidence.sh
```

## 5. GitHub Upload Hygiene

GitHub 업로드 전 확인:

```bash
git status --short
git diff --check
```

커밋하면 안 되는 항목:

- `reports/` 아래 Jenkins evidence 산출물
- `.env`, `env/*.env` 같은 실제 환경 파일
- registry password, kubeconfig, cloud credential
- `.log`, `.tmp`, `.bak` 등 로컬 실험 파일
- `/tmp/`에 만든 임시 테스트 산출물
- IDE/editor 캐시

민감정보 확인 예시:

```bash
rg -n "PASSWORD=|SECRET=|TOKEN=|AWS_ACCESS_KEY|AWS_SECRET|kubeconfig|BEGIN .*PRIVATE KEY" .
```

`.gitignore`는 로컬 evidence, 로그, credential, 임시 파일이 Git 추적 대상에 들어가지 않도록 관리한다.

## 6. Non-goals

현재 범위에서 하지 않는 것:

- AWS 리소스 자동 생성
- Terraform 구현
- Ansible 구현
- EKS 구축
- 완전 독립 DB 기반 MSA 완성
- Kafka/RabbitMQ 이벤트 기반 전환
- SonarQube, Cilium, Falco 실제 런타임 통합
