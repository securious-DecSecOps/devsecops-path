# 알려진 한계와 원본 VulnBank 차이

이 문서는 VulnBank MSA PoC가 원본 VulnBank와 완전히 동일한 운영 애플리케이션이 아니라, 보안 실습과 DevSecOps Golden Path 검증을 위해 단계적으로 분해된 PoC라는 점을 명확히 기록한다.

## 1. 원본 VulnBank와의 기능 차이

원본 VulnBank에는 독립적인 `email-service`가 없다. 이메일은 사용자 테이블의 컬럼으로 관리되며, OTP 흐름은 SMS/Nexmo 설정을 통해 동작하는 구조다. MSA PoC에서도 별도 이메일 서비스는 추가하지 않았고, 이메일 필드는 사용자 프로필 데이터로만 유지한다.

SMS/OTP 경로는 PoC 환경에서 기본 활성화 대상이 아니다. `sms_api`, `VB_OTP`, `NEXMO_API_KEY`, `NEXMO_API_SECRET` 같은 설정이 실제로 주입되지 않으면 OTP 경로는 비활성 또는 제한 동작으로 남는다. 이 PoC의 검증 기준은 OTP 운영 연동이 아니라 기본 로그인, 거래, 설정, 파일 업로드 흐름과 의도된 취약점 재현이다.

MSA 전환 과정에서 원본 취약점 중 일부는 구조적으로 약화되거나 제거되었다. PHP session id를 서비스 간에 직접 전파하던 방식은 HMAC-SHA256 서명 토큰으로 교체되어 기존 session fixation 표면이 줄었다. 원본의 이미지 처리 경로에 의존하던 ImageMagick 계열 CVE 표면은 현재 frontend/file-service 구조에 그대로 이식하지 않았다. 또한 transaction/file/settings 서비스가 `users` 테이블을 직접 조회하거나 수정하던 cross-domain SQL 일부는 user-service HTTP 호출과 DB schema 권한 분리로 제거되었다.

## 2. 의도된 4개 취약점 보존과 추가 상속 취약점

다음 4개 취약점은 보안 실습 목적상 의도적으로 보존했다.

- 음수 송금: 금액이 음수인지 검증하지 않아 잔액 조작이 가능하다.
- IDOR transaction history: 요청자가 다른 계좌번호의 거래 내역을 조회할 수 있다.
- IDOR user update: 요청자가 임의 사용자 ID를 지정해 회원 정보를 수정할 수 있다.
- 파일 업로드 RCE: 업로드 파일의 확장자와 MIME을 검증하지 않아 PHP 웹쉘 업로드와 실행이 가능하다.

SonarQube 분석에서는 추가로 `117 bugs / 8 vulnerabilities / 42 security hotspots`가 검출되었다. 이 항목들은 원본 취약 애플리케이션과 PoC 코드 특성에서 상속된 위험을 포함하며, 현재 PoC 범위에서는 모두 수정 대상이 아니다. 보안 도구가 위험을 식별하고 증적화하는지 확인하는 것이 현재 목표다.

## 3. UI 클라이언트의 Token 사용

Phase 4에서 백엔드는 PHP cookie session 기반 인증에서 HMAC-SHA256 Bearer token 기반 인증으로 전환되었다. 이번 UI 패치로 `vulnbank.js`는 로그인 응답의 `token` 값을 `localStorage`에 저장하고, 이후 모든 jQuery Ajax 요청에 `Authorization: Bearer <token>` 헤더를 자동 첨부한다.

이 방식은 브라우저 UI 기능 복구를 위한 PoC 구현이다. `localStorage`에 token을 저장하면 XSS가 발생했을 때 token 탈취 위험이 있다. 운영급 대안은 `HttpOnly` cookie와 CSRF token 조합, 또는 `SameSite=Strict` 같은 cookie 정책을 함께 사용하는 방식이다. 현재 작업의 목표는 token storage hardening이 아니라 Phase 4 이후 깨진 브라우저 흐름을 복구하는 것이다.

## 4. PoC Scope 외 한계

데이터 계층은 service별 schema로 분리했지만, MariaDB 인스턴스는 하나다. 즉 DB-per-service 구조가 아니라 단일 MariaDB 안의 schema-per-service 구조다.

토큰 형식은 자체 HMAC-SHA256 서명 포맷이다. `base64url(json).hash_hmac` 형태이며 RFC-7519 JWT가 아니다. OAuth2/OIDC도 도입하지 않았다.

Secret 관리는 Kubernetes Secret 기반 운영 모델이 아니라 env 평문 기반 PoC 기본값을 사용한다. 일부 기본 비밀번호와 토큰 secret은 실습 편의용이며 운영 환경에 사용할 수 없다.

인프라 검증은 WSL kind 환경이 기준이다. AWS bootstrap과 운영형 배포 자동화는 아직 작성되지 않았다.

런타임 보안 도구는 아직 설치하지 않았다. Falco, Cilium, Istio 같은 런타임 탐지, 네트워크 정책, 서비스 메시 계층은 다음 단계의 확장 지점으로만 남겨두었다.

DAST는 현재 `verify.sh`와 custom curl 기반 재현 스크립트가 중심이다. OWASP ZAP은 아직 cluster CronJob 모드로 통합하지 않았다.

SBOM 생성은 Trivy 기반 SPDX/CycloneDX 산출물로 추가되었지만, Dependency-Track 같은 SBOM 분석 플랫폼과는 아직 연동하지 않았다.

## 5. 이번 작업으로 메워진 갭

Phase 4의 미완성 부분은 백엔드만 token 인증으로 전환되고, 브라우저 JS 클라이언트는 여전히 cookie session에 의존했다는 점이다. 그 결과 로그인 응답에는 token이 포함되지만, 이후 `type=user&action=check` 같은 Ajax 요청에는 `Authorization` 헤더가 없어 `Permission denied`가 발생했다.

이번 패치로 `vulnbank.js`가 로그인 응답의 token을 `localStorage`에 저장하고, 모든 Ajax 호출에 Bearer token을 자동 첨부한다. 로그아웃 시에는 `logout.php`가 `localStorage`의 `vb_token`을 제거한 뒤 `login.php`로 이동한다.

결과적으로 브라우저 UI에서 `login.php` 로그인 이후 `portal.php`, `transactions.php`, `settings.php` 흐름이 다시 동작한다. 기존 `verify.sh`는 `/api/v1/*` 경로를 직접 호출하고 Bearer 헤더를 직접 첨부하므로 이번 UI 패치의 영향을 받지 않아야 한다.
