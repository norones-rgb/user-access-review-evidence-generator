#Requires -Version 7.2
[CmdletBinding()]
param(
    [ValidateSet('Demo','Csv')][string]$Mode = 'Demo',
    [string]$IdentityCsv,
    [string]$EntitlementCsv,
    [string]$DecisionCsv,
    [string]$SourceCsv,
    [string]$BaselineCsv,
    [string]$ConfigPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'output'),
    [string]$AsOfUtc
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/UserAccessReviewEvidence.psm1') -Force
if ($Mode -eq 'Demo') {
    $sample = Join-Path $PSScriptRoot 'sample-data'
    $IdentityCsv = Join-Path $sample 'identities.csv'
    $EntitlementCsv = Join-Path $sample 'entitlements.csv'
    $DecisionCsv = Join-Path $sample 'decisions.csv'
    $SourceCsv = Join-Path $sample 'source-manifest.csv'
    $BaselineCsv = Join-Path $sample 'baseline.csv'
    if ([string]::IsNullOrWhiteSpace($AsOfUtc)) { $AsOfUtc = '2026-11-05T19:00:00Z' }
}
else {
    foreach ($argName in @('IdentityCsv','EntitlementCsv','DecisionCsv','SourceCsv')) {
        if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $argName -ValueOnly))) {
            throw "Csv mode requires -$argName."
        }
    }
    if ([string]::IsNullOrWhiteSpace($AsOfUtc)) {
        throw 'Csv mode requires explicit -AsOfUtc to prevent ambiguous historical analysis.'
    }
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot 'config/default.json' }
$result = Invoke-UarEvidenceReview -IdentityCsv $IdentityCsv -EntitlementCsv $EntitlementCsv -DecisionCsv $DecisionCsv -SourceCsv $SourceCsv -BaselineCsv $BaselineCsv -ConfigPath $ConfigPath -AsOfUtc $AsOfUtc
$reports = Export-UarEvidenceReports -Result $result -OutputDirectory $OutputDirectory
Write-Host ("Review {0}: {1} entitlements, {2} findings ({3} critical, {4} high); evidence: {5}." -f $result.Summary.ReviewId, $result.Summary.EntitlementCount, $result.Summary.FindingCount, $result.Summary.CriticalCount, $result.Summary.HighCount, $result.Summary.ReviewEvidenceState)
$reports
