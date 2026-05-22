# Jenkins Runtime Image

Jenkinsfile은 build와 delivery에 필요한 도구가 Jenkins container 안에 이미 설치되어 있다고 가정합니다. Pipeline 실행 때마다 package를 설치하지 않는 방향입니다.

이 image에는 아래 도구를 포함합니다.

- Docker CLI
- kubectl
- Helm
- Trivy
- Python 3
- jq
- git
- curl

Build example:

```bash
docker build -t secure-k8s-delivery-jenkins:local jenkins
```

Container에는 여전히 아래 접근이 필요합니다.

- local lab에서는 보통 `/var/run/docker.sock`을 통한 Docker daemon 접근
- `/var/jenkins_home/kubeconfig` 위치의 kubeconfig
- Jenkins Credentials 또는 환경변수를 통한 registry credential

local fallback registry credential은 smoke test 용도입니다. 운영 환경에서는 Jenkins Credentials, Harbor Robot Account, ECR IAM auth를 사용하세요.

