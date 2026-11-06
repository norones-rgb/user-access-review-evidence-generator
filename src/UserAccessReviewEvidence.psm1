#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-UarUtc {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Field)
    if ($Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$') {
        throw "$Field must be an ISO 8601 UTC timestamp ending in Z (example: 2026-11-05T12:00:00Z)."
    }
    try { return [datetimeoffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
    catch { throw "Invalid UTC timestamp in $Field : $Value" }
}

function Read-UarCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$RequiredColumns)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file not found: $Path" }
    $line = @(Get-Content -LiteralPath $Path -TotalCount 1 -Encoding UTF8)
    if ($line.Count -eq 0 -or [string]::IsNullOrWhiteSpace($line[0])) { throw "CSV has no header: $Path" }
    $columns = @(([string]$line[0]).TrimStart([char]0xFEFF).Split(',') | ForEach-Object { $_.Trim().Trim('"') })
    foreach ($name in $RequiredColumns) {
        if ($columns -cnotcontains $name) { throw "CSV $Path is missing required column: $name" }
    }
    return @(Import-Csv -LiteralPath $Path -Encoding UTF8)
}

function Assert-UarUnique {
    param([object[]]$Rows, [string]$Field, [string]$Dataset)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Rows) {
        $key = [string]$row.$Field
        if ([string]::IsNullOrWhiteSpace($key)) { throw "$Dataset has a blank $Field." }
        if ($key -cne $key.Trim()) { throw "$Dataset has a $Field with surrounding whitespace: $key" }
        if (-not $seen.Add($key)) { throw "$Dataset contains duplicate $Field : $key" }
    }
}

function Assert-UarInput {
    [CmdletBinding()]
    param([object[]]$Identities, [object[]]$Entitlements, [object[]]$Decisions,
          [object[]]$Sources, [object[]]$Baseline, [System.Collections.IDictionary]$Config,
          [datetime]$AsOfUtc)
    foreach ($key in @('ReviewId','ReviewDueUtc','ExpectedApplications','SourceMaxAgeDays','TerminationGraceDays','RevocationGraceDays')) {
        if (-not $Config.Contains($key)) { throw "Configuration is missing $key." }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Config['ReviewId'])) { throw 'ReviewId cannot be blank.' }
    $due = ConvertTo-UarUtc -Value ([string]$Config['ReviewDueUtc']) -Field 'ReviewDueUtc'
    $expectedApps = @($Config['ExpectedApplications'])
    if ($expectedApps.Count -lt 1) { throw 'ExpectedApplications must contain at least one application.' }
    $appSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($app in $expectedApps) {
        if ([string]::IsNullOrWhiteSpace([string]$app) -or -not $appSet.Add(([string]$app).Trim())) {
            throw 'ExpectedApplications must have distinct nonblank values.'
        }
    }
    foreach ($key in @('SourceMaxAgeDays','TerminationGraceDays','RevocationGraceDays')) {
        $n = 0
        if (-not [int]::TryParse([string]$Config[$key], [ref]$n) -or $n -lt 0 -or $n -gt 3650) {
            throw "$key must be an integer from 0 to 3650."
        }
    }
    if ($Identities.Count -lt 1 -or $Sources.Count -lt 1) {
        throw 'Identity records and source manifests cannot be empty; zero-row entitlement exports are allowed only with source evidence.'
    }
    Assert-UarUnique -Rows $Identities -Field 'IdentityId' -Dataset 'identities'
    Assert-UarUnique -Rows $Entitlements -Field 'EntitlementId' -Dataset 'entitlements'
    Assert-UarUnique -Rows $Sources -Field 'Application' -Dataset 'sources'
    Assert-UarUnique -Rows $Baseline -Field 'EntitlementId' -Dataset 'baseline'
    Assert-UarUnique -Rows $Decisions -Field 'EntitlementId' -Dataset 'decisions'
    foreach ($person in $Identities) {
        if ([string]$person.EmploymentStatus -cnotin @('Active','Inactive','Terminated','Leave')) {
            throw "Unsupported EmploymentStatus for $($person.IdentityId)."
        }
        if ($person.EmploymentStatus -eq 'Terminated') {
            if ([string]::IsNullOrWhiteSpace([string]$person.TerminationDateUtc)) {
                throw "Terminated identity $($person.IdentityId) has no TerminationDateUtc."
            }
            $terminatedAt = ConvertTo-UarUtc -Value $person.TerminationDateUtc -Field 'TerminationDateUtc'
            if ($terminatedAt -gt $AsOfUtc) { throw "Future termination date for $($person.IdentityId)." }
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$person.TerminationDateUtc)) {
            [void](ConvertTo-UarUtc -Value $person.TerminationDateUtc -Field 'TerminationDateUtc')
        }
    }
    foreach ($entitlement in $Entitlements) {
        foreach ($key in @('IdentityId','Application','Resource','Privilege','Status','SourceSystem')) {
            if ([string]::IsNullOrWhiteSpace([string]$entitlement.$key)) { throw "Blank $key for entitlement $($entitlement.EntitlementId)." }
        }
        if ([string]$entitlement.Status -cnotin @('Active','Disabled')) { throw "Unknown Status for entitlement $($entitlement.EntitlementId)." }
        if ([string]$entitlement.Privilege -cnotin @('Standard','Privileged')) { throw "Unknown Privilege for entitlement $($entitlement.EntitlementId)." }
        $observed = ConvertTo-UarUtc -Value $entitlement.ObservedAtUtc -Field 'ObservedAtUtc'
        if ($observed -gt $AsOfUtc) { throw "Entitlement $($entitlement.EntitlementId) has future observation time." }
    }
    foreach ($src in $Sources) {
        if ([string]$src.IsComplete -cnotin @('True','False')) { throw "Source $($src.Application) IsComplete must be True or False." }
        $exported = ConvertTo-UarUtc -Value $src.ExportedAtUtc -Field 'ExportedAtUtc'
        if ($exported -gt $AsOfUtc) { throw "Source $($src.Application) has a future export time." }
    }
    foreach ($decision in $Decisions) {
        if ([string]$decision.ReviewId -cne [string]$Config['ReviewId']) { throw "Cross-cycle decision for entitlement $($decision.EntitlementId)." }
        if ([string]$decision.Decision -cnotin @('Approve','Revoke','Exception','Pending')) {
            throw "Unsupported decision for entitlement $($decision.EntitlementId)."
        }
        if ([string]::IsNullOrWhiteSpace([string]$decision.ReviewerId)) { throw "Missing reviewer ID for $($decision.EntitlementId)." }
        $when = ConvertTo-UarUtc -Value $decision.DecisionAtUtc -Field 'DecisionAtUtc'
        if ($when -gt $AsOfUtc) { throw "Decision $($decision.EntitlementId) has future timestamp." }
    }
    $entitlementIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $Entitlements) { [void]$entitlementIds.Add([string]$e.EntitlementId) }
    foreach ($d in $Decisions) {
        if (-not $entitlementIds.Contains([string]$d.EntitlementId)) {
            throw "Decision references unknown entitlement $($d.EntitlementId). Resolve export scope before running."
        }
    }
    return $due
}

function New-UarFinding {
    param([int]$Sequence, [string]$Rule, [string]$Severity, [string]$Category,
          [string]$IdentityId, [string]$EntitlementId, [string]$Application,
          [string]$Description, [string]$Action)
    return [pscustomobject][ordered]@{
        FindingId = ('UAR-{0:d4}' -f $Sequence)
        Rule = $Rule
        Severity = $Severity
        Category = $Category
        IdentityId = $IdentityId
        EntitlementId = $EntitlementId
        Application = $Application
        Description = $Description
        RecommendedAction = $Action
    }
}

function Get-UarFileEvidence {
    param([string]$Path, [string]$Type)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    return [pscustomobject]@{
        InputType = $Type
        FileName = [IO.Path]::GetFileName($Path)
        SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Invoke-UarEvidenceReview {
    <#
    .SYNOPSIS
    Read-only reconciliation of exported identities, entitlements, reviewer decisions, and source manifest.
    .DESCRIPTION
    Reads local files only. Creates findings and provenance; never modifies source records or permissions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdentityCsv,
        [Parameter(Mandatory)][string]$EntitlementCsv,
        [Parameter(Mandatory)][string]$DecisionCsv,
        [Parameter(Mandatory)][string]$SourceCsv,
        [Parameter(Mandatory)][string]$ConfigPath,
        [string]$BaselineCsv,
        [Parameter(Mandatory)][string]$AsOfUtc
    )
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Config not found: $ConfigPath" }
    try { $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable }
    catch { throw "Invalid JSON configuration: $($_.Exception.Message)" }
    if ($null -eq $config -or $config -isnot [System.Collections.IDictionary]) { throw 'Configuration must be a JSON object.' }
    $asOf = ConvertTo-UarUtc -Value $AsOfUtc -Field 'AsOfUtc'
    $identities = @(Read-UarCsv -Path $IdentityCsv -RequiredColumns @('IdentityId','DisplayName','EmploymentStatus','ManagerId','TerminationDateUtc','Department'))
    $entitlements = @(Read-UarCsv -Path $EntitlementCsv -RequiredColumns @('EntitlementId','IdentityId','Application','Resource','Privilege','Status','ObservedAtUtc','SourceSystem'))
    $decisions = @(Read-UarCsv -Path $DecisionCsv -RequiredColumns @('ReviewId','EntitlementId','Decision','ReviewerId','DecisionAtUtc','TicketId','Note'))
    $sources = @(Read-UarCsv -Path $SourceCsv -RequiredColumns @('Application','ExportedAtUtc','IsComplete','CoverageNote'))
    $baseline = @()
    if (-not [string]::IsNullOrWhiteSpace($BaselineCsv)) {
        $baseline = @(Read-UarCsv -Path $BaselineCsv -RequiredColumns @('EntitlementId','IdentityId','Application','Resource','Privilege'))
    }
    $due = Assert-UarInput -Identities $identities -Entitlements $entitlements -Decisions $decisions -Sources $sources -Baseline $baseline -Config $config -AsOfUtc $asOf
    $identityIndex = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $decisionIndex = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $sourceIndex = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $baselineIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $baselineIndex = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $currentIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $identities) { $identityIndex.Add([string]$p.IdentityId, $p) }
    foreach ($d in $decisions) { $decisionIndex.Add([string]$d.EntitlementId, $d) }
    foreach ($s in $sources) { $sourceIndex.Add([string]$s.Application, $s) }
    foreach ($b in $baseline) {
        [void]$baselineIds.Add([string]$b.EntitlementId)
        $baselineIndex.Add([string]$b.EntitlementId, $b)
    }
    foreach ($e in $entitlements) { [void]$currentIds.Add([string]$e.EntitlementId) }

    $findings = [Collections.Generic.List[object]]::new()
    $evidence = [Collections.Generic.List[object]]::new()
    $seq = 0
    $sourceIssues = 0
    $maxAge = [int]$config['SourceMaxAgeDays']
    foreach ($app in @($config['ExpectedApplications']) | Sort-Object) {
        $src = $null
        if (-not $sourceIndex.TryGetValue([string]$app, [ref]$src)) {
            $seq++; $sourceIssues++
            [void]$findings.Add((New-UarFinding $seq 'SOURCE_EXPORT_MISSING' 'High' 'EvidenceGap' '' '' ([string]$app) 'No source manifest exists for a required application.' 'Obtain and validate an application export before concluding its access is reviewed.'))
            continue
        }
        if ($src.IsComplete -eq 'False') {
            $seq++; $sourceIssues++
            [void]$findings.Add((New-UarFinding $seq 'SOURCE_EXPORT_INCOMPLETE' 'High' 'EvidenceGap' '' '' ([string]$app) 'Source owner marked the export incomplete.' 'Resolve source scope and provide a complete authoritative export.'))
        }
        $srcAt = ConvertTo-UarUtc -Value $src.ExportedAtUtc -Field 'ExportedAtUtc'
        if (($asOf - $srcAt).TotalDays -gt $maxAge) {
            $seq++; $sourceIssues++
            [void]$findings.Add((New-UarFinding $seq 'SOURCE_EXPORT_STALE' 'High' 'EvidenceGap' '' '' ([string]$app) "Source export older than $maxAge days." 'Refresh the source export and rerun reconciliation.'))
        }
    }
    $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($app in @($config['ExpectedApplications'])) { [void]$expectedSet.Add([string]$app) }
    $missingCount = 0
    $pendingCount = 0
    $activeCount = 0
    foreach ($ent in @($entitlements | Sort-Object -Property EntitlementId)) {
        $identity = $null; $decision = $null; $src = $null
        $knownIdentity = $identityIndex.TryGetValue([string]$ent.IdentityId,[ref]$identity)
        $hasDecision = $decisionIndex.TryGetValue([string]$ent.EntitlementId,[ref]$decision)
        $hasSource = $sourceIndex.TryGetValue([string]$ent.Application,[ref]$src)
        $isActive = ([string]$ent.Status -eq 'Active')
        $isPrivileged = ([string]$ent.Privilege -eq 'Privileged')
        $decisionText = if ($hasDecision) { [string]$decision.Decision } else { 'Missing' }
        if ($isActive) { $activeCount++ }
        if (-not $hasDecision) { $missingCount++ }
        elseif ($decisionText -eq 'Pending') { $pendingCount++ }
        $inBaseline = if ([string]::IsNullOrWhiteSpace($BaselineCsv)) { 'Unknown' } elseif ($baselineIds.Contains([string]$ent.EntitlementId)) { 'Yes' } else { 'No' }
        $sourceReliable = ($expectedSet.Contains([string]$ent.Application) -and $hasSource -and $src.IsComplete -eq 'True' -and (($asOf - (ConvertTo-UarUtc -Value $src.ExportedAtUtc -Field 'ExportedAtUtc')).TotalDays -le $maxAge))
        [void]$evidence.Add([pscustomobject][ordered]@{
            EntitlementId = [string]$ent.EntitlementId
            IdentityId = [string]$ent.IdentityId
            Application = [string]$ent.Application
            Resource = [string]$ent.Resource
            Privilege = [string]$ent.Privilege
            AccessStatus = [string]$ent.Status
            SourceSystem = [string]$ent.SourceSystem
            SourceObservedAtUtc = [string]$ent.ObservedAtUtc
            SourceEvidenceCurrentAndComplete = [bool]$sourceReliable
            Decision = $decisionText
            ReviewerId = if ($hasDecision) { [string]$decision.ReviewerId } else { '' }
            DecisionAtUtc = if ($hasDecision) { [string]$decision.DecisionAtUtc } else { '' }
            TicketId = if ($hasDecision) { [string]$decision.TicketId } else { '' }
            InBaseline = $inBaseline
        })
        if (-not $expectedSet.Contains([string]$ent.Application) -or -not $hasSource) {
            $seq++; $sourceIssues++
            [void]$findings.Add((New-UarFinding $seq 'ENTITLEMENT_SOURCE_UNVERIFIED' 'High' 'EvidenceGap' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Application entitlement lacks a configured and evidenced source.' 'Align entitlement export, expected application scope and source manifest.'))
        }
        if (-not $knownIdentity) {
            $seq++
            [void]$findings.Add((New-UarFinding $seq 'IDENTITY_NOT_IN_HR_EXPORT' 'High' 'EvidenceGap' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Entitlement has no matching identity in the HR export; identity status is unknown.' 'Investigate identity correlation; do not infer that the account is unauthorized or terminated.'))
        }
        elseif ($isActive -and $identity.EmploymentStatus -eq 'Terminated') {
            $terminatedAt = ConvertTo-UarUtc -Value $identity.TerminationDateUtc -Field 'TerminationDateUtc'
            if (($asOf - $terminatedAt).TotalDays -ge [int]$config['TerminationGraceDays']) {
                $seq++
                [void]$findings.Add((New-UarFinding $seq 'TERMINATED_IDENTITY_ACTIVE_ACCESS' 'Critical' 'RiskFinding' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'HR reports termination beyond the configured grace period while source access remains active.' 'Escalate for approved offboarding remediation and verify source entitlement state.'))
            } else {
                $seq++
                [void]$findings.Add((New-UarFinding $seq 'TERMINATION_WITHIN_GRACE' 'Medium' 'RiskFinding' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'HR reports recent termination; active access is still within the configured grace period.' 'Verify scheduled deprovisioning and follow up at grace-period expiry.'))
            }
        }
        elseif ($isActive -and $identity.EmploymentStatus -eq 'Inactive') {
            $seq++
            [void]$findings.Add((New-UarFinding $seq 'INACTIVE_IDENTITY_ACTIVE_ACCESS' 'High' 'RiskFinding' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Inactive HR identity retains an active entitlement.' 'Review access with identity owner and investigate expected state.'))
        }
        if ($isActive -and $isPrivileged -and ($decisionText -eq 'Missing' -or $decisionText -eq 'Pending')) {
            $seq++
            [void]$findings.Add((New-UarFinding $seq 'PRIVILEGED_ACCESS_UNREVIEWED' 'High' 'RiskFinding' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Active privileged access lacks a final reviewer decision.' 'Request authorized review; do not auto-approve.'))
        }
        if ($decisionText -eq 'Missing' -or $decisionText -eq 'Pending') {
            if ($asOf -gt $due) {
                $seq++
                [void]$findings.Add((New-UarFinding $seq 'REVIEW_DECISION_OVERDUE' 'High' 'RiskFinding' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Entitlement has no final reviewer decision after the review due date.' 'Route to designated reviewer and track completion evidence.'))
            }
        }
        if ($isActive -and $decisionText -eq 'Revoke') {
            $decisionAt = ConvertTo-UarUtc -Value $decision.DecisionAtUtc -Field 'DecisionAtUtc'
            $pastGrace = (($asOf - $decisionAt).TotalDays -ge [int]$config['RevocationGraceDays'])
            $seq++
            $rule = if ($pastGrace) { 'REVOKE_DECISION_ACCESS_ACTIVE' } else { 'REVOKE_REMEDIATION_IN_GRACE' }
            $severity = if ($pastGrace) { 'Critical' } else { 'Medium' }
            [void]$findings.Add((New-UarFinding $seq $rule $severity 'RiskFinding' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'A revoke decision exists, but the export still reports active access.' 'Validate ticket status and source state; follow authorized revocation workflow.'))
        }
        if ($decisionText -eq 'Exception' -and [string]::IsNullOrWhiteSpace([string]$decision.TicketId)) {
            $seq++
            [void]$findings.Add((New-UarFinding $seq 'EXCEPTION_WITHOUT_REFERENCE' 'High' 'EvidenceGap' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Exception decision has no tracked exception or approval reference.' 'Record exception justification, approver, owner and expiration in the control system.'))
        }
        if ($inBaseline -eq 'Yes') {
            $prev = $null
            [void]$baselineIndex.TryGetValue([string]$ent.EntitlementId, [ref]$prev)
            if ($prev -and ($prev.IdentityId -cne $ent.IdentityId -or $prev.Application -cne $ent.Application -or $prev.Resource -cne $ent.Resource -or $prev.Privilege -cne $ent.Privilege)) {
                $seq++
                $changeSeverity = if ($isPrivileged) { 'High' } else { 'Medium' }
                [void]$findings.Add((New-UarFinding $seq 'BASELINE_ENTITLEMENT_CHANGED' $changeSeverity 'ChangeIndicator' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Entitlement identity, application, resource, or privilege differs from prior baseline.' 'Review the grant, assignment and normalization history; do not assume the difference is authorized.'))
            }
        }
        if ($isActive -and $isPrivileged -and $knownIdentity -and [string]::IsNullOrWhiteSpace([string]$identity.ManagerId)) {
            $seq++
            [void]$findings.Add((New-UarFinding $seq 'PRIVILEGED_ACCESS_MISSING_MANAGER' 'Medium' 'EvidenceGap' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'The HR identity record has no manager for privileged access owner validation.' 'Verify accountable owner and independent reviewer.'))
        }
        if ($inBaseline -eq 'No' -and $isActive) {
            $seq++
            $severity = if ($isPrivileged) { 'Medium' } else { 'Low' }
            [void]$findings.Add((New-UarFinding $seq 'NEW_ACCESS_SINCE_BASELINE' $severity 'ChangeIndicator' ([string]$ent.IdentityId) ([string]$ent.EntitlementId) ([string]$ent.Application) 'Active entitlement does not appear in the prior baseline export; this is not by itself proof of inappropriate access.' 'Verify new grant against change/request history and the expected access model.'))
        }
    }
    foreach ($old in @($baseline | Sort-Object -Property EntitlementId)) {
        if (-not $currentIds.Contains([string]$old.EntitlementId)) {
            $seq++
            [void]$findings.Add((New-UarFinding $seq 'BASELINE_ENTITLEMENT_NOT_IN_CURRENT_EXPORT' 'Medium' 'EvidenceGap' ([string]$old.IdentityId) ([string]$old.EntitlementId) ([string]$old.Application) 'Prior baseline entitlement is absent from current export; removal is not verified.' 'Verify authoritative source state and export completeness before claiming access was removed.'))
        }
    }
    $sourceEvidenceState = if ($sourceIssues -gt 0) { 'Incomplete' } else { 'CurrentAndCompletePerManifest' }
    $evidenceGapCount = @($findings | Where-Object Category -eq 'EvidenceGap').Count
    $revocationGapCount = @($findings | Where-Object { $_.Rule -in @('REVOKE_DECISION_ACCESS_ACTIVE','REVOKE_REMEDIATION_IN_GRACE') }).Count
    $reviewEvidenceState = if (($missingCount + $pendingCount + $evidenceGapCount + $revocationGapCount) -gt 0) { 'Incomplete' } else { 'Recorded' }
    $summary = [pscustomobject][ordered]@{
        ReviewId = [string]$config['ReviewId']
        AsOfUtc = $asOf.ToString('yyyy-MM-ddTHH:mm:ssZ')
        ReviewDueUtc = $due.ToString('yyyy-MM-ddTHH:mm:ssZ')
        IdentityCount = $identities.Count
        EntitlementCount = $entitlements.Count
        ActiveEntitlementCount = $activeCount
        DecisionCount = $decisions.Count
        MissingDecisionCount = $missingCount
        PendingDecisionCount = $pendingCount
        SourceEvidenceState = $sourceEvidenceState
        ReviewEvidenceState = $reviewEvidenceState
        FindingCount = $findings.Count
        CriticalCount = @($findings | Where-Object Severity -eq 'Critical').Count
        HighCount = @($findings | Where-Object Severity -eq 'High').Count
        MediumCount = @($findings | Where-Object Severity -eq 'Medium').Count
        LowCount = @($findings | Where-Object Severity -eq 'Low').Count
    }
    $inputs = [Collections.Generic.List[object]]::new()
    foreach ($entry in @(@('Identity',$IdentityCsv),@('Entitlements',$EntitlementCsv),@('Decisions',$DecisionCsv),@('SourceManifest',$SourceCsv),@('Config',$ConfigPath))) {
        [void]$inputs.Add((Get-UarFileEvidence -Type $entry[0] -Path $entry[1]))
    }
    if (-not [string]::IsNullOrWhiteSpace($BaselineCsv)) { [void]$inputs.Add((Get-UarFileEvidence -Type 'Baseline' -Path $BaselineCsv)) }
    return [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        Summary = $summary
        InputEvidence = @($inputs.ToArray())
        Findings = @($findings.ToArray())
        EntitlementEvidence = @($evidence.ToArray())
        Warnings = @('Recorded approvals are unverified reviewer assertions; this tool cannot establish entitlement appropriateness, source completeness, or closure of revocation tickets independently.', 'HR and application CSV exports must be access-controlled and verified against authoritative source systems.')
    }
}

function Protect-UarCsvCell {
    param([AllowNull()][object]$Value)
    $s = [string]$Value
    if ($s -match '^\s*[=+@\-\t\r\n]') { return "'" + $s }
    return $s
}

function ConvertTo-UarSafeCsvObject {
    param([Parameter(Mandatory)][object]$Object)
    $row = [ordered]@{}
    foreach ($p in $Object.PSObject.Properties) { $row[$p.Name] = Protect-UarCsvCell -Value $p.Value }
    return [pscustomobject]$row
}

function Export-UarEvidenceReports {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Result, [Parameter(Mandatory)][string]$OutputDirectory)
    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
    $csv = Join-Path $OutputDirectory 'uar-findings.csv'
    $evidenceCsv = Join-Path $OutputDirectory 'uar-entitlement-evidence.csv'
    $json = Join-Path $OutputDirectory 'uar-evidence.json'
    $html = Join-Path $OutputDirectory 'uar-dashboard.html'
    $findingColumns = @('FindingId','Rule','Severity','Category','IdentityId','EntitlementId','Application','Description','RecommendedAction')
    $evidenceColumns = @('EntitlementId','IdentityId','Application','Resource','Privilege','AccessStatus','SourceSystem','SourceObservedAtUtc','SourceEvidenceCurrentAndComplete','Decision','ReviewerId','DecisionAtUtc','TicketId','InBaseline')
    if (@($Result.Findings).Count -gt 0) {
        $Result.Findings | ForEach-Object { ConvertTo-UarSafeCsvObject $_ } | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8
    } else { Set-Content -LiteralPath $csv -Value ($findingColumns -join ',') -Encoding utf8 }
    if (@($Result.EntitlementEvidence).Count -gt 0) {
        $Result.EntitlementEvidence | ForEach-Object { ConvertTo-UarSafeCsvObject $_ } | Export-Csv -LiteralPath $evidenceCsv -NoTypeInformation -Encoding utf8
    } else { Set-Content -LiteralPath $evidenceCsv -Value ($evidenceColumns -join ',') -Encoding utf8 }
    $Result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $json -Encoding utf8
    $esc = { param([object]$v) [System.Net.WebUtility]::HtmlEncode([string]$v) }
    $rowMarkup = [Collections.Generic.List[string]]::new()
    foreach ($finding in @($Result.Findings)) {
        $cells = @($finding.FindingId,$finding.Severity,$finding.Rule,$finding.IdentityId,$finding.EntitlementId,$finding.Application,$finding.Description,$finding.RecommendedAction)
        [void]$rowMarkup.Add('<tr>' + (($cells | ForEach-Object { '<td>' + (& $esc $_) + '</td>' }) -join '') + '</tr>')
    }
    if ($rowMarkup.Count -eq 0) { [void]$rowMarkup.Add('<tr><td colspan="8">No rule findings for this input set. This does not certify access.</td></tr>') }
    $s = $Result.Summary
    $cards = @(
        [pscustomobject]@{ Label='Entitlements'; Value=$s.EntitlementCount }
        [pscustomobject]@{ Label='Active'; Value=$s.ActiveEntitlementCount }
        [pscustomobject]@{ Label='Missing decisions'; Value=$s.MissingDecisionCount }
        [pscustomobject]@{ Label='Pending decisions'; Value=$s.PendingDecisionCount }
        [pscustomobject]@{ Label='Critical'; Value=$s.CriticalCount }
        [pscustomobject]@{ Label='High'; Value=$s.HighCount }
        [pscustomobject]@{ Label='Medium'; Value=$s.MediumCount }
        [pscustomobject]@{ Label='Low'; Value=$s.LowCount }
    )
    $cardMarkup = ($cards | ForEach-Object { '<div class="metric"><span>' + (& $esc $_.Label) + '</span><strong>' + (& $esc $_.Value) + '</strong></div>' }) -join "`n"
    $markup = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; script-src 'none'; base-uri 'none'; form-action 'none'">
<title>UAR Evidence Dashboard</title>
<style>
:root{color-scheme:light;font-family:system-ui,-apple-system,'Segoe UI',sans-serif;color:#202d35;background:#f4f6f8}
body{margin:0;padding:36px;max-width:1440px;margin-inline:auto}h1{font-size:29px;margin:0 0 7px}h2{font-size:18px;margin:30px 0 14px}
p{color:#52606d;line-height:1.55}.eyebrow{letter-spacing:.15em;font-weight:700;color:#536c76;font-size:12px;text-transform:uppercase}
.summary{background:white;border:1px solid #dce3e8;padding:22px;border-radius:12px}.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin:22px 0}
.metric{padding:16px;background:#fff;border:1px solid #dce3e8;border-radius:10px}.metric span{display:block;font-size:12px;color:#576570}.metric strong{display:block;font-size:27px;margin-top:8px}
.tablewrap{background:#fff;border:1px solid #dce3e8;border-radius:12px;overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px;text-align:left}
th,td{border-bottom:1px solid #e8edf0;padding:11px;vertical-align:top;min-width:70px;overflow-wrap:anywhere}th{background:#eaf0f3;white-space:nowrap}
.warning{border-left:4px solid #ad6a27;background:#fff8e9;padding:14px 18px;border-radius:5px;color:#5a451d}
footer{font-size:12px;color:#64717a;margin:26px 0}
</style></head>
<body><div class="eyebrow">ISGIN / IAM audit automation · Offline evidence</div><h1>User Access Review Evidence</h1>
<p>Read-only comparison of HR identities, entitlement exports and recorded reviewer decisions. All displayed data is local to this report.</p>
<section class="summary"><strong>Review:</strong> $(& $esc $s.ReviewId) &nbsp; <strong>As of:</strong> $(& $esc $s.AsOfUtc) &nbsp; <strong>Due:</strong> $(& $esc $s.ReviewDueUtc)<br>
<strong>Source evidence:</strong> $(& $esc $s.SourceEvidenceState) &nbsp; <strong>Recorded review evidence:</strong> $(& $esc $s.ReviewEvidenceState)</section>
<div class="metrics">$cardMarkup</div>
<div class="warning"><strong>Not a certification.</strong> An approval row does not independently verify authorizations. Incomplete or stale exports, missing identities, and pending decisions must be investigated. No access was changed.</div>
<h2>Findings ($(& $esc $s.FindingCount))</h2><div class="tablewrap"><table><thead><tr><th>ID</th><th>Severity</th><th>Rule</th><th>Identity</th><th>Entitlement</th><th>Application</th><th>Explanation</th><th>Recommended action</th></tr></thead>
<tbody>$($rowMarkup -join "`n")</tbody></table></div>
<footer>Generated from export files only. CSV/JSON contain more evidence detail. Protect report files according to your organization's handling policy.</footer></body></html>
"@
    Set-Content -LiteralPath $html -Value $markup -Encoding utf8
    return [pscustomobject]@{ FindingsCsv = $csv; EvidenceCsv = $evidenceCsv; Json = $json; Html = $html }
}

Export-ModuleMember -Function Invoke-UarEvidenceReview, Export-UarEvidenceReports
