# Future SonarQube Integration

SonarQube is not implemented in v1.

It should enter the path before image build or before the final security gate:

```text
Source
-> SonarQube Scan
-> Quality Gate
-> Docker Build
-> Trivy Scan
-> Security Gate
```

Expected future evidence:

- project key
- branch or commit
- quality gate status
- issue counts
- link to SonarQube dashboard

The final gate can later combine SonarQube and Trivy results.

