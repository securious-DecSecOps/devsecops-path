# 문서 읽는 순서

처음 보는 사람은 모든 문서를 한 번에 읽을 필요가 없습니다. 아래 순서만 따라가면 됩니다.

## 먼저 읽기

1. [../README.md](../README.md)
   - 프로젝트가 무엇인지, local 기본값이 무엇인지 확인합니다.

2. [golden-path.md](golden-path.md)
   - 이 repo가 단일 앱 배포 repo가 아니라 Golden Path 템플릿이라는 점을 이해합니다.

3. [local-kind-runbook.md](local-kind-runbook.md)
   - local에서 `simple-web` MVP를 검증하는 방법을 봅니다.

4. [workload-onboarding.md](workload-onboarding.md)
   - 새 워크로드를 어떻게 추가하는지 봅니다.

5. [vulnbank-msa-migration.md](vulnbank-msa-migration.md)
   - VulnBank monolith와 MSA adapter의 차이를 확인합니다.

6. [security-gate-policy.md](security-gate-policy.md)
   - Trivy 결과를 어떻게 PASS/BLOCK으로 판단하는지 봅니다.

7. [aws-k3s-runbook.md](aws-k3s-runbook.md)
   - AWS VM/k3s로 옮길 때 local 값과 무엇이 달라지는지 봅니다.

## 배포 모드별 상세

- [helm-runbook.md](helm-runbook.md)
- [argocd-gitops-runbook.md](argocd-gitops-runbook.md)

## 참고 문서

- [architecture.md](architecture.md)
- [registry-notes.md](registry-notes.md)
- [evidence-policy.md](evidence-policy.md)
- [troubleshooting.md](troubleshooting.md)
- [vulnbank-msa-migration.md](vulnbank-msa-migration.md)

## 선택 확장 문서

아래 문서는 local MVP 필수 문서가 아닙니다. 나중에 보안 도구를 확장할 때 참고합니다.

- [cve-rescan-pipeline.md](cve-rescan-pipeline.md)
- [alerting-policy.md](alerting-policy.md)
- [dast-runtime-validation.md](dast-runtime-validation.md)
- [future-sonarqube.md](future-sonarqube.md)
- [future-cilium-runtime-security.md](future-cilium-runtime-security.md)
