# Kubescape 통합

## 1. Kubescape 도입 이유

Kubescape는 Kubernetes manifest와 cluster posture에 특화된 보안 점검 도구다. 기존 Checkov가 Dockerfile, Terraform, Kubernetes 등 여러 IaC 기술을 폭넓게 점검하는 도구라면, Kubescape는 Kubernetes hardening 관점에 더 집중한다.

이 PoC에서 Kubescape를 추가한 이유는 단순히 SAST 도구 수를 늘리는 것이 아니라, Kubernetes 리소스가 어떤 보안 프레임워크 기준에서 위험한지 설명할 수 있게 하기 위해서다. Kubescape는 NSA-CISA Kubernetes Hardening Guide, MITRE ATT&CK for Kubernetes, CIS Kubernetes Benchmark 같은 프레임워크와 직접 연결된 결과를 제공한다.

현재 범위는 pre-deploy CLI scan이다. Jenkins Pipeline에서 Helm chart를 대상으로 정적 스캔을 수행하고 결과를 evidence로 보관한다. Kubescape Operator 기반의 in-cluster 연속 스캔과 runtime posture 관찰은 다음 단계로 둔다.

## 2. 출력 위치

Jenkins build마다 Kubescape 결과는 다음 경로에 저장된다.

- `reports/dev/<N>/kubescape/nsa.json`
- `reports/dev/<N>/kubescape/mitre.json`
- `reports/dev/<N>/kubescape/cis.json`
- `reports/dev/<N>/kubescape/nsa.err`
- `reports/dev/<N>/kubescape/mitre.err`
- `reports/dev/<N>/kubescape/cis.err`
- `reports/dev/<N>/kubescape/kubescape-summary.txt`
- `reports/dev/<N>/kubescape/kubescape-version.txt`
- `reports/dev/<N>/kubescape/frameworks.txt`

이 파일들은 다른 evidence와 동일하게 Jenkins archive에 보존된다. JSON 파일은 원본 분석 결과이고, `kubescape-summary.txt`는 발표와 리뷰에서 빠르게 확인하기 위한 요약 파일이다.

## 3. 환경 변수

새로 추가된 환경 변수는 없다. 기존 Jenkinsfile.msa에서 사용하는 값을 그대로 사용한다.

- `HELM_CHART_DIR`: Kubescape가 스캔할 Helm chart 경로
- `REPORT_DIR`: scan 결과와 summary가 저장될 build별 evidence 경로

Kubescape CLI가 Jenkins 컨테이너에 없으면 `scripts/kubescape-scan.sh`가 첫 실행 시 GitHub release에서 바이너리를 내려받아 설치한다.

## 4. ENFORCE_GATE 정책

현재 PoC 기본값은 `ENFORCE_GATE=false`다. 따라서 Kubescape finding은 기록과 evidence 보관 대상으로 두며, build를 자동 차단하지 않는다.

운영형 정책으로 확장할 경우 `ENFORCE_GATE=true`에서 Security Gate가 Kubescape 결과까지 aggregate하도록 확장할 수 있다. 예를 들어 NSA-CISA critical control 실패, CIS baseline 필수 항목 실패, MITRE ATT&CK for Kubernetes 고위험 항목을 차단 기준에 포함할 수 있다. 현재 작업에서는 정보 기록까지만 수행한다.

## 5. 향후 확장 자리

Kubescape Operator를 cluster 안에 설치하면 배포 후에도 Kubernetes 리소스와 cluster posture를 지속적으로 점검할 수 있다. 이 경우 GitOps repo에 다음과 같은 위치를 둘 수 있다.

- `gitops-manifest-repo/platform/kubescape/`

Armo Cloud 연동은 선택 사항이다. 필요하면 별도 환경 변수와 secret을 추가해 활성화할 수 있지만, 현재 PoC에서는 외부 SaaS 연동 없이 로컬 Jenkins evidence 생성만 수행한다.
