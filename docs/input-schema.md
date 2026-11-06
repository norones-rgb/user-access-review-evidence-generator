# Input CSV schema and mapping guidance

UTF-8 CSV with a single exact-case header row. The parser uses PowerShell `Import-Csv`. Header names must match these field names exactly. Columns may appear in any order. No embedded comma in header names. Data values may contain quoted commas according to CSV escaping rules.

## `identities.csv`

| Column | Required meaning |
| --- | --- |
| `IdentityId` | Nonblank, unique, stable HR identity key; NOT display name |
| `DisplayName` | Display-only optional label; not used for correlation |
| `EmploymentStatus` | Exact value: `Active`, `Inactive`, `Terminated`, or `Leave` |
| `ManagerId` | Manager/owner ID, may be blank (flagged for privileged access) |
| `TerminationDateUtc` | UTC time for terminated identities; mandatory if `Terminated` |
| `Department` | Informational only |

## `entitlements.csv`

| Column | Required meaning |
| --- | --- |
| `EntitlementId` | Nonblank unique stable entitlement key within campaign |
| `IdentityId` | Source-to-HR correlation key; can be unknown but will be flagged |
| `Application` | Application name matching config and manifest |
| `Resource` | Exact entitlement, role or resource name |
| `Privilege` | `Standard` or `Privileged`; based on documented mapping |
| `Status` | `Active` or `Disabled` as reported by application source |
| `ObservedAtUtc` | ISO UTC observation timestamp |
| `SourceSystem` | Provenance label for exporting system |

## `decisions.csv`

| Column | Required meaning |
| --- | --- |
| `ReviewId` | Must equal config `ReviewId`; cross-campaign rows rejected |
| `EntitlementId` | References a known entitlement; duplicate or unknown rejected |
| `Decision` | `Approve`, `Revoke`, `Exception`, `Pending` |
| `ReviewerId` | Nonblank reviewer ID; identity/authority not verified by analyzer |
| `DecisionAtUtc` | ISO UTC timestamp |
| `TicketId` | ITSM/remediation/exception tracking ref; may be blank (flagged for `Exception`) |
| `Note` | Optional; not exported in full to reduce data handling |

Rows with no decision are permitted and flagged. An approval record is **not** evidence of appropriately authorized approval by itself.

## `source-manifest.csv`

| Column | Required meaning |
| --- | --- |
| `Application` | Unique application name for export |
| `ExportedAtUtc` | ISO UTC timestamp of relevant export |
| `IsComplete` | Exact `True` or `False` as asserted by source owner |
| `CoverageNote` | Human explanation of export scope or gaps |

All expected applications from config must be present; absent applications produce high-priority evidence gaps. A source export that is past the configured max age is stale. Entitlements from applications outside expected scope are flagged.

## `baseline.csv` (optional)

| Column | Required meaning |
| --- | --- |
| `EntitlementId` | Unique entitlement ID as previously represented |
| `IdentityId` | Identity key |
| `Application` | Application name |
| `Resource` | Resource name |
| `Privilege` | Privilege classification |

The `EntitlementId` is the baseline join key; identity, application, resource, and privilege are checked for changes. Re-keying or renamed entitlements need separate upstream normalization. A baseline entitlement absent from current export is **not** proof that access was revoked.

## Configuration (`config/default.json`)

- `ReviewId` — exact campaign identifier.
- `ReviewDueUtc` — strictly formatted UTC review deadline.
- `ExpectedApplications` — distinct application names required for scope completeness.
- `SourceMaxAgeDays` — integer max age of source exports.
- `TerminationGraceDays` — integer number of days after termination to classify as critical.
- `RevocationGraceDays` — integer number of days after reviewer revoke decision to classify as critical.

### Provenance limitations

Every input file is hashed SHA-256. Hashes prove only equality to the hashed bytes, not ownership, completeness, digital signing, reviewer authority, or regulatory sufficiency. No column contains passwords, tokens, session data, or private keys.
