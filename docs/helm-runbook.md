# Helm Runbook

`DEPLOY_MODE=helm`은 ArgoCD 없이 표준 Helm chart 경로를 검증할 때 사용합니다.

## Commands

```bash
helm lint helm/simple-web
helm template simple-web helm/simple-web
```

Pipeline의 deploy script는 내부적으로 아래와 같은 형태를 실행합니다.

```bash
helm upgrade --install "$HELM_RELEASE" "$HELM_CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set "nameOverride=$APP_NAME" \
  --set "namespace=$NAMESPACE" \
  --set "image.repository=$IMAGE_REPOSITORY" \
  --set "image.tag=$IMAGE_TAG"
```

## Evidence

Helm 관련 증적은 아래 경로에 저장됩니다.

```text
reports/dev/<build-number>/helm/
```

예상 파일:

- `rendered.yaml`
- `upgrade.log`
- `status.txt`

Kubernetes rollout 증적은 여전히 `kubernetes/` 아래에 저장됩니다.

