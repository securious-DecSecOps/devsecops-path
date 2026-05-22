# Alerting Extension

Alerting은 기본 템플릿의 선택 확장입니다. MVP는 외부 webhook, cloud permission, chat integration 없이도 동작해야 합니다.

## Typical Alert Events

- enforce mode에서 security gate 실패
- new-CVE rescan에서 조치가 필요한 영향 발견
- post-deployment validation에서 high-risk behavior 발견

## Suggested Channels

- generic webhook
- Slack webhook
- AWS SNS
- ticketing system integration

## Suggested Payload Fields

- workload
- build number
- image tag
- finding summary
- gate or validation result
- evidence path
- action required

## Implementation Guidance

실제 알림 전송은 기본값으로 비활성화하는 것을 권장합니다. 먼저 notification payload를 evidence로 저장하고, credential과 운영 책임이 명확해진 뒤 실제 전송을 활성화하세요.

