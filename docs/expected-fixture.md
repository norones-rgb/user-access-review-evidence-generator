# Synthetic fixture expected behavior

Deterministic as-of time: **2026-11-05T19:00:00Z**. This package uses fabricated accounts and systems. The rule totals were calculated independently from CSVs; passing Pester execution is still required for runtime confirmation.

| Metric | Expected |
| --- | ---: |
| HR identities | 10 |
| Entitlements | 15 |
| Reviewer decision rows | 13 |
| Missing decisions | 2 |
| Pending decisions | 2 |
| Findings | **22** |
| Critical | **2** |
| High | **12** |
| Medium | **7** |
| Low | **1** |

## Expected findings by rule

| Rule | Expected count |
| --- | ---: |
| SOURCE_EXPORT_INCOMPLETE | 1 |
| SOURCE_EXPORT_STALE | 1 |
| ENTITLEMENT_SOURCE_UNVERIFIED | 1 |
| IDENTITY_NOT_IN_HR_EXPORT | 1 |
| TERMINATED_IDENTITY_ACTIVE_ACCESS | 1 |
| TERMINATION_WITHIN_GRACE | 1 |
| INACTIVE_IDENTITY_ACTIVE_ACCESS | 1 |
| PRIVILEGED_ACCESS_UNREVIEWED | 2 |
| REVIEW_DECISION_OVERDUE | 4 |
| REVOKE_DECISION_ACCESS_ACTIVE | 1 |
| REVOKE_REMEDIATION_IN_GRACE | 1 |
| EXCEPTION_WITHOUT_REFERENCE | 1 |
| PRIVILEGED_ACCESS_MISSING_MANAGER | 1 |
| NEW_ACCESS_SINCE_BASELINE | 5 |

Example scenarios: E002 is terminated and still active beyond grace following a revoke decision; E007 is recently terminated and within both grace windows; E003 lacks a reviewer decision for privileged access; E014 has an unknown HR identity, which is an evidence gap, not proof of termination; the CodeRepo manifest is stale; the CRM manifest reports incomplete scope.

No actual person's access or HR information was used.
