# ArgoCD GitOps Runbook

`DEPLOY_MODE=argocd`는 ArgoCD가 설치되어 있고, 이 repo가 GitHub에 올라간 뒤 사용하는 경로입니다.

## Flow

1. Jenkins가 image build, scan, gate, push를 수행합니다.
2. `scripts/update-gitops-image.sh`가 아래 파일의 image 값을 업데이트합니다.

```text
gitops/apps/simple-web/dev/values.yaml
```

3. `scripts/deploy-argocd.sh`가 아래 Application manifest를 적용합니다.

```text
argocd/applications/simple-web-dev.yaml
```

4. ArgoCD가 Git에 선언된 desired state를 Kubernetes에 sync합니다.

## Required Manual Edit

실제 ArgoCD 사용 전 아래 placeholder를 바꿔야 합니다.

```text
https://github.com/REPLACE_ME/secure-k8s-delivery-path.git
```

본인 GitHub repository URL로 교체하세요.

## Kustomize and Helm

`gitops/apps/simple-web/dev/kustomization.yaml`은 환경별 values를 사용해 shared Helm chart를 렌더링합니다. 이 profile을 쓰려면 ArgoCD에서 Kustomize Helm support가 필요할 수 있습니다.

## Status Checks

ArgoCD CLI가 설치되어 있으면:

```bash
argocd app get simple-web-dev
argocd app sync simple-web-dev
```

CLI가 없으면:

```bash
kubectl apply -f argocd/applications/simple-web-dev.yaml
kubectl get application simple-web-dev -n argocd
```

## Evidence

ArgoCD 증적은 아래 파일에 저장됩니다.

```text
reports/dev/<build-number>/argocd/app-status.txt
```

