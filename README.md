# DevSecOps Golden Path — CI & Supply Chain

금융권 보안담당자의 실무(판단·차단·추적·재평가·증적)를 Kubernetes 파이프라인으로 재현한 **evidence-driven DevSecOps Golden Path**의 CI/공급망 레포다. 이 레포에는 Jenkins 파이프라인 정의와 스캐너·게이트·배포 스크립트가 들어 있다.

전체 설계·아키텍처·탐지 효능 데이터는 문서 사이트에서 본다 → **https://securious-decsecops.github.io/secubank-docs/**

## 구성 레포

| Repo | 역할 |
| --- | --- |
| **devsecops-path** (이 레포) | Jenkins CI 파이프라인 + 스캐너/게이트/배포 스크립트 + 부트스트랩 |
| [app-source-repo](https://github.com/securious-DecSecOps/app-source-repo) | 검증용 워크로드 소스(VulnBank MSA 등) |
| [gitops-manifest-repo](https://github.com/securious-DecSecOps/gitops-manifest-repo) | Helm 차트 · ArgoCD App · 런타임 플랫폼 |
| [infra-terraform-repo](https://github.com/securious-DecSecOps/infra-terraform-repo) | AWS 인프라(Terraform) + EC2 부트스트랩 |

## CI 파이프라인 (`Jenkinsfile.aws-ci`)

개발자 push → 빌드 전 정적 검사 → 빌드 후 아티팩트 검사 → 게이트 → Harbor push → 증적.

| 단계 | 도구 | 스크립트 |
| --- | --- | --- |
| Secrets | Gitleaks | `scripts/gitleaks-scan-repos.sh` |
| SAST | SonarQube | `scripts/sonarqube-scan-services.sh` |
| IaC | Checkov | `scripts/checkov-scan-services.sh` |
| K8s | Kubescape | `scripts/kubescape-scan.sh` |
| Build | Docker | `scripts/build-services.sh` |
| SBOM | Syft | `scripts/generate-sbom.sh` |
| Image CVE | Trivy | `scripts/trivy-scan-services.sh` |
| Gate | 집계·차단 | `scripts/security-gate-services.sh` |
| Push | Harbor | `scripts/registry-login.sh` · `scripts/push-services.sh` |
| Notify | SNS | `scripts/notify-sns.sh` |

`ENFORCE_GATE=false`(report-only) ↔ `true`(차단)로 게이트 강제 여부를 환경에 맞게 선택한다. 게이트 정책: `GATE_MAX_CRITICAL=0`, `GATE_MAX_HIGH=3`.

## 디렉터리

```
Jenkinsfile.aws-ci        # AWS CI-only 파이프라인 (정본)
scripts/                  # 스캐너·게이트·빌드·푸시·배포·알림 스크립트
bootstrap/local-wsl/      # 로컬(WSL/kind) 부트스트랩 + verify.sh(비즈로직 DAST)
docs/                     # 운영 문서 (intentional-vulnerabilities, security-gate-policy 등)
```

## 로컬 비즈로직 검증 (DAST)

```bash
# 실행 중인 워크로드 frontend를 대상으로 음수송금·IDOR·웹쉘 RCE 재현
FRONTEND_URL=http://localhost:18080 bash scripts/test-msa-integration.sh
```

## 주의 — 검증 워크로드는 의도적으로 취약함

VulnBank 등 검증 워크로드는 **의도된 취약점을 가진 lab target**이다(운영 배포 금지). 이 파이프라인의 목적은 그 취약점을 **탐지·차단하고 증적을 남기는 것**이다. 취약점 위치는 `docs/intentional-vulnerabilities.md` 참고.

## License

Apache License 2.0 — `LICENSE` 참고.
