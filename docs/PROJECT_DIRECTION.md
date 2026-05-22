# Project Direction

## Core Direction

`secure-k8s-delivery-path` is not a single application deployment project.

It is a reusable secure delivery path for Kubernetes workloads.

The project should answer:

```text
Can any workload be onboarded into a repeatable DevSecOps path with build, scan, gate, registry, deploy, and evidence?
```

The standard deployment path must include Helm and ArgoCD from the beginning:

```text
Source
→ Jenkins
→ Docker Build
→ Trivy Scan
→ Security Gate
→ Registry Push
→ Helm Chart
→ GitOps Repo Image Tag Update
→ ArgoCD GitOps Sync
→ Kubernetes Runtime
→ Evidence
```

## Why this is not secubank

The earlier graduation project context used `secubank` because the target scenario was a banking-style security platform.

However, this repository should be reusable by any domain.

Therefore:

```text
secure-k8s-delivery-path = reusable core template
secubank = historical/example context only, not the template default
```

## Target Users

Potential users:

- students learning DevSecOps
- security teams building a local proof of concept
- developers trying Jenkins + Trivy + Kubernetes
- teams needing a starter template for secure delivery

## Current MVP Scope

The first MVP is local-only:

```text
Jenkins
→ Docker Build
→ Trivy Scan
→ Security Gate
→ local Harbor
→ Helm
→ GitOps image tag update
→ ArgoCD
→ kind Kubernetes
→ Evidence Reports
```

## Non-goals for MVP

Do not implement these in the first MVP:

- AWS EC2 provisioning
- EKS
- Terraform
- DefectDojo
- Prometheus/Grafana
- Full multi-application runtime orchestration

Helm and ArgoCD are not non-goals. They are part of the standard delivery path.

Additional supply-chain tools such as SonarQube and runtime security tools such
as Cilium or Falco should be documented as future expansion points.
