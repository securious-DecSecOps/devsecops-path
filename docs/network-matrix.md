# VulnBank MSA Network Matrix

서비스 간 호출 관계 일람. **Cilium NetworkPolicy / Istio AuthorizationPolicy 작성 시 1차 reference**로 사용한다.

기본 가정:
- 모든 서비스는 K8s ClusterIP Service. 통신은 평문 HTTP (Istio 도입 후 mTLS 자동화).
- Frontend의 PHP gateway가 외부 트래픽(`/api/v1/*`, `/vulnbank/online/uploads/*`)을 받아 backend로 forward.
- Backend 서비스는 외부에 직접 노출되지 않는다 (ClusterIP only).
- 모든 PHP 서비스의 컨테이너 포트는 `8080`.
- DB(MariaDB) 포트는 `3306`.

## 외부 → Cluster

| From | To | Port | Path | 용도 |
| --- | --- | --- | --- | --- |
| 외부 사용자/테스터 | `vulnbank-msa-frontend` | 8080 | `/api/v1/auth/login` (공개) | 로그인 → 토큰 발급 |
| 외부 사용자/테스터 | `vulnbank-msa-frontend` | 8080 | `/api/v1/auth/sms` (공개) | SMS 코드 발송 |
| 외부 사용자/테스터 | `vulnbank-msa-frontend` | 8080 | `/api/v1/transactions/*` | 토큰 필요 |
| 외부 사용자/테스터 | `vulnbank-msa-frontend` | 8080 | `/api/v1/settings/*` | 토큰 필요 |
| 외부 사용자/테스터 | `vulnbank-msa-frontend` | 8080 | `/api/v1/files/upload` | 토큰 필요 (multipart) |
| 외부 사용자/테스터 | `vulnbank-msa-frontend` | 8080 | `/api/v1/status/*` | 토큰 필요 |
| 외부 사용자/테스터 | `vulnbank-msa-frontend` | 8080 | `/vulnbank/online/uploads/*` | 의도된 RCE 경로 |
| K8s 프로브 | 모든 서비스 | 8080 | `/healthz` (`/healthz.php` for file-service) | liveness/readiness |
| Prometheus (예정) | 모든 서비스 | 8080 | `/metrics` (미구현) | 메트릭 수집 |

## Frontend → Backend (Gateway 라우팅)

| From | To | Port | 용도 |
| --- | --- | --- | --- |
| `vulnbank-msa-frontend` | `vulnbank-msa-user-service` | 8080 | auth/login, sms, user lookup, user update |
| `vulnbank-msa-frontend` | `vulnbank-msa-transaction-service` | 8080 | transfer, history, recent, balance, verify, clear, cancel |
| `vulnbank-msa-frontend` | `vulnbank-msa-file-service` | 8080 | upload_avatar, list, avatar |
| `vulnbank-msa-frontend` | `vulnbank-msa-settings-service` | 8080 | changelocale, get/list, update, resetdb, infoupdate, changepass |
| `vulnbank-msa-frontend` | `vulnbank-msa-status-service` | 8080 | ping, get |

## Backend → Backend (Service-to-Service)

Phase 1 이후 cross-service 호출은 **모두 user-service의 내부 HTTP API**로 통일됨.

| From | To | Port | 용도 |
| --- | --- | --- | --- |
| `vulnbank-msa-transaction-service` | `vulnbank-msa-user-service` | 8080 | `vb_user_lookup_by_account`, `vb_user_balance_set` |
| `vulnbank-msa-file-service` | `vulnbank-msa-user-service` | 8080 | `vb_user_lookup_by_id`, `vb_user_avatar_set` |
| `vulnbank-msa-settings-service` | `vulnbank-msa-user-service` | 8080 | `vb_user_lookup_by_id`, `vb_user_update_fields` |
| `vulnbank-msa-status-service` | `vulnbank-msa-user-service` | 8080 | health/ping aggregation |
| `vulnbank-msa-status-service` | 다른 5개 PHP service | 8080 | health/ping aggregation |

**역방향 호출은 없음.** user-service는 다른 서비스로 outbound 호출을 하지 않는다.

## Backend → Database

서비스별 DB 권한은 Phase 3에서 MariaDB GRANT로 강제 분리됨. 자기 schema 외엔 거부됨.

| From | To | Port | DB user → schema |
| --- | --- | --- | --- |
| `vulnbank-msa-user-service` | `vulnbank-db` | 3306 | `user_svc` → `vb_user.*` only |
| `vulnbank-msa-transaction-service` | `vulnbank-db` | 3306 | `tx_svc` → `vb_tx.*` only |
| `vulnbank-msa-file-service` | `vulnbank-db` | 3306 | `file_svc` → `vb_file.*` only (현재 코드에선 거의 미사용) |
| `vulnbank-msa-settings-service` | `vulnbank-db` | 3306 | `settings_svc` → `vb_settings.*` only |

`vulnbank-msa-status-service`와 `vulnbank-msa-frontend`는 DB에 연결하지 않는다.

## DB Init Job → Database

| From | To | Port | 용도 |
| --- | --- | --- | --- |
| Job `vulnbank-db-init` (helm post-install/upgrade hook) | `vulnbank-db` | 3306 | root로 CREATE DATABASE/USER/GRANT + 초기 seed 데이터 INSERT |

Job은 성공 직후 helm `hook-delete-policy: hook-succeeded`에 의해 자동 삭제된다.

## 외부 (인터넷) → 모든 pod

**현재 정책 없음.** 모든 서비스가 모든 외부로 outbound 가능. **Cilium NetworkPolicy 도입 시 default-deny + 명시적 allow 권장.**

명시적으로 허용되어야 할 outbound (현재 PoC 기준):
- 모든 PHP service → `vulnbank-db:3306` (위 표대로)
- 모든 PHP service → 다른 service의 `:8080`
- `kube-dns` (`10.96.0.10:53`) — K8s DNS
- (선택) `nexmo.com:443` — SMS API (env로 disabled 상태)

LiteLLM 공급망 공격 같은 시나리오에서 "허용되지 않은 outbound"가 차단되어야 한다. 이게 Cilium 정책의 핵심 가치.

## 차단되어야 할 흐름 (zero-trust 시나리오)

| From | To | 기대 동작 |
| --- | --- | --- |
| `vulnbank-msa-transaction-service` | `vulnbank-msa-file-service` 직접 | 차단 (현재 코드에선 호출 안 함; 의도되지 않은 흐름) |
| `vulnbank-msa-file-service` | `vulnbank-db:3306` cross-schema | DB가 거부 (MariaDB GRANT) + NetworkPolicy 통과 |
| 임의 pod | `vulnbank-msa-user-service` 직접 | namespace 외부에선 차단되어야 함 |
| Workload pod | 인터넷 임의 host | 명시 allowlist 외 차단 |

## 정책 작성 시 주의사항

1. **Service name vs Deployment name**: K8s Service는 `vulnbank-msa-<service>` 형식, Deployment는 `<service>` 형식. NetworkPolicy `podSelector`는 label 기반(`app.kubernetes.io/name=<service>`)으로 매칭해야 함.
2. **Frontend의 듀얼 역할**: 외부 entry + 내부 라우터. ingress allow는 80/443 또는 NodePort, egress allow는 5개 backend 서비스 모두.
3. **DB pod label**: `app.kubernetes.io/name=vulnbank-db`. egress 정책에서 DB target 지정 시 사용.
4. **PHP `php -S` 특성**: 별도 health check endpoint가 워크로드와 같은 포트(8080)에 있음. 프로브 트래픽도 같은 포트 allow 필요.
5. **Webshell RCE 의도**: `/vulnbank/online/uploads/*.php` 경로는 의도된 vulnerability. NetworkPolicy로 차단하지 마라 — 시나리오의 핵심.
