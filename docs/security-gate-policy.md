# Security Gate Policy

Security Gate는 단순히 취약점 개수를 세는 단계가 아닙니다. Pipeline이 배포 정책 결정을 기록하는 지점입니다.

```text
block, warn, continue in report-only mode, alert, or require manual review
```

v1에서는 Trivy image scan 결과를 사용해 가장 작은 정책 엔진을 구현합니다. 아래 모델은 이후 확장 방향을 정의합니다.

## 구현된 MVP Rule

```text
Critical > 0 => BLOCK
Critical = 0 => PASS
High => WARN / accepted risk in v1
```

## Enforcement Mode

`ENFORCE_GATE=false`

Gate 결과가 `BLOCK`이어도 exit code `0`으로 종료합니다. local 학습, 취약 워크로드 테스트, evidence 수집을 위해 pipeline을 계속 진행할 수 있습니다.

`ENFORCE_GATE=true`

Gate 결과가 `BLOCK`이면 exit code `1`로 종료해 pipeline을 실패시킵니다.

## Target Policy v1

| 조건 | 결정 |
| --- | --- |
| Secret 탐지 | 즉시 차단 |
| fixed version이 있는 Critical CVE | 차단 |
| exploit 우선순위가 높은 Critical CVE | 차단 |
| 인터넷 노출 서비스의 High CVE | 경고 또는 조건부 차단 |
| 내부용/영향 낮은 High CVE | report 저장 및 조치 기한 부여 |
| unfixed CVE | report 저장 및 보완 통제 기록 |
| 의도적으로 취약한 실습 워크로드 | `ENFORCE_GATE=false`로 report-only 허용 |
| DAST High/Critical | 기본적으로 알림 및 수동 검토 |

## 모든 Finding을 차단하지 않는 이유

모든 finding을 즉시 차단하면 실제 보안 의사결정 없이 배포만 멈출 수 있습니다. Finding 종류마다 다른 처리가 필요합니다.

- secret은 대부분 즉시 조치 가능한 고위험 finding입니다.
- fixed version이 있는 Critical CVE는 차단 후보입니다.
- unfixed CVE는 risk acceptance 또는 compensating control이 필요합니다.
- DAST finding은 오탐과 재현성 확인이 필요할 수 있습니다.
- 실습용 취약 워크로드는 report-only 모드로 진행해야 할 수 있습니다.

## Evidence

Gate 결과는 아래 파일에 저장됩니다.

```text
reports/dev/<build-number>/gate/gate-result.txt
```

Gate evidence에는 아래 정보가 들어가는 것이 좋습니다.

- workload
- build number
- image
- scanner inputs
- critical/high counts
- fixed-version availability when known
- final gate result
- enforcement mode
- action required

## Future Gate Inputs

향후 아래 도구들이 같은 gate model에 입력으로 들어올 수 있습니다.

- SonarQube for source/SAST quality gates
- Gitleaks for secret detection
- Checkov for Kubernetes/IaC checks
- SBOM/CycloneDX policy and Dependency-Track style analysis
- Cosign signature verification
- SLSA/provenance checks
- DAST and runtime findings as alert/review inputs

