# Security and privacy policy

## Read-only boundary

The analyzer reads local, explicitly supplied CSV and JSON files and writes only local reports. It never authenticates to AD/LDAP, SailPoint, ServiceNow, an application endpoint or a third-party service; never changes access, and never silently accepts pending decisions. It does not send telemetry or make network calls. GitHub Actions installs Pester and runs only against fabricated repo data.

## Threat model and mitigations

| Threat | Defensive behavior | Residual limitation |
| --- | --- | --- |
| Untrusted CSV injection | Exported CSV text starting with spreadsheet formula triggers (`=`, `+`, `-`, `@`, tabs/newlines after whitespace) is prefixed with apostrophe | Always test with your actual spreadsheet software and never enable untrusted macros |
| HTML injection | HTML-encode all interpolated source values; offline HTML declares a restrictive CSP | A hostile local file viewer or browser extension is outside scope |
| Ambiguous identities | Stable identity and entitlement IDs required; duplicate/blank keys rejected | IDs must be normalized and joined correctly upstream |
| Wrong review cycle | Decision `ReviewId` must exactly equal configured review ID; unknown decision entitlement rejected | Reviewer authorization and signing not independently checked |
| False clean result | Missing, stale, or incomplete required source manifests generate evidence gaps; missing or pending review decisions remain open | Fabricated `IsComplete=True` cannot be detected without independent source-owner verification |
| Time manipulation | Strict UTC timestamps; `Csv` mode requires `AsOfUtc`; future observations and decisions rejected | System-supplied timestamps still require source verification |
| Sensitive data exposure | IDs and hashes instead of full source paths; outputs ignored by git; no credentials accepted | Evidence reports themselves contain identifiers and entitlement details |
| Unsafe remediation | Findings contain human review actions only; no auto-provision, revoke, approve, or ticket closure | Human operators are responsible for authorized workflows |

## Minimum handling controls

- Use authorized input exports only; strip unnecessary PII and secrets before import.
- Secure private working folders; restrict account IDs, access details, reviewer IDs, and tickets according to organizational policy.
- Do not publish report files, raw exports, confidential exception notes, hashes of sensitive files, or copied customer data in public GitHub repositories.
- Use an isolated evaluation environment with least-privilege read access and a retention/deletion plan.
- Verify source owners, export generation time, completeness and identity correlation *outside* this tool.
- Treat findings as **triage signals**, not proof of wrongdoing or a compliance finding on their own.
- Reports contain input SHA-256 hashes to support integrity comparisons, not cryptographic proof of origin or authenticity.
- Examine modifications and run Pester before considering use with non-synthetic data.

## Reporting a vulnerability

Report suspected vulnerabilities privately to the repository owner. Avoid including actual HR records, production account details, credentials or personal information. Do not file public issues containing sensitive data.
