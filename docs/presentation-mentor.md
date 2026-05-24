---
marp: true
theme: default
paginate: true
header: 'VulnBank MSA DevSecOps PoC'
footer: 'dsaedsae · github.com/securious-DecSecOps · v0.3.1-poc'
style: |
  section { font-size: 22px; }
  h1 { font-size: 36px; }
  h2 { font-size: 30px; }
  code { font-size: 18px; }
  pre { font-size: 16px; }
  table { font-size: 18px; }
---

# VulnBank MSA DevSecOps PoC

멘토 발표 자료

작성: dsaedsae
기준: Build #19, tag v0.3.1-poc
GitHub: github.com/securious-DecSecOps

---

## 한 문장으로 말하면

취약한 PHP 모놀리스(VulnBank)를 6개 Kubernetes 마이크로서비스로 분해하고,
빌드부터 배포까지의 보안 검증 흐름을 Jenkins 파이프라인과 ArgoCD GitOps 루프로 자동화한 PoC.

핵심은 도구를 많이 붙인 게 아니라, **이미지 하나가 어떤 검사를 거쳐 어디에 배포되었고 어떤 증적을 남겼는지**를 한 줄로 추적 가능하게 만든 데 있다.

---

## 시작 동기

처음에는 SAST, 이미지 스캔, DAST, 런타임 도구를 파이프라인에 하나씩 붙이는 방향으로 접근했다.
구체화하면서 알게 된 건, 도구를 늘려도 "이 결과가 어떤 배포 대상에 대한 판단인가"가 일관되게 설명되지 않으면 보안 검증이라고 부르기 어렵다는 점이었다.

그래서 도구를 더 붙이기 전에 **표준 배포 경로와 증적 체인부터 고정**하고, 그 위에 도구를 얹는 순서로 전환했다.

---

## Before / After

```
[Before — Monolith]
1 Debian 컨테이너 안에 nginx + php-fpm 7.0 + mariadb + ImageMagick.
docker run -p 80:80 한 줄로 끝.

[After — Shared-DB MSA]
K8s namespace `secure-path-dev`에 frontend(gateway) +
user / transaction / status / file / settings 5개 백엔드 + MariaDB 1대.
MariaDB는 한 인스턴스지만 vb_user / vb_tx / vb_file / vb_settings 4 schema로
나누고, 각 서비스마다 별도 DB 계정 + GRANT로 cross-schema 접근을 막아놓았다.
```

서비스 간 통신은 K8s Service DNS 통한 HTTP, 인증은 HMAC-SHA256 stateless token, 각 서비스는 OpenAPI 3.0.3 스펙을 자체 노출.

---

## 5 Phase로 나눠서 옮긴 이유

Strangler Fig 패턴. 한 번에 다 옮기지 않고, 옮길 때마다 4개 의도된 취약점이 그대로 살아 있는지 확인했다.

- Phase 1: 다른 도메인의 SQL 직접 호출 제거. user 정보가 필요하면 user-service HTTP로만 lookup.
- Phase 3: DB schema 분리 + 서비스별 DB 계정 + GRANT. `tx_svc`로 `vb_user.users` 접근하면 MariaDB가 ERROR 1142로 거부.
- Phase 4: PHP session 폐기, HMAC-SHA256 token으로 교체.
- Phase 5: 각 서비스 OpenAPI 3.0.3 스펙. "Intentionally vulnerable" 라벨 명시.

매 phase 끝에 verify.sh로 7/7 PASS 확인. 옮기는 과정에서 의도된 vuln이 우연히 사라지면 PoC의 측정 대상이 깨지기 때문에 매번 확인했다.

---

## 4개의 의도된 취약점 (보존 대상)

| 위치 | 종류 |
| --- | --- |
| transaction-service `transactionSendLocal` | 음수 송금 (business logic) |
| transaction-service `case "history"` | 다른 계좌 거래내역 조회 (IDOR) |
| settings-service `settingsInfoUpdateLocal` | 다른 사용자 정보 수정 (IDOR) |
| file-service 업로드 + frontend gateway | 파일 업로드 RCE (chain) |

Build #19 시점에도 verify.sh가 7/7 PASS를 보고하면서 4가지 모두 재현된다.
중요한 건 이 4가지가 **logic / authorization 결함이라 SAST가 원리적으로 잡기 어려운 종류**라는 점이고, 나중에 다시 짚는다.

---

## 원본 VulnBank의 나머지 취약점은?

솔직히 다 옮긴 건 아니다. 원본에는 XSS, CSRF, race condition, 약한 md5 해시, 세션 픽세이션, ImageMagick CVE 등도 있었는데,

- 일부는 옮기는 과정에서 사라졌다. session 자체를 폐기했더니 session fixation은 개념적으로 소멸했고, base image를 `php:7.4-cli`로 바꾸면서 ImageMagick CVE도 없어졌다. Cross-domain SQL 제거하면서 일부 SQL injection 경로도 같이 정리됐다.
- 일부는 PHP 코드를 그대로 inherit해서 아마 잔존할 것이다. md5 password 해시 같은 부분은 login 로직을 안 건드렸으니 거의 확실히 살아 있을 텐데, 명시적으로 측정 대상으로 잡지 않았다.
- SonarQube가 빌드마다 이런 inherited 부분의 일부를 잡아낸다 (뒤에 숫자).

이 PoC는 "원본 vuln 풀세트를 옮기는 것"이 목표가 아니라 "SAST의 사각지대를 가장 명확히 드러내는 4가지를 선별해서 보존하는 것"이 목표였다.

---

## CI 파이프라인 (15 stage)

```
1.  Checkout SCM (devsecops-path)
2.  Preflight Tools
3.  Checkout App Source
4.  Checkout GitOps Repo
5.  Prepare Metadata  (REPORT_DIR = reports/dev/<BUILD_NUMBER>)
6.  Docker Build Services           — 6 이미지 빌드
7.  Trivy Scan Services             — 이미지 CVE
8.  Generate SBOM                   — Trivy SPDX + CycloneDX
9.  Checkov IaC Scan                — Dockerfile + Helm chart
10. Gitleaks Secret Scan            — 3 repo git history
11. SonarQube SAST                  — PHP
12. Security Gate                   — 4 도구 결과 aggregate (ENFORCE_GATE 정책)
13. Registry Login + Push           — Harbor
14. Deploy + GitOps Commit Push     — gitops repo에 image tag 자동 commit/push
15. Collect + Archive Evidence
```

Build #19에서 15 stage 전부 통과. 트리거 한 번이면 빌드부터 배포까지 사람 손이 안 들어간다.

---

## SBOM stage가 하는 일

`scripts/generate-sbom.sh`가 Trivy를 두 번 부른다. 한 번은 SPDX, 한 번은 CycloneDX.

- SPDX 2.3은 정부/규제 환경의 표준이고, CycloneDX 1.6은 Dependency-Track 같은 도구가 선호하는 포맷.
- 같은 비용으로 두 view를 다 확보하는 게 합리적이라 둘 다 생성.
- 6개 서비스에 대해 각 포맷이라 빌드당 12개 SBOM 파일 + summary가 `reports/dev/<N>/sbom/`에 떨어진다.

Build #19 결과로는 각 서비스당 SPDX 170 packages / CycloneDX 169 components. 같은 base image(`php:7.4-cli`)를 쓰니까 패키지 수가 거의 동일한 게 자연스럽다.

운영 단계 가면 이걸 그대로 Dependency-Track에 POST하면 신규 CVE 매칭이 자동으로 돌아간다. PoC는 파일 생성까지만.

---

## 4중 SAST가 실제로 찾은 것

SonarQube 기준 Build #19:

- PHP 라인 수: 약 20,130
- vulnerabilities: 8
- bugs: 117
- code smells: 1,870
- security hotspots: 42

대표적으로 잡힌 것들:

- `chmod 0777` (php:S2612, MAJOR) — 의도된 파일 업로드 RCE의 일부
- SSL/TLS verify 비활성 4건 (CRITICAL) — Nexmo SMS API curl 호출 부분
- DB root password 빈 값 2건 (BLOCKER)
- cookie `secure` flag 누락 1건

inherit된 PHP 코드의 약점이 정직하게 노출됐다.
"PoC라 vuln만 심어놓은 거 아닌가" 하는 의심에 대한 답이 되는 데이터.

---

## 그런데 4개의 의도된 vuln 중 SonarQube가 잡은 건 1개뿐이다

이게 이 PoC의 가장 중요한 측정 결과.

- 음수 송금: 못 잡음. "amount는 양수여야 한다"는 도메인 invariant가 코드 어디에도 표현되어 있지 않다. SAST는 코드 패턴을 보지 도메인 의미를 모른다.
- IDOR 2종: 못 잡음. "args.id가 session.id와 일치해야 한다" 같은 authorization 의도가 코드에 명시되어 있지 않은 한, SAST가 추론할 수 없다.
- 파일 업로드 RCE: 부분만. `chmod 0777`은 잡았지만, 확장자/MIME 검증 누락 + frontend gateway가 .php를 실행시키는 체인 전체는 못 봤다.

→ DAST(OWASP ZAP), 런타임 통제(Falco, Cilium NetworkPolicy, Istio AuthorizationPolicy 등)가 단순 보완재가 아니라 **다른 layer를 cover하는 서로 다른 종류의 검증**이라는 정량적 근거가 여기에 있다.

---

## GitOps 루프가 닫히는 모습 (Build #19 evidence)

```
Developer가 app-source-repo에 push
   ↓
Jenkins Build #19 (15 stage)
   ↓
Harbor에 :19 태그로 6개 이미지 push
   ↓
Jenkins가 gitops-manifest-repo에 image tag bump를 자동 commit/push
   ↳ 38f71b8 ci: bump vulnbank-msa to image tag 19 (build #19)
   ↓
ArgoCD detect + sync (필요 시 hard refresh annotation)
   ↓
frontend-d6cfbddc7-lsg78 새 Pod 기동 with image :19
   ↓
verify.sh 7/7 PASS
```

발표에서 보여주기 좋은 부분은 "사람이 한 일이 거의 없다"는 점.
Build trigger 1회를 빼면 자동.

---

## Phase 4의 빠진 조각 — UI 클라이언트 token

Build #19 직전에 발견한 갭. backend는 Phase 4에서 HMAC Bearer token으로 전환했는데, 브라우저에서 도는 `vulnbank.js`는 cookie session 그대로였다. 그래서 브라우저로 로그인까지는 되지만 그 다음 ajax 호출은 전부 "Permission denied"로 떨어지고 있었다.

verify.sh는 `/api/v1/*`를 직접 Bearer 헤더로 호출하니까 7/7 PASS였고, "API surface는 정상"이라는 측정만 했지 "사람이 브라우저로 쓸 때 정상"은 검증하지 않은 결과.

수정 자체는 작다. `$.ajaxSetup`에 beforeSend 훅을 달아서 localStorage의 token을 Bearer로 자동 첨부하게 했고, 401 statusCode 핸들러로 토큰 제거 + login 페이지 리다이렉트.

운영급으로 가면 localStorage 보관은 XSS에 취약하니까 HttpOnly cookie + CSRF token 조합이 더 낫다. PoC는 기능 복구가 목적이라 거기까지는 안 갔다. 이 한계는 `docs/known-limitations.md`에 명시.

---

## 3-Repo 거버넌스

- `devsecops-path` — Jenkins, scripts, bootstrap, docs. "어떻게 빌드하고 검사할 것인가".
- `gitops-manifest-repo` — Helm chart, ArgoCD App, env overlay. "K8s에 무엇이 배포되어야 하는가". 향후 platform 도구(Falco/Cilium/Istio/Kubescape/ZAP CronJob)도 여기 `platform/` 폴더에 추가될 자리.
- `app-source-repo` — PHP 앱 소스. 의도된 vuln 포함.

판단 기준이 단순하다: ArgoCD가 sync 가능한 K8s 리소스는 gitops 쪽, Jenkins가 실행하거나 EC2를 install하는 스크립트는 devsecops-path 쪽.

이렇게 끊어놓으면 권한 관리도 자연스럽게 분리된다. 앱 개발자는 app-source-repo만 push 권한 있으면 되고, gitops repo는 사람이 직접 만지지 않고 Jenkins만 자동 commit한다.

---

## Evidence-as-Code

모든 보안 결정이 `reports/dev/<BUILD_NUMBER>/` 한 곳에 모인다.

```
reports/dev/19/
├── trivy/         이미지별 CVE 스캔
├── sbom/          SBOM (SPDX + CycloneDX, summary)
├── checkov/       Dockerfile + Helm 매니페스트
├── gitleaks/      3 repo git history
├── sonarqube/     analysis task id, quality gate, issues
├── gate/          security gate 판단 근거
├── helm/          rendered manifest, upgrade log
├── gitops/        diff before/after auto commit
├── argocd/        app-status snapshot
├── kubernetes/    pods / services / deployments
├── events/        kubectl describe + events
├── evidence/      verify.sh DAST 결과
├── metadata.txt   BUILD_NUMBER, GIT_SHA, image tags
└── evidence-map.md
```

`archiveArtifacts`로 Jenkins archive에 영구 보존. Build #19로 들어가면 위 디렉토리 트리 그대로 조회 가능.
어떤 vuln 보고가 어느 빌드의 어느 이미지에 대한 것인지 build ID + commit SHA로 한 줄에 추적된다.

운영급으로 가면 S3 versioned bucket + KMS encryption + 90일 후 Glacier 같은 archive 정책을 얹는 게 자연스러운 확장.
PoC는 Jenkins archive까지만.

---

## 정직한 한계와 다음 단계 자리

발표할 때 가장 신경 쓴 부분.

- DB는 같은 MariaDB 안에 schema만 나눈 형태다. DB-per-service는 다음 단계.
- Token 형식은 RFC-7519 JWT가 아니라 자체 HMAC. 마이그하면 sidecar에서 검증 가능.
- 시크릿은 PoC라 env 평문. sealed-secrets / ESO / Vault가 다음.
- 인프라는 WSL의 kind cluster. AWS install bootstrap 스크립트는 아직 미작성 — 다음 codex 작업 후보.
- 런타임 도구(Falco, Cilium, Istio)는 install 안 했다. 다만 들어갈 자리는 `gitops-manifest-repo/platform/` 하위로 확정해놓아서, 다음 단계가 자연스럽게 이어진다.
- DAST는 verify.sh의 custom script만. OWASP ZAP은 cluster CronJob 모드(`platform/zap/`)로 다음 단계.
- SBOM은 파일 생성까지. Dependency-Track 연동은 운영 단계.

"안 한 것"을 솔직히 늘어놓는 게 오히려 평가에 좋다고 본다.
다음 단계 자리가 명확하다는 게 PoC의 가치니까.

---

## 디버깅 함정 12개 — 운영에서 만나게 될 것들

도구 통합은 문서대로만 동작하지 않더라. 이번 PoC에서 실제 부딪힌 것들을 정리하면:

1. Helm `namespace.yaml`이랑 `helm install --create-namespace` 충돌
2. Python `zipfile.extractall()`이 Unix exec bit 손실 → `unzip` CLI로 우회
3. Harbor v2.6+가 project-level robot API를 제거함 → system-level `/api/v2.0/robots` 사용
4. ArgoCD가 Helm hook을 strip해버림 → `argocd.argoproj.io/hook: PostSync` 병기
5. Multi-repo workspace에서 nested `.git` 때문에 SonarQube가 sub-repo 파일을 못 봄 → `sonar.scm.disabled=true`
6. Sonar-scanner 7.x zip dir 명명이 6.x와 달라짐 → namelist에서 동적 resolve
7. Sonar-scanner의 embedded JRE 권한 문제 → `skipJreProvisioning=true`
8. `sonar.projectBaseDir` 자동 추론이 워크스페이스 루트가 아님 → 명시 지정
9. Docker daemon insecure-registries vs curl reachability — `docker push`는 daemon의 trust 기준이라 `localhost:8082`로 통일
10. GitHub fine-grained PAT의 org repo 권한 함정 → Classic PAT (repo scope)
11. PEP 668 externally-managed Python → `--break-system-packages`
12. ArgoCD가 Jenkins commit을 즉시 안 봄 → polling lag 회피로 `refresh=hard` annotation 또는 webhook

각 함정마다 commit message에 한 줄 설명이 남아 있다. 운영자 입장에서 보면 한 줄로 끝나는 게 진짜 가치라고 본다.

---

## 라이브 데모 (5분 분량)

발표 마지막에 보여줄 흐름:

```bash
# 시스템 살아 있다는 증거
kubectl get pods -n secure-path-dev
kubectl -n argocd get application secubank-vulnbank-msa-dev
kubectl -n secure-path-dev get deployment frontend \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# SAST가 진짜 동작
curl -u admin:... 'http://localhost:9000/api/measures/component?component=vulnbank-msa&metricKeys=ncloc,bugs,vulnerabilities,security_hotspots'

# SBOM evidence
docker exec secubank-jenkins ls \
  /var/jenkins_home/jobs/vulnbank-msa-dev/builds/19/archive/reports/dev/19/sbom/

# DB 권한 격리
kubectl -n secure-path-dev run dbprobe --rm -i --image=mariadb:10.6 -- \
  mariadb -h vulnbank-db -u tx_svc -ptx_svc_pw -e "SELECT 1 FROM vb_user.users"
# ERROR 1142

# 4 의도 vuln 재현
bash /home/wngus/devsecops-path/bootstrap/local-wsl/verify.sh

# GitOps 루프
cd /home/wngus/gitops-manifest-repo && git log --oneline -2
```

---

## 멘토가 물어볼 만한 것들

여기는 표 대신 그냥 적는다.

왜 MSA냐 — Golden Path가 multi-service 워크로드를 처리 가능한지 검증하려고. 빌드 N번, 스캔 N번, push N번이 실제로 운영 가능한지 한 번에 보려는 의도.

왜 SAST 4종을 다 썼느냐 — 각자 다른 layer를 cover하니까. Trivy는 이미지 CVE, Checkov는 IaC 미설정, Gitleaks는 git 히스토리의 secret leak, SonarQube는 PHP 코드. 하나로 다 못 잡는다.

SonarQube가 의도된 4 vuln 중 1개만 잡은 게 이상하지 않냐 — 그게 이 PoC의 핵심 결과. business logic이랑 authorization은 코드 패턴이 아니라 도메인 의미의 문제고, SAST는 원리적으로 못 본다. 그래서 DAST와 런타임 통제가 필요하다는 정량 근거가 된다.

Gitleaks가 BLOCK인데 빌드가 SUCCESS인 이유 — ENFORCE_GATE 정책. PoC는 false로 finding 기록만 하고 차단 안 함. 운영에선 true로 바꾸면 빌드 자체가 fail. 정책이 코드에 박혀 있어서 운영 시 한 줄 토글.

시크릿 관리 — PoC라 env 평문. 운영은 sealed-secrets/ESO/Vault. 이건 코드 어디에 들어갈지가 이미 정의되어 있다.

Falco/Cilium은 언제 — 빌드/배포 자동화에 집중한 단계가 끝나면 그 위에 얹는다. 4 vuln이 살아 있어서 detection target이 명확하니 다음 단계로 자연스럽게 이어진다.

신규 CVE — SBOM은 만들어놓았으니 Dependency-Track 같은 도구에 연동만 하면 자동 매칭이 돈다. PoC는 파일 생성까지.

AWS — 다음 codex 작업으로 install bootstrap script 작성 예정. EC2 free tier로 한 번 사이클 검증한 후 발표 자료에 포함.

---

## 마무리 메시지

이 프로젝트를 통해 가장 크게 배운 건 도구 통합 자체가 가치가 아니라는 점이다.

도구를 5개 6개 붙여도 "어떤 위험을 어떤 기준으로 판단했고, 그 결정이 누구에 의해 언제 어디서 다시 검토 가능한가"가 추적되지 않으면 보안 검증이라고 부르기 어렵다.

표준 배포 경로와 증적 체인이 먼저고, 도구는 그 위에 얹는 것.
이게 컨설팅 관점에서 "DevSecOps를 한다"고 말할 때 실제로 의미 있는 산출물이라고 본다.

---

## 부록 — 발표 전 점검

- Build #19 Jenkins console 캡처
- SonarQube dashboard 캡처 (8 vulns / 117 bugs / 42 hotspots)
- Harbor secubank/vulnbank-msa-* 태그 리스트 (`:19` 보이게)
- ArgoCD Synced + Healthy 캡처 (`rev=38f71b8`)
- kubectl get pods (image `:19` 보이게)
- verify.sh 7/7 PASS 출력
- gitops 레포 `git log --oneline -3` (Jenkins commit 보이게)
- `docs/known-limitations.md`, `docs/sbom-evidence.md` 출력본
- 디버깅 함정 12개 슬라이드
- 발표 전 PAT 노출분 모두 revoke
- 3 repo 모두 public + tag `v0.3.1-poc` 박힌 상태 확인
