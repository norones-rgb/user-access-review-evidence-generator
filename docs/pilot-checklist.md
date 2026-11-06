# Controlled pilot checklist

Use synthetic fixtures first. **This is not authorization to run on any organization's HR, SailPoint, ServiceNow, AD, or application data.**

## Preparation

- [ ] Confirm written permission, responsible owner, reviewer roles, approved application scope, and handling/retention requirements.
- [ ] Run GitHub Actions on Windows and Linux; investigate any Pester failures.
- [ ] Verify source timestamps, account identifiers and entitlement ID stability, including rehires, contractors and service accounts.
- [ ] Validate config `ReviewId`, review deadline, expected apps, criticality mapping, source freshness and grace periods.
- [ ] Obtain authorized HR identities and application entitlements. Map exports offline using a documented, peer-reviewed normalization step.
- [ ] Obtain complete app-source manifests attested by export owner and verify export row counts independently.
- [ ] Obtain reviewer decisions for the **same campaign**, and check reviewers' actual authorization in the system of record.
- [ ] If comparing against prior UAR: confirm baseline identity and entitlement ID mapping consistency.
- [ ] Use a protected output folder outside the Git repository and define access/retention controls.

## Run, inspect and close

- [ ] Run `-Mode Csv` with an explicit UTC as-of timestamp and non-production output path.
- [ ] Treat any `EvidenceGap`, stale source, missing/pending decision, and unknown identity as unresolved.
- [ ] Cross-check critical/high findings in authoritative application and HR systems.
- [ ] Validate revoke/exception tickets and closure evidence; do **not** infer closure from reviewer decisions alone.
- [ ] Sample low/no-finding records and confirm that missing source rows have not been mistaken for revocations.
- [ ] Archive hash manifest and run parameters in approved audit evidence management, not public GitHub.
- [ ] Restrict exports/results; securely delete copies when retention period ends.
- [ ] Obtain independent human sign-off in formal governance process. This tool never certifies compliance.

## Stop conditions

Stop if scope is uncertain, CSVs have duplicate keys, reviewer decisions belong to another campaign, IDs fail correlation, exports are incomplete, source timestamps are unreliable, or a meaningful test fails. Fix source quality first; do not change source risk settings solely to hide findings.
