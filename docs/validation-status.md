# Validation status for v0.1

**Checked without a PowerShell runtime:**

- All five synthetic CSV files parse cleanly and contain the expected columns/rows.
- JSON configuration parses cleanly and has the documented keys.
- Synthetic rule outcomes independently recomputed from the fixture: **22 findings** (2 critical, 12 high, 7 medium, 1 low).
- HTML fixture preview parses as static HTML and has no JavaScript or external assets.
- GitHub Actions workflow YAML parsed and includes Windows/Linux runners.
- The module includes all documented detection-rule identifiers, plus validation paths for duplicate keys, timestamps and reviewer decisions.
- Archive integrity and file count are checked after packaging.

**Not tested in this environment:**

- PowerShell module parse/load and execution in an actual `pwsh` process.
- Pester test runtime and GitHub Actions results.
- Behavior with live organization exports or any vendor-specific source.
- Correctness of a particular organization's review, offboarding or audit control requirements.

Before any real-data pilot, run Pester and the demonstration on PowerShell 7.2+ (GitHub Actions does this after publication), then peer-review the output against authoritative source data using the [pilot checklist](pilot-checklist.md). A locally generated demo report should not be represented as compliance certification.
