# VulnBank Shared-DB 기반 MSA 전환 PoC

## 아키텍처 정의

본 프로젝트의 `examples/vulnbank-msa`는 **완전 독립형 Cloud-Native MSA**가 아니다.

현재 구조는 기존 VulnBank 모놀리식 PHP 레거시를 서비스별 컨테이너와 API 경계로 1차 분해한 **Shared-DB 패턴 기반의 MSA 전환 PoC 아키텍처**다.

즉, 목표는 "처음부터 새로 설계한 이상적인 MSA"가 아니라 다음을 검증하는 것이다.

1. 기존 취약 워크로드를 여러 서비스 이미지로 분해할 수 있는가.
2. 분해된 서비스들을 동일한 DevSecOps Golden Path에 태울 수 있는가.
3. 서비스별 build, scan, gate, push, deploy, evidence 흐름을 자동화할 수 있는가.
4. 원본의 의도된 취약점이 분산 환경에서도 재현되는지 증적화할 수 있는가.

## 현재 repo의 VulnBank 경로

| 경로 | 상태 | 목적 |
| --- | --- | --- |
| `examples/vulnbank` | upstream VulnBank monolith snapshot | 원본 취약 워크로드 보존 및 비교 기준 |
| `examples/vulnbank-msa` | Shared-DB 기반 MSA 전환 PoC | 원본 PHP 로직을 서비스별 컨테이너/API 경계로 분해 |

`examples/vulnbank`는 원본 코드의 기준점이다.  
`examples/vulnbank-msa`는 원본 VulnBank를 Golden Path에서 MSA 형태로 빌드, 스캔, 배포, 검증하기 위한 전환형 워크로드다.

## 현재 성과 요약

현재 `examples/vulnbank-msa`는 6개 서비스 단위로 분리되어 있다.

| 서비스 | 역할 | 현재 상태 |
| --- | --- | --- |
| `user-service` | 로그인, 회원가입, 세션 확인, 사용자 검증 | PHP 기반 API 구현 |
| `transaction-service` | 송금, 잔액 조회, 거래내역 조회 | PHP 기반 API 구현 |
| `settings-service` | 회원정보 수정, 비밀번호 변경, 설정 변경 | PHP 기반 API 구현 |
| `file-service` | 프로필 파일 업로드 및 파일 제공 | PHP 기반 API 구현 |
| `status-service` | 상태 점검, 대시보드 통계 조회 | PHP 기반 API 구현 |
| `frontend` | 원본 UI 및 API gateway 역할 | PHP gateway/router 구현 |

현재 자동화된 범위는 다음과 같다.

1. 6개 서비스의 독립 Docker image build
2. Helm chart 렌더링 및 Kubernetes 배포 구조
3. 서비스별 Trivy image scan
4. MSA 전체 Security Gate
5. Harbor 등 registry push 자동화
6. GitOps values image tag 갱신
7. Helm 또는 ArgoCD 배포 경로 연동
8. Jenkinsfile.msa 기반 pipeline stage 연동
9. Evidence-as-Code 방식의 취약점 재현 증적 수집

즉, 단일 앱 배포 repo가 아니라 `vulnbank-msa`라는 취약 워크로드를 서비스 단위로 나누어 Golden Path에 태우는 구조까지 구현되어 있다.

## 현재 MSA PoC 구조

```text
examples/vulnbank-msa/
├── shared/php/inc/
├── services/
│   ├── user-service/
│   ├── transaction-service/
│   ├── settings-service/
│   ├── file-service/
│   ├── status-service/
│   └── frontend/
└── services.list
```

배포 시 Kubernetes 내부 구조는 다음과 같은 형태를 가진다.

```text
frontend
  ├── /api/v1/auth/*          -> user-service
  ├── /api/v1/transactions/*  -> transaction-service
  ├── /api/v1/settings/*      -> settings-service
  ├── /api/v1/files/*         -> file-service
  └── /api/v1/status/*        -> status-service

user-service
transaction-service
settings-service
file-service
status-service
  └── shared database: vulnbank-db
```

서비스들은 독립 컨테이너와 독립 Kubernetes Service로 배포되지만, 데이터 계층은 현재 단일 `vulnbank-db`를 공유한다.

## Golden Path에서의 동작

단일 앱은 하나의 이미지와 하나의 보안 리포트를 만든다.

```text
simple-web
-> image 1개
-> Trivy report 1개
-> Security Gate 1개
```

MSA PoC는 서비스별 이미지와 서비스별 보안 리포트를 만든다.

```text
vulnbank-msa
-> user-service image
-> transaction-service image
-> settings-service image
-> file-service image
-> status-service image
-> frontend image
-> service별 Trivy scan
-> 전체 MSA Security Gate
-> registry push
-> GitOps values tag update
-> Helm 또는 ArgoCD deploy
-> Evidence archive
```

이 흐름은 `Jenkinsfile.msa`와 `scripts/*-services.sh` 계열 스크립트가 담당한다.

## 의도된 취약점 증적

현재 PoC는 분산 환경에서도 다음 취약 동작이 재현되는지 수집하도록 설계되어 있다.

| 취약점 | 증적 수집 위치 | 목적 |
| --- | --- | --- |
| 음수 송금 | `scripts/collect-msa-evidence.sh` | 금융 로직 검증 실패 재현 |
| IDOR 거래내역 조회 | `scripts/collect-msa-evidence.sh` | 타인 계좌 거래내역 조회 재현 |
| IDOR 회원정보 변경 | `scripts/collect-msa-evidence.sh` | 타인 사용자 정보 변경 재현 |
| `.php` 파일 업로드 및 실행 | `scripts/collect-msa-evidence.sh` | 파일 업로드 검증 부재 및 실행 가능성 재현 |

증적은 다음 위치에 저장된다.

```text
reports/dev/<build-number>/evidence/msa-vulnerability-evidence.json
reports/dev/<build-number>/evidence/summary.txt
```

이 증적은 "취약점을 고쳤다"는 자료가 아니라, 취약 실습 워크로드의 의도된 결함이 MSA 전환 후에도 재현되는지 확인하는 자료다.

## 기술적 제약 사항

현재 구조는 전환 비용 최소화와 원본 데이터 정합성 유지를 위해 단일 `vulnbank-db` 스키마를 공유한다.

또한 여러 서비스가 `shared/php/inc/`의 공통 PHP 모듈을 함께 사용한다.

이 때문에 현재 아키텍처는 완벽한 서비스 간 느슨한 결합을 달성한 상태가 아니다.

구체적인 제약은 다음과 같다.

1. 서비스별 독립 DB ownership이 없다.
2. 서비스 간 데이터 소유 경계가 완전히 분리되어 있지 않다.
3. 공통 PHP 모듈 변경이 여러 서비스에 동시에 영향을 줄 수 있다.
4. 서비스 간 API contract 검증이 아직 충분히 자동화되어 있지 않다.
5. 데이터 동기화나 비동기 이벤트 기반 통신 구조가 없다.
6. 장애 격리와 독립 확장성은 컨테이너/배포 단위에서는 일부 확보되었지만 데이터 계층에서는 제한적이다.

따라서 현재 구현을 "완전한 Cloud-Native MSA"라고 표현하면 과장이다.

정확한 표현은 다음과 같다.

```text
기존 VulnBank 모놀리스를 서비스별 컨테이너와 API 경계로 1차 분해한
Shared-DB 기반 MSA 전환 PoC
```

## 왜 Shared-DB로 시작했는가

VulnBank 원본은 모놀리식 PHP 애플리케이션이며, 사용자, 계좌, 거래, 설정, 파일 정보가 하나의 DB 흐름에 강하게 결합되어 있다.

이 상태에서 곧바로 서비스별 DB를 분리하면 다음 비용이 발생한다.

1. 사용자/계좌/거래 데이터 소유권 재설계
2. 서비스 간 조회 API 재작성
3. 분산 트랜잭션 또는 보상 트랜잭션 설계
4. 초기 데이터 seed 구조 재설계
5. 원본 취약점 재현 조건 재검증
6. 기존 UI와 API 호출 흐름의 대규모 수정

따라서 현재 단계에서는 원본 취약점과 업무 흐름을 유지하면서 배포 단위와 API 경계를 먼저 분리하는 접근을 선택했다.

## 현재 실행 기준

Jenkins에서는 단일 앱용 `Jenkinsfile`이 아니라 `Jenkinsfile.msa`를 사용한다.

주요 환경값은 다음과 같다.

```text
WORKLOAD_NAME=vulnbank-msa
APP_NAME=vulnbank-msa
MSA_WORKLOAD_DIR=examples/vulnbank-msa
SERVICES=user-service,transaction-service,status-service,file-service,settings-service,frontend
HELM_CHART_DIR=helm/vulnbank-msa
GITOPS_APP_DIR=gitops/apps/vulnbank-msa/dev
ARGOCD_APP_MANIFEST=argocd/applications/vulnbank-msa-dev.yaml
```

Kubernetes 내부 서비스 주소는 Helm values에서 관리한다.

```text
USER_SERVICE_URL=http://vulnbank-msa-user-service:8080/api.php
TRANSACTION_SERVICE_URL=http://vulnbank-msa-transaction-service:8080/api.php
SETTINGS_SERVICE_URL=http://vulnbank-msa-settings-service:8080/api.php
FILE_SERVICE_URL=http://vulnbank-msa-file-service:8080/api.php
STATUS_SERVICE_URL=http://vulnbank-msa-status-service:8080/api.php
DB_HOST=vulnbank-db
```

## Next Step

2차 고도화 단계에서는 현재 Shared-DB PoC를 더 독립적인 MSA 구조로 발전시킨다.

### 1. 서비스별 DB Ownership 분리

각 서비스가 소유하는 데이터를 명확히 나눈다.

| 서비스 | 향후 DB ownership 후보 |
| --- | --- |
| `user-service` | 사용자, 인증, 세션, 권한 |
| `transaction-service` | 거래, 송금, 잔액 변경 이벤트 |
| `settings-service` | 시스템 설정, 사용자 프로필 설정 |
| `file-service` | 업로드 파일 메타데이터 |
| `status-service` | 상태 조회 결과, 운영 메트릭 |

### 2. 이벤트 기반 아키텍처 도입

서비스 간 데이터 동기화는 직접 DB 공유가 아니라 이벤트 기반으로 전환한다.

후보 기술은 다음과 같다.

```text
Kafka
RabbitMQ
```

예시 이벤트:

```text
UserCreated
UserProfileUpdated
TransferRequested
TransferApproved
TransferRejected
FileUploaded
SecurityFindingDetected
```

### 3. 서비스 간 API Contract 검증

서비스 간 호출은 명시적인 API contract를 기준으로 검증한다.

도입 후보:

```text
OpenAPI schema
contract test
consumer-driven contract testing
Schemathesis 기반 API fuzzing
```

### 4. 취약점 재현 테스트 고도화

현재 Evidence-as-Code는 핵심 취약점 재현을 확인한다.

향후에는 다음 검증을 추가한다.

1. 인증 우회
2. 세션 고정
3. SSRF
4. 파일 업로드 후 실행 경로
5. 서비스 간 권한 전파 실패
6. 이벤트 기반 구조에서의 데이터 정합성 실패

### 5. 운영 보안 레이어 추가

Golden Path의 다음 보안 계층으로 아래 도구를 단계적으로 추가한다.

```text
SonarQube
Gitleaks
Checkov
SBOM/CycloneDX
Cosign
SLSA/provenance
Cilium
Falco
NetworkPolicy
runtime observability
OWASP ZAP
```

## 최종 정리

현재 `vulnbank-msa`는 완전 독립형 Cloud-Native MSA가 아니다.

그러나 다음 성과는 달성했다.

1. 원본 VulnBank 모놀리스 기반 로직을 서비스별 컨테이너/API 경계로 분해했다.
2. 6개 서비스가 독립 Docker image로 빌드된다.
3. Helm chart와 GitOps values로 Kubernetes 배포 경로를 관리한다.
4. 서비스별 Trivy scan과 MSA Security Gate를 수행한다.
5. GitOps image tag update와 Jenkins pipeline 연동을 자동화했다.
6. 의도된 취약점 재현 결과를 Evidence-as-Code로 수집한다.

따라서 본 프로젝트의 현재 상태는 다음과 같이 정의한다.

```text
Shared-DB 패턴 기반의 VulnBank MSA 전환 PoC
```

이 정의가 현재 구현 범위와 기술적 한계를 가장 정확하게 설명한다.
