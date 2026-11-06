# Detection rules (v0.1)

| Rule | Severity | Condition | Category |
| --- | --- | --- | --- |
| `SOURCE_EXPORT_MISSING` | High | Required app absent from manifest | Evidence gap |
| `SOURCE_EXPORT_INCOMPLETE` | High | Manifest `IsComplete=False` | Evidence gap |
| `SOURCE_EXPORT_STALE` | High | Export exceeds `SourceMaxAgeDays` | Evidence gap |
| `ENTITLEMENT_SOURCE_UNVERIFIED` | High | Entitlement application not both configured and in manifest | Evidence gap |
| `IDENTITY_NOT_IN_HR_EXPORT` | High | Entitlement identity not in HR dataset | Evidence gap |
| `TERMINATED_IDENTITY_ACTIVE_ACCESS` | Critical | Terminated identity with active entitlement after grace | Risk finding |
| `TERMINATION_WITHIN_GRACE` | Medium | Terminated identity with active entitlement still within grace | Risk finding |
| `INACTIVE_IDENTITY_ACTIVE_ACCESS` | High | Inactive identity has active entitlement | Risk finding |
| `PRIVILEGED_ACCESS_UNREVIEWED` | High | Privileged active entitlement has pending/missing reviewer decision | Risk finding |
| `REVIEW_DECISION_OVERDUE` | High | Missing/pending decision after review due date | Risk finding |
| `REVOKE_DECISION_ACCESS_ACTIVE` | Critical | Active entitlement still observed after revoke decision grace | Risk finding |
| `REVOKE_REMEDIATION_IN_GRACE` | Medium | Active entitlement observed within revoke grace | Risk finding |
| `EXCEPTION_WITHOUT_REFERENCE` | High | Recorded exception without ticket/reference | Evidence gap |
| `PRIVILEGED_ACCESS_MISSING_MANAGER` | Medium | Privileged active entitlement has no HR manager | Evidence gap |
| `NEW_ACCESS_SINCE_BASELINE` | Medium for privileged / Low for standard | Active entitlement ID missing from supplied prior baseline | Change indicator |
| `BASELINE_ENTITLEMENT_CHANGED` | High if privileged / Medium otherwise | Same ID now maps to changed identity, app, resource, or privilege | Change indicator |
| `BASELINE_ENTITLEMENT_NOT_IN_CURRENT_EXPORT` | Medium | Prior entitlement ID absent from current export; removal not verified | Evidence gap |

**Notes**: A record may generate multiple findings (different reasons for investigation). Severity is a triage default. Adjust organization-specific policies, application classifications, and legal requirements in a future supported rules layer, not by assuming these defaults are universal.

## Important distinction: evidence versus state

A missing entitlement row in an incomplete export is **not** evidence of a successful revocation. This tool only evaluates entitlements that are present, plus explicit manifest coverage. Source manifests need independent scope and row-count validation before any control attestation.

## Fail-closed validation examples

The engine throws an error instead of generating a passing review when it sees duplicate entitlement/reviewer-decision keys, unknown reviewer decision entitlement IDs, wrong campaign IDs, future timestamps, malformed UTC timestamps, unsupported states or missing schema columns.
