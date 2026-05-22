# Jenkins Pipeline from SCM Setup

## Why Pipeline from SCM?

Pipeline from SCM keeps the CI/CD logic in Git.

This is better than pasting a pipeline script into Jenkins UI because:

- Jenkinsfile is version-controlled.
- Changes can be reviewed.
- The pipeline is portable.
- GitHub can be used as the source of truth.
- The same pipeline can later support AWS profiles.

## Jenkins UI Steps

Create a new item:

```text
New Item
→ secure-k8s-delivery-path-local-kind
→ Pipeline
```

Configure:

```text
Pipeline Definition: Pipeline script from SCM
SCM: Git
Repository URL: https://github.com/<YOUR_ID>/secure-k8s-delivery-path.git
Branch Specifier: */main
Script Path: Jenkinsfile
```

Then:

```text
Save
→ Build Now
```

## Required Jenkins assumptions

The local Jenkins container should have:

```text
docker
kubectl
trivy
python3
access to Docker daemon
KUBECONFIG=/var/jenkins_home/kubeconfig
```

The kind cluster and local Harbor must already be reachable.
