# AWS k3s Runbook

AWS VM/k3s 지원은 profile 방향입니다. 이 repo가 v1에서 AWS 인프라를 직접 생성하지는 않습니다.

## Intended Flow

AWS VM 환경에서는 GitHub repo를 clone해서 사용합니다.

```bash
git clone https://github.com/<YOUR_ID>/secure-k8s-delivery-path.git
cd secure-k8s-delivery-path
```

기준 profile은 `env/aws-k3s.env.example`입니다.

## Local kind와 다른 점

AWS에서는 아래 local 전용 값을 사용하지 않습니다.

- `localhost:9092`
- kind containerd mirror 설정
- Docker Desktop 가정
- local Jenkins container state

대신 아래 중 하나를 사용합니다.

- ECR registry URL
- DNS 기반 Harbor URL

예시:

```text
123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/secure-delivery/vulnbank:<tag>
harbor.secure-delivery.internal/secure-delivery/vulnbank:<tag>
```

## First Planned Workload

`vulnbank`는 AWS VM/k3s에서 첫 실전 워크로드로 온보딩할 후보입니다. v1에서는 placeholder이며, 이후 Dockerfile, manifest 또는 Helm values, workload-specific evidence 기대값을 추가해야 합니다.

## Recommended Deploy Mode

ArgoCD와 registry credential이 준비된 뒤에는 아래 값을 권장합니다.

```text
DEPLOY_MODE=argocd
ENFORCE_GATE=true
```

