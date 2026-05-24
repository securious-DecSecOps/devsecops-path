# SBOM Evidence Policy

VulnBank MSA 파이프라인에서 생성되는 SBOM(Software Bill of Materials)의 정책, 저장 위치, 포맷, 운영 확장 계획.

## 1. 생성 시점과 도구

- 시점: Jenkinsfile.msa의 `Generate SBOM` stage (Trivy Scan Services 직후)
- 도구: Trivy CLI (`trivy image --format spdx-json|cyclonedx`)
- 대상: 6 service 이미지 (`${REGISTRY_URL}/${REGISTRY_PROJECT}/vulnbank-msa-<service>:${IMAGE_TAG}`)
- 입력: 이미 빌드된 로컬 이미지 (Docker Build Services stage 산출물)

## 2. 출력 위치

```
reports/dev/<build-number>/sbom/
├── sbom-summary.txt                        # 빌드 메타데이터 + 서비스별 결과 요약
├── user-service.spdx.json
├── user-service.cdx.json
├── transaction-service.spdx.json
├── transaction-service.cdx.json
├── status-service.spdx.json
├── status-service.cdx.json
├── file-service.spdx.json
├── file-service.cdx.json
├── settings-service.spdx.json
├── settings-service.cdx.json
├── frontend.spdx.json
└── frontend.cdx.json

reports/dev/<build-number>/services/<service>/sbom/
├── sbom.spdx.json                          # 서비스 단위 디렉토리 복사본
└── sbom.cdx.json
```

전체 평탄 보존본은 `reports/dev/<N>/sbom/`, 서비스별 그루핑 사본은 `reports/dev/<N>/services/<svc>/sbom/`. 같은 내용 2 view.

## 3. 저장 정책 (PoC 단계)

- Jenkins workspace에 생성 후, `archiveArtifacts`로 Jenkins archive에 영구 보존
- 위치: `secubank-jenkins:/var/jenkins_home/jobs/<job>/builds/<N>/archive/reports/dev/<N>/sbom/`
- 접근: Jenkins UI → Build → "Build Artifacts" 또는 컨테이너 내 직접 조회
- 보존: Jenkins job 보존 정책에 의존 (default: 무제한)
- **git repo에는 commit 금지** — artifact는 git에 들어가지 않음

S3, Dependency-Track, OCI artifact attachment은 **PoC scope 외**. 운영 단계에서 추가.

## 4. 포맷 선택 — SPDX + CycloneDX 둘 다

| 포맷 | 용도 |
| --- | --- |
| SPDX 2.x JSON | ISO/IEC 5962 표준. 정부/규제 환경의 디폴트. SBOM 교환 호환성 최고. |
| CycloneDX 1.x JSON | OWASP 표준. Dependency-Track, Snyk, GitHub Dependabot 친화. 컴포넌트 분석 용이. |

→ Trivy 단일 호출 2회로 같은 이미지에서 양 포맷 모두 생성. 추가 비용 미미.

## 5. SBOM이 답하는 질문

- 이 이미지에는 어떤 OS 패키지가 포함됐나? (Debian/Alpine layer)
- PHP, Python 등 언어 의존성 트리는?
- 특정 CVE 발표 시, 어느 빌드/이미지가 영향 받는지 역추적
- 라이선스 분포 (GPL/MIT/Apache 등)
- 공급망 변화 추적 (빌드 간 의존성 diff)

## 6. 환경 변수

`generate-sbom.sh`는 기존 SAST 스크립트와 동일 환경 변수 사용:

| 변수 | 출처 | 예시 |
| --- | --- | --- |
| `APP_NAME` | Jenkinsfile parameter | `vulnbank-msa` |
| `REGISTRY_URL` | Jenkinsfile parameter | `localhost:8082` |
| `REGISTRY_PROJECT` | Jenkinsfile parameter | `secubank` |
| `IMAGE_TAG` | `BUILD_NUMBER` 기본 | `19` |
| `REPORT_DIR` | `Prepare Metadata` stage | `reports/dev/19` |
| `SERVICES` | Jenkinsfile parameter | `user-service,transaction-service,...,frontend` |

추가 환경 변수 없이 동작. 새 credential/시크릿 필요 없음.

## 7. 운영 단계 확장 계획 (out of PoC scope)

향후 운영 환경에서 추가 가능한 분기:

```
reports/dev/<N>/sbom/<svc>.cdx.json
   ├── (현재) Jenkins archive 저장
   ├── (운영) aws s3 cp → s3://secubank-evidence/sbom/build-<N>/
   ├── (운영) Dependency-Track API POST /api/v1/bom (자동 신규 CVE 매칭)
   └── (운영) cosign attest --predicate sbom.cdx.json → OCI artifact attachment
```

`scripts/generate-sbom.sh`에 환경 변수 기반 분기 추가:
- `EVIDENCE_S3_BUCKET` → aws s3 cp
- `DTRACK_URL` + `DTRACK_API_KEY` → curl POST
- `COSIGN_KEY` → cosign attest

PoC는 위 분기 미구현. 호환 가능한 구조만 유지.

## 8. 검증 절차 (수동)

```bash
# Jenkins workspace 또는 archive에서
ls reports/dev/<N>/sbom/
# → 12개 파일 + sbom-summary.txt 존재 확인

# JSON 유효성
python3 -c "import json; json.load(open('reports/dev/<N>/sbom/user-service.spdx.json'))"
python3 -c "import json; json.load(open('reports/dev/<N>/sbom/user-service.cdx.json'))"

# 패키지 수 (SPDX)
python3 -c "import json; d=json.load(open('reports/dev/<N>/sbom/user-service.spdx.json')); print(len(d.get('packages',[])))"

# 패키지 수 (CycloneDX)
python3 -c "import json; d=json.load(open('reports/dev/<N>/sbom/user-service.cdx.json')); print(len(d.get('components',[])))"

# 요약
cat reports/dev/<N>/sbom/sbom-summary.txt
```

## 9. 실패 시 동작

- Trivy SBOM 생성 실패 시: stage가 fail 처리 (set -euo pipefail)
- 이미지가 로컬에 없으면 fail (Docker Build Services가 선행되어야 함)
- 부분 실패 시 `${REPORT_DIR}/sbom/<service>.err`에 로그 보존

## 10. 관련 문서

- `evidence-policy.md` — 전체 evidence 정책
- `architecture.md` — 파이프라인 stage 다이어그램
- `cve-rescan-pipeline.md` — SBOM 기반 신규 CVE 재스캔 계획 (운영 단계)
- `security-gate-policy.md` — gate에 SBOM 포함 여부 (현재 미포함)
