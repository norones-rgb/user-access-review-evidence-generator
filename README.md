# User Access Review Evidence Generator

**PowerShell 7.2+ · Read-only identity governance control · Synthetic-first portfolio project**

Produces evidence for **User Access Review (UAR)** campaigns from exported identities, entitlements, reviewer decisions, application-source manifests, and optional prior-review baseline. It flags unresolved or potentially risky conditions without changing any directory, account, or application authorization.

> **Important:** This is a control-support utility, not an access certification system. A row marked `Approve` means the file reports a review decision; it does **not** prove that the reviewer was authorized, that access was appropriate, or that the decision was attested. A `Revoke` decision does not mean access has been removed. Confirm authoritative application exports, review permissions, and remediation ticket closure separately.

## Quick start (no AD, API tokens, or production data required)

```powershell
pwsh -NoProfile -File ./Invoke-UserAccessReview.ps1 -Mode Demo
```

A deterministic demo uses `2026-11-05T19:00:00Z` and writes to `output/`:

- `uar-findings.csv` — sortable prioritized review and evidence-gap findings.
- `uar-entitlement-evidence.csv` — one record per entitlement with reviewer decision, source quality, and baseline indicator.
- `uar-evidence.json` — structured findings, evidence rows, summary, **SHA-256 hashes** of inputs, and explicit warnings.
- `uar-dashboard.html` — self-contained offline dashboard with HTML-encoded content and no external scripts or network requests.

**Sample baseline:** 10 synthetic identities, 15 entitlements, 13 decision records, three source manifests, and **22 expected findings (2 critical, 12 high, 7 medium, 1 low)**. This is independently checked fixture math, **not** a claim that Pester has already passed on your machine.

## Supported modes

| Mode | Reads | Writes |
| --- | --- | --- |
| `Demo` | Repository's synthetic CSVs, local JSON config | Local reports only |
| `Csv` | User-supplied exported CSVs, local JSON config | Local reports only |

The tool has **no live directory query mode**, **no Graph/API calls**, **no access approvals**, **no provisioning**, **no removals**, and **no changes to reviewer decisions**. Exports must be gathered separately by authorized staff and correctly scoped to the review. CSV mode doesn't infer completeness from a file containing some users.

## Use your authorized review exports

```powershell
pwsh -NoProfile -File ./Invoke-UserAccessReview.ps1 `
  -Mode Csv `
  -IdentityCsv './private-inputs/hr-identities.csv' `
  -EntitlementCsv './private-inputs/application-entitlements.csv' `
  -DecisionCsv './private-inputs/reviewer-decisions.csv' `
  -SourceCsv './private-inputs/source-manifest.csv' `
  -BaselineCsv './private-inputs/prior-baseline.csv' `
  -ConfigPath './config/default.json' `
  -AsOfUtc '2026-11-05T19:00:00Z' `
  -OutputDirectory './private-output'
```

`-BaselineCsv` is optional. Without it, `InBaseline` reports `Unknown` and the `NEW_ACCESS_SINCE_BASELINE` rule is disabled. `-AsOfUtc` is mandatory in `Csv` mode; the engine refuses ambiguous time input. All timestamps must be UTC ISO 8601, ending in `Z` (seconds required).

The supplied example configuration is for **synthetic demo purposes**. Change `ReviewId`, `ReviewDueUtc`, expected applications, and grace periods to match an authorized campaign before analyzing real exports. Protect `private-inputs` and `private-output` outside the public repo.

## What it finds

- Terminated identities with active access after a configurable grace period, with an explicit recent-termination grace status.
- Inactive HR identities retaining active application entitlements.
- Revoke decisions while the entitlement export still reports active access, accounting for remediation grace.
- Active privileged entitlements with no final reviewer decision.
- Missing or pending decisions after a review deadline.
- Privileged identity records without a manager for accountability review.
- Exception decisions lacking a tracked ticket/reference.
- Unexpected entitlements absent from the *optional* prior baseline, changed assignments/privileges, and baseline IDs absent from current export (never assumed revoked).
- Entitlements pointing to unknown HR identities; status is **unknown**, not presumed terminated.
- Incomplete/stale/missing source manifests and entitlements outside expected application scope. These are **evidence gaps**, not passing controls.

See [full rule catalog](docs/rules.md) and [input mapping](docs/input-schema.md).

## Directory structure

```text
user-access-review-evidence-generator/
├── .github/workflows/ci.yml
├── .gitattributes
├── .gitignore
├── Invoke-UserAccessReview.ps1
├── src/UserAccessReviewEvidence.psm1
├── config/default.json
├── sample-data/
│   ├── identities.csv
│   ├── entitlements.csv
│   ├── decisions.csv
│   ├── source-manifest.csv
│   └── baseline.csv
├── tests/UserAccessReviewEvidence.Tests.ps1
├── docs/
│   ├── architecture.md
│   ├── input-schema.md
│   ├── rules.md
│   ├── expected-fixture.md
│   ├── pilot-checklist.md
│   └── fixture-preview.html
├── SECURITY.md
├── NOTICE
└── output/.gitkeep
```

## Tests and CI

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force
Import-Module Pester -MinimumVersion 5.5.0
Invoke-Pester -Path ./tests -CI -Output Detailed
```

Tests cover fixture totals, incomplete evidence, grace periods, SHA-256 provenance, four output formats, duplicate keys, cross-cycle decisions, future-dated observations, missing schema columns, omitted source manifests, HTML escaping and formula-injection protection in CSV. GitHub Actions runs on Ubuntu and Windows PowerShell 7.2+ and separately executes the demo.

The reference implementation is authored for PowerShell 7.2+; **CI execution and real-world correctness must be verified independently** before any authorized pilot.

## Operational and security controls

1. Keep all real HR/user/application data off public repositories; never commit actual exports, generated outputs, access tickets, credentials, or secrets.
2. Acquire exports using approved methods; classify and store them under least privilege, with retention and deletion controls.
3. Match identities on stable `IdentityId` (never on display name) and entitlements on a stable, unique `EntitlementId` per campaign. Record any key normalization logic.
4. Require source owner confirmation of scope and freshness. `IsComplete=True` is a **claim in an input**, not proof.
5. Review high/critical findings manually, reconcile discrepancies with the actual application system of record, and maintain review/closure evidence in the source GRC/ITSM platform.
6. Never interpret a clean finding list as compliance certification or use this tool to automatically approve/revoke access.

Read [SECURITY.md](SECURITY.md) and [pilot checklist](docs/pilot-checklist.md) before considering real data.

## Constraints and limitations

- CSV input schema is fixed and intentionally narrow; vendor exports from SailPoint, ServiceNow, AD, or application platforms require a **separate, reviewed normalization step**. It makes no claims of direct vendor integration or SailPoint configuration.
- Reviewer identity and decision strings are imported, **not cryptographically signed or independently verified**.
- `SourceMaxAgeDays` and grace periods operate against the supplied `AsOfUtc`; they are policy parameters, not legal standards.
- Baseline comparison uses entitlement IDs only. Reissued IDs, renamed privileges, or changed application account mappings require explicit normalization and may produce misleading change indicators.
- CSV is protected against common spreadsheet formula interpretation when exported, but downstream software and data classification policies remain relevant.
- The evidence JSON contains account IDs, resource names, decisions and ticket references; treat every generated report as potentially sensitive.
- The project does not claim coverage of shared, machine, or nonhuman identities unless your input normalization provides a documented identity mapping.
- If source coverage is partial, conclusions about absent access are prohibited; output state will remain `Incomplete` when flagged by manifest checks.

## Roadmap

After the first successful Windows/Linux CI run: add a normalization adapter for approved SailPoint/ServiceNow exports; enforce reviewer independence when authoritative reviewer-role data exists; add attestation timestamps and evidence integrity signatures; add historical comparison across quarterly campaigns; add exception aging and closure-status reconciliation. All remain **read-only** unless a separate fully authorized and reviewed remediation component is explicitly designed.

## Ownership and use

Copyright (c) 2026. See [NOTICE](NOTICE). No open-source license has been granted by publication alone. Portfolio demo code, synthetic data only.