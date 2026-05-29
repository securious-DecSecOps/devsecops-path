#!/usr/bin/env bash
# SNS 보안 알림 — Security Gate 결과를 SNS 토픽으로 publish (이메일/SMS 구독자에게 전달).
# 선택적으로 검증된 번호에 직접 SMS(도쿄 리전). 빌드를 절대 깨지 않는다(모든 실패 무시).
set -uo pipefail

SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:ap-northeast-2:428156589833:secubank-security-alerts}"
SNS_REGION="${SNS_REGION:-ap-northeast-2}"
APP_NAME="${APP_NAME:-vulnbank-msa}"
WORKLOAD_NAME="${WORKLOAD_NAME:-${APP_NAME}}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"
REPORT_DIR="${REPORT_DIR:-reports/dev/${BUILD_NUMBER}}"
gate="${REPORT_DIR}/gate/aggregated-summary.txt"

result="UNKNOWN"
if [[ -f "$gate" ]]; then
  if grep -q 'GATE_RESULT=BLOCK' "$gate"; then result="BLOCK"; else result="PASS"; fi
fi
crit="$(grep -oE 'CRITICAL_COUNT=[0-9]+' "$gate" 2>/dev/null | head -1 | cut -d= -f2)"
high="$(grep -oE 'HIGH_COUNT=[0-9]+' "$gate" 2>/dev/null | head -1 | cut -d= -f2)"
enforce="${ENFORCE_GATE:-false}"

subject="[SecuBank CI] ${APP_NAME} #${BUILD_NUMBER} Security Gate: ${result}"
subject="${subject:0:99}"
reasons="$(grep -A8 'BLOCK_REASONS_BEGIN' "$gate" 2>/dev/null | grep '^- ' | head -5)"
msg="SecuBank DevSecOps CI — Security Gate Notification

workload : ${WORKLOAD_NAME}
build    : #${BUILD_NUMBER}
result   : ${result}   (enforce_gate=${enforce})
trivy    : CRITICAL=${crit:-?} HIGH=${high:-?}   (policy: max CRITICAL 0 / HIGH 3)
evidence : ${REPORT_DIR}/  (gitleaks·sonarqube·checkov·kubescape·sbom·trivy·gate)
${reasons:+
top block reasons:
${reasons}}"

if ! command -v aws >/dev/null 2>&1; then
  echo "[notify-sns] aws CLI not found; skip"; exit 0
fi

aws sns publish --region "$SNS_REGION" --topic-arn "$SNS_TOPIC_ARN" \
  --subject "$subject" --message "$msg" >/dev/null 2>&1 \
  && echo "[notify-sns] topic published (result=${result})" \
  || echo "[notify-sns] WARN: topic publish failed (IAM sns:Publish / topic ARN 확인)"

# 선택: 검증된 번호로 직접 SMS (SMS_PHONE 설정 시에만; 도쿄 리전).
if [[ -n "${SMS_PHONE:-}" ]]; then
  aws sns publish --region "${SMS_REGION:-ap-northeast-1}" --phone-number "$SMS_PHONE" \
    --message "[SecuBank CI] ${APP_NAME} #${BUILD_NUMBER} gate=${result} crit=${crit:-?} high=${high:-?}" >/dev/null 2>&1 \
    && echo "[notify-sns] SMS sent to ${SMS_PHONE}" \
    || echo "[notify-sns] WARN: SMS 실패 (샌드박스 번호검증 필요?)"
fi
exit 0
