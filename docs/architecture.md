# Architecture

`secure-k8s-delivery-path`는 워크로드 자산과 공통 delivery path를 분리합니다.

```text
examples/<workload>
  -> Jenkinsfile
  -> scripts/*
  -> registry
  -> k8s/base or helm/*
  -> gitops/apps/*
  -> argocd/applications/*
  -> reports/*
```

## Control Planes

Jenkins는 supply-chain automation plane입니다. 이미지를 빌드하고, Trivy를 실행하고, gate를 평가하고, 이미지를 push하고, evidence를 기록합니다.

Harbor 또는 ECR은 image registry plane입니다.

Kubernetes는 runtime plane입니다. local profile은 kind를 사용하고, AWS profile은 VM 위의 k3s를 대상으로 합니다.

Helm은 표준 package/rendering layer입니다.

ArgoCD는 표준 GitOps deployment controller입니다.

## Deploy Mode Split

`DEPLOY_MODE=kubectl`은 가장 빠른 local smoke path입니다.

`DEPLOY_MODE=helm`은 ArgoCD 없이 공식 chart 경로를 검증합니다.

`DEPLOY_MODE=argocd`는 `gitops/`의 desired state를 업데이트하고 배포를 ArgoCD에 맡깁니다.

## Security Scope

v1은 Trivy 기반 supply-chain image scanning과 Critical CVE gate를 구현합니다. Runtime security 도구는 future layer로 문서화합니다.

