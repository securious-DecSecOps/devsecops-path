# secure-k8s-delivery-path Context Kit

이 키트는 Codex에게 현재 프로젝트 상황과 방향을 정확히 알려주기 위한 Markdown 파일 모음입니다.

## 사용 방법

WSL에서 새 repo 경로로 이동합니다.

```bash
cd ~/secure-k8s-delivery-path
```

이 키트의 파일들을 repo에 복사한 뒤, Codex를 실행합니다.

Codex 첫 프롬프트로는 아래 파일을 붙여넣으면 됩니다.

```text
prompts/CODEX_BOOTSTRAP_PROMPT.md
```

## 핵심 목적

- `secubank` 졸업프로젝트와 분리된 도메인 중립 오픈소스 템플릿으로 만든다.
- 현재 수동으로 검증한 Jenkins-Harbor-kind 배포 경로를 Pipeline as Code로 정리한다.
- local-kind MVP부터 Helm + ArgoCD 기반 표준 배포 경로를 포함한다.
- 이후 aws-k3s / aws-2vm에서 GitHub repo를 pull해 같은 golden path를 재사용한다.
