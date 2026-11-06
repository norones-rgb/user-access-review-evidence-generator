#Requires -Version 7.2
BeforeAll {
    $project = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $project 'src/UserAccessReviewEvidence.psm1') -Force
    $sample = Join-Path $project 'sample-data'
    $sampleParams = @{
        IdentityCsv = Join-Path $sample 'identities.csv'
        EntitlementCsv = Join-Path $sample 'entitlements.csv'
        DecisionCsv = Join-Path $sample 'decisions.csv'
        SourceCsv = Join-Path $sample 'source-manifest.csv'
        BaselineCsv = Join-Path $sample 'baseline.csv'
        ConfigPath = Join-Path $project 'config/default.json'
        AsOfUtc = '2026-11-05T19:00:00Z'
    }
}

Describe 'UAR synthetic fixture' {
    It 'reconciles expected records without modifying source files' {
        $before = (Get-FileHash $sampleParams.EntitlementCsv -Algorithm SHA256).Hash
        $result = Invoke-UarEvidenceReview @sampleParams
        $result.Summary.IdentityCount | Should -Be 10
        $result.Summary.EntitlementCount | Should -Be 15
        $result.Summary.DecisionCount | Should -Be 13
        $result.Summary.FindingCount | Should -Be 22
        $result.Summary.CriticalCount | Should -Be 2
        $result.Summary.HighCount | Should -Be 12
        $result.Summary.MediumCount | Should -Be 7
        $result.Summary.LowCount | Should -Be 1
        (Get-FileHash $sampleParams.EntitlementCsv -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'never labels incomplete evidence as a completed review' {
        $result = Invoke-UarEvidenceReview @sampleParams
        $result.Summary.SourceEvidenceState | Should -Be 'Incomplete'
        $result.Summary.ReviewEvidenceState | Should -Be 'Incomplete'
        $result.Summary.MissingDecisionCount | Should -Be 2
        $result.Summary.PendingDecisionCount | Should -Be 2
        @($result.Findings | Where-Object Rule -eq 'SOURCE_EXPORT_STALE').Count | Should -Be 1
        @($result.Findings | Where-Object Rule -eq 'SOURCE_EXPORT_INCOMPLETE').Count | Should -Be 1
    }

    It 'distinguishes terminated access and recent revocation grace periods' {
        $result = Invoke-UarEvidenceReview @sampleParams
        @($result.Findings | Where-Object Rule -eq 'TERMINATED_IDENTITY_ACTIVE_ACCESS').Count | Should -Be 1
        @($result.Findings | Where-Object Rule -eq 'TERMINATION_WITHIN_GRACE').Count | Should -Be 1
        @($result.Findings | Where-Object Rule -eq 'REVOKE_DECISION_ACCESS_ACTIVE').Count | Should -Be 1
        @($result.Findings | Where-Object Rule -eq 'REVOKE_REMEDIATION_IN_GRACE').Count | Should -Be 1
    }

    It 'records provenance hashes without embedding absolute source paths' {
        $result = Invoke-UarEvidenceReview @sampleParams
        $result.InputEvidence.Count | Should -Be 6
        foreach ($record in $result.InputEvidence) {
            $record.SHA256 | Should -Match '^[0-9a-f]{64}$'
            $record.FileName | Should -Not -Match '[\\/]'
        }
    }

    It 'writes all HTML CSV and JSON reports and preserves report row counts' {
        $result = Invoke-UarEvidenceReview @sampleParams
        $out = Join-Path $TestDrive 'reports'
        $paths = Export-UarEvidenceReports -Result $result -OutputDirectory $out
        Test-Path -LiteralPath $paths.FindingsCsv | Should -BeTrue
        Test-Path -LiteralPath $paths.EvidenceCsv | Should -BeTrue
        Test-Path -LiteralPath $paths.Json | Should -BeTrue
        Test-Path -LiteralPath $paths.Html | Should -BeTrue
        @(Import-Csv -LiteralPath $paths.FindingsCsv).Count | Should -Be 22
        @(Import-Csv -LiteralPath $paths.EvidenceCsv).Count | Should -Be 15
        $json = Get-Content -LiteralPath $paths.Json -Raw | ConvertFrom-Json
        $json.Summary.FindingCount | Should -Be 22
        (Get-Content -LiteralPath $paths.Html -Raw) | Should -Match 'Not a certification'
    }
}

Describe 'Fail closed on malformed or conflicting evidence' {
    It 'rejects duplicate entitlement keys' {
        $tmp = Join-Path $TestDrive 'duplicate-entitlements.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.EntitlementCsv)
        $rows[1].EntitlementId = $rows[0].EntitlementId
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.EntitlementCsv = $tmp
        { Invoke-UarEvidenceReview @p } | Should -Throw '*duplicate EntitlementId*'
    }

    It 'rejects review decisions from the wrong campaign' {
        $tmp = Join-Path $TestDrive 'wrong-cycle.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.DecisionCsv)
        $rows[0].ReviewId = 'UAR-2025-Q3'
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.DecisionCsv = $tmp
        { Invoke-UarEvidenceReview @p } | Should -Throw '*Cross-cycle*'
    }

    It 'rejects future access observations' {
        $tmp = Join-Path $TestDrive 'future.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.EntitlementCsv)
        $rows[0].ObservedAtUtc = '2099-01-01T01:01:01Z'
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.EntitlementCsv = $tmp
        { Invoke-UarEvidenceReview @p } | Should -Throw '*future observation*'
    }

    It 'flags changed assignments for an existing baseline entitlement' {
        $tmp = Join-Path $TestDrive 'changed-assignment.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.EntitlementCsv)
        $rows[0].Resource = 'ElevatedSalesRead'
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.EntitlementCsv = $tmp
        $result = Invoke-UarEvidenceReview @p
        @($result.Findings | Where-Object Rule -eq 'BASELINE_ENTITLEMENT_CHANGED').Count | Should -Be 1
        $result.Summary.FindingCount | Should -Be 23
    }

    It 'never treats missing baseline rows as verified access removal' {
        $tmp = Join-Path $TestDrive 'extra-baseline.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.BaselineCsv)
        $rows += [pscustomobject]@{ EntitlementId='E999'; IdentityId='U001'; Application='CRM'; Resource='LegacyExport'; Privilege='Standard' }
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.BaselineCsv = $tmp
        $result = Invoke-UarEvidenceReview @p
        @($result.Findings | Where-Object Rule -eq 'BASELINE_ENTITLEMENT_NOT_IN_CURRENT_EXPORT').Count | Should -Be 1
        $result.Summary.ReviewEvidenceState | Should -Be 'Incomplete'
    }

    It 'rejects missing CSV columns' {
        $tmp = Join-Path $TestDrive 'missing-column.csv'
        Set-Content -LiteralPath $tmp -Value @('EntitlementId,IdentityId,Application','E001,U001,CRM')
        $p = $sampleParams.Clone(); $p.EntitlementCsv = $tmp
        { Invoke-UarEvidenceReview @p } | Should -Throw '*missing required column*'
    }

    It 'rejects duplicate review decisions' {
        $tmp = Join-Path $TestDrive 'duplicate-decisions.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.DecisionCsv)
        $rows[1].EntitlementId = $rows[0].EntitlementId
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.DecisionCsv = $tmp
        { Invoke-UarEvidenceReview @p } | Should -Throw '*duplicate EntitlementId*'
    }

    It 'treats a missing required source as an evidence gap' {
        $tmp = Join-Path $TestDrive 'missing-source.csv'
        @(Import-Csv -LiteralPath $sampleParams.SourceCsv | Where-Object Application -ne 'FinanceERP') |
            Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.SourceCsv = $tmp
        $result = Invoke-UarEvidenceReview @p
        @($result.Findings | Where-Object Rule -eq 'SOURCE_EXPORT_MISSING').Count | Should -Be 1
        $result.Summary.SourceEvidenceState | Should -Be 'Incomplete'
    }
}

Describe 'Safe reporting' {
    It 'escapes HTML payloads from untrusted source columns' {
        $tmp = Join-Path $TestDrive 'html-payload.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.EntitlementCsv)
        $rows[0].Application = '<img src=x onerror=alert(1)>'
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.EntitlementCsv = $tmp
        $result = Invoke-UarEvidenceReview @p
        $paths = Export-UarEvidenceReports -Result $result -OutputDirectory (Join-Path $TestDrive 'safe-html')
        $html = Get-Content -LiteralPath $paths.Html -Raw
        $html | Should -Not -Match '<img src=x'
        $html | Should -Match '&lt;img src=x'
    }

    It 'neutralizes spreadsheet formula payloads in CSV exports' {
        $tmp = Join-Path $TestDrive 'csv-formula.csv'
        $rows = @(Import-Csv -LiteralPath $sampleParams.EntitlementCsv)
        $rows[0].Resource = '=HYPERLINK("https://example.invalid")'
        $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
        $p = $sampleParams.Clone(); $p.EntitlementCsv = $tmp
        $result = Invoke-UarEvidenceReview @p
        $paths = Export-UarEvidenceReports -Result $result -OutputDirectory (Join-Path $TestDrive 'safe-csv')
        $row = Import-Csv -LiteralPath $paths.EvidenceCsv | Where-Object EntitlementId -eq 'E001'
        $row.Resource.StartsWith("'=HYPERLINK") | Should -BeTrue
    }
}
