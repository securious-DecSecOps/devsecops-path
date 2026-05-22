# Evidence Policy

Evidence는 Golden Path의 핵심 산출물입니다.

local 기본 경로:

```text
reports/dev/<build-number>/
```

## Required Evidence

- `metadata.txt`
- `docker/build.log`
- `trivy/image-scan.json`
- `trivy/image-scan.txt`
- `sbom/` when SBOM generation is enabled
- `gate/gate-result.txt`
- `registry/login.log`
- `registry/push.log`
- `kubernetes/pods.txt`
- `kubernetes/service.txt`
- `kubernetes/deployment.txt`
- `events/pod-describe.txt`
- `events/image-pull-events.txt`
- `evidence-files.txt`
- `evidence-map.md`

Deploy mode별 추가 evidence:

- `helm/rendered.yaml`
- `helm/upgrade.log`
- `helm/status.txt`
- `gitops/diff.txt`
- `argocd/app-status.txt`
- `rescan/` for optional new-CVE impact analysis jobs
- `notifications/` for optional notification payload evidence

## Evidence Map

`evidence-map.md`는 아래 정보를 연결합니다.

- Build Number
- Git SHA
- Workload Name
- App Name
- Image
- Namespace
- Deploy Mode
- Trivy result
- Gate result
- Registry push status
- Kubernetes deployment status
- Helm release status
- ArgoCD status
- Evidence path

이 파일은 source부터 runtime까지 이어지는 추적선을 제공합니다.

## Rescan Value

Evidence는 배포 이후에도 사용할 수 있습니다. Scanner DB 또는 CVE feed가 바뀌었을 때, 저장된 SBOM과 image reference를 사용하면 이미 배포된 image가 영향을 받는지 다시 판단할 수 있습니다.

rescan evidence는 아래 정보를 연결하는 것이 좋습니다.

- original build number
- original Git SHA
- image repository and tag
- SBOM file path
- newly detected CVE IDs
- affected packages and versions
- fixed versions when available
- notification decision
- required action

