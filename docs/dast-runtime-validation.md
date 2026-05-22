# DAST and Runtime Validation Extension

DAST와 runtime check는 배포 이후 검증 계층입니다.

이 결과들은 환경 맥락과 수동 검토가 필요한 경우가 많기 때문에 기본 supply-chain gate와 분리합니다.

## Position in the Path

```text
pre-deployment checks
-> deployment
-> DAST/runtime validation
-> evidence and follow-up action
```

## DAST

Baseline web check는 header, cookie, passive finding 증적을 남기는 데 사용할 수 있습니다.

Active testing은 소유하고 허가된 test environment에서만 수행해야 합니다.

일반 scanner로 부족한 경우 workload별 domain-specific check를 추가할 수 있습니다. Golden Path가 재사용 가능하도록 이러한 check는 workload adapter 디렉터리나 별도 test script에 두는 것을 권장합니다.

## Runtime Security

Runtime security 도구는 나중에 아래 evidence를 추가할 수 있습니다.

- network flow
- process behavior
- policy enforcement
- suspicious runtime events

예시는 Cilium/Hubble, Falco, NetworkPolicy check, log-based validation입니다. 이 항목들은 local MVP 필수 기능이 아닙니다.

