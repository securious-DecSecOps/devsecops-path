# AWS Migration Context

## Important Principle

AWS migration does not mean copying local kind settings.

The portable assets are:

```text
application source
Dockerfile
Kubernetes manifests
Helm chart
ArgoCD Application manifests
Jenkinsfile
scripts
security gate policy
reports/evidence structure
documentation
```

The non-portable local settings are:

```text
localhost:9092
kind node containerd mirror
172.18.0.1 gateway
local kubeconfig
local Jenkins container state
local Docker login files
```

## AWS k3s Profile

AWS k3s profile should replace:

```text
localhost:9092
```

with either:

```text
ECR registry URL
```

or:

```text
DNS-based Harbor URL
```

Example ECR:

```text
123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/secure-delivery/myapp:<git-sha>
```

Example Harbor:

```text
harbor.secure-delivery.internal/secure-delivery/myapp:<git-sha>
```

## AWS 2-VM Direction

Final planned structure:

```text
EC2-1: Runtime
- k3s
- ArgoCD
- application workloads
- runtime validation tools later

EC2-2: Supply Chain Security
- Jenkins
- Docker build
- Trivy
- Harbor
- Checkov later
```

## Phasing

Do not implement AWS now.

Keep AWS provisioning out of the local MVP, but keep Helm and ArgoCD in the
standard path so the same GitHub repository can be pulled onto AWS VMs and used
without redesigning the deployment model.
