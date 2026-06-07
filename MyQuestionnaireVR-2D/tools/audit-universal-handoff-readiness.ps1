param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$CompanionSummaryPath = "",
    [string]$DirectHandoffRoot = "",
    [string]$OutputDir = "",
    [string]$RunId = "",
    [int]$RequiredCleanQuestTrials = 10,
    [switch]$RequireComplete
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "universal-handoff-readiness-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

function Read-JsonIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Get-FirstPropertyValue {
    param(
        [object]$Object,
        [string[]]$Names,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }
    return $Default
}

function Resolve-LatestSummary {
    param(
        [string]$Root,
        [string]$FileName,
        [scriptblock]$Predicate = { param($json) $true }
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Filter $FileName -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    foreach ($candidate in $candidates) {
        $json = Read-JsonIfExists -Path $candidate.FullName
        if ($json -and (& $Predicate $json)) {
            return [ordered]@{
                path = $candidate.FullName
                json = $json
                lastWriteTime = $candidate.LastWriteTime.ToString('o')
            }
        }
    }
    return $null
}

function New-Requirement {
    param(
        [string]$Id,
        [string]$Requirement,
        [string]$Status,
        [string]$EvidencePath = "",
        [string]$Evidence = "",
        [array]$Missing = @()
    )

    return [ordered]@{
        id = $Id
        requirement = $Requirement
        status = $Status
        evidencePath = $EvidencePath
        evidence = $Evidence
        missing = @($Missing)
    }
}

$projectFull = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($DirectHandoffRoot)) {
    $DirectHandoffRoot = Join-Path $projectFull 'artifacts\quest-direct-handoff'
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $projectFull ("artifacts\universal-handoff-readiness\" + $RunId)
}
$outputFull = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null

if ([string]::IsNullOrWhiteSpace($CompanionSummaryPath)) {
    $latestCompanion = Resolve-LatestSummary `
        -Root (Join-Path $projectFull 'artifacts\builder-companion-workflow') `
        -FileName 'builder-companion-workflow-summary.json' `
        -Predicate {
            param($json)
            return $json.endToEndReceipt -and
                [string]$json.endToEndReceipt.status -ne 'partial-skipped-evidence'
        }
    if ($latestCompanion) {
        $CompanionSummaryPath = $latestCompanion.path
        $companion = $latestCompanion.json
    }
}
else {
    $CompanionSummaryPath = [System.IO.Path]::GetFullPath($CompanionSummaryPath)
    $companion = Read-JsonIfExists -Path $CompanionSummaryPath
}

if (-not $companion) {
    throw "No usable builder companion workflow summary found. Pass -CompanionSummaryPath or run validate-builder-companion-workflow.ps1."
}

$receipt = $companion.endToEndReceipt
$checks = $receipt.checks
$artifacts = $receipt.artifacts

$directSummaries = @()
if (Test-Path -LiteralPath $DirectHandoffRoot) {
    $directSummaries = @(
        Get-ChildItem -LiteralPath $DirectHandoffRoot -Recurse -Filter 'quest-direct-handoff-validation-summary.json' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $json = Read-JsonIfExists -Path $_.FullName
                if ($json) {
                    [PSCustomObject]@{
                        path = $_.FullName
                        lastWriteTime = $_.LastWriteTime
                        json = $json
                        dryRun = [bool](Get-FirstPropertyValue -Object $json.decisionGate -Names @('dryRun') -Default $false)
                        passCount = [int](Get-FirstPropertyValue -Object $json -Names @('passCount') -Default 0)
                        blockedCount = [int](Get-FirstPropertyValue -Object $json -Names @('blockedCount') -Default 0)
                        failCount = [int](Get-FirstPropertyValue -Object $json -Names @('failCount') -Default 0)
                        attemptedTrialCount = [int](Get-FirstPropertyValue -Object $json -Names @('attemptedTrialCount') -Default 0)
                        status = [string](Get-FirstPropertyValue -Object $json -Names @('status') -Default '')
                    }
                }
            }
    )
}

$realDirectSummaries = @($directSummaries | Where-Object { -not [bool]$_.dryRun })
$bestRealDirect = @($realDirectSummaries | Sort-Object @{ Expression = { $_.passCount }; Descending = $true }, @{ Expression = { $_.lastWriteTime }; Descending = $true } | Select-Object -First 1)
$latestRealDirect = @($realDirectSummaries | Sort-Object lastWriteTime -Descending | Select-Object -First 1)
$cleanTrialGate = $false
$manualHeadsetPass = $false
$defaultApproved = $false
$manualStatus = 'missing'
$directCandidateStatus = 'missing'
if ($bestRealDirect) {
    $decisionGate = $bestRealDirect.json.decisionGate
    $cleanTrialGate = [bool](Get-FirstPropertyValue -Object $decisionGate -Names @('automatedQuestTrialGatePassed') -Default $false)
    $manualStatus = [string](Get-FirstPropertyValue -Object $decisionGate -Names @('manualHeadsetPassStatus') -Default 'missing')
    $manualHeadsetPass = $manualStatus -eq 'pass'
    $defaultApproved = [bool](Get-FirstPropertyValue -Object $decisionGate -Names @('defaultDirectPendingIntentApproved') -Default $false)
    $directCandidateStatus = [string](Get-FirstPropertyValue -Object $decisionGate -Names @('candidateAStatus') -Default '')
}

$requirements = @()
$requirements += New-Requirement `
    -Id 'hosted-gui-publication' `
    -Requirement 'Hosted website GUI is published, matches the staged/source builder, and exposes the runner controls.' `
    -Status $(if ([bool]$checks.hostedBuilderValidationPass) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "hostedBuilderValidationPass=$($checks.hostedBuilderValidationPass); hostedStatus=$($companion.hostedBuilderValidation.status)"
$requirements += New-Requirement `
    -Id 'local-companion-contract' `
    -Requirement 'The GUI can signal the local companion with pairing-token protection, status/capability checks, and job polling.' `
    -Status $(if ([bool]$checks.companionTokenAuthorization -and [bool]$checks.runnerJobReceiptsInspectable) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "companionTokenAuthorization=$($checks.companionTokenAuthorization); runnerJobReceiptsInspectable=$($checks.runnerJobReceiptsInspectable)"
$requirements += New-Requirement `
    -Id 'apk-generation' `
    -Requirement 'The local companion creates a questionnaire APK and records path, byte count, and SHA-256 evidence.' `
    -Status $(if ([bool]$checks.generateApkHashPass) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "generatedApk=$($artifacts.generatedApk.path); bytes=$($artifacts.generatedApk.bytes); sha256=$($artifacts.generatedApk.sha256)"
$requirements += New-Requirement `
    -Id 'local-render-visual-evidence' `
    -Requirement 'Local renderers produce inspectable questionnaire and temporal tracer PNG evidence before headset evidence.' `
    -Status $(if ([bool]$checks.renderPreviewArtifactGatePass -and [bool]$checks.workflowArtifactPreviewEndpointPass) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "renderPreviewArtifactGatePass=$($checks.renderPreviewArtifactGatePass); workflowArtifactPreviewEndpointPass=$($checks.workflowArtifactPreviewEndpointPass)"
$requirements += New-Requirement `
    -Id 'evidence-bundle' `
    -Requirement 'The local companion can package JSON/log/CSV/PNG evidence into a typed zip bundle.' `
    -Status $(if ([bool]$checks.evidenceBundleEndpointPass) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "evidenceBundleEndpointPass=$($checks.evidenceBundleEndpointPass); entries=$($artifacts.evidenceBundle.entryCount); bytes=$($artifacts.evidenceBundle.bytes)"
$requirements += New-Requirement `
    -Id 'direct-pendingintent-contract-preflight' `
    -Requirement 'Direct XR -> 2D panel -> same XR app PendingIntent contract preflights with the real questionnaire, tracer, and Unity APK package/catalog contract.' `
    -Status $(if ([bool]$checks.directHandoffDryRunContractPass -and [bool]$checks.workflowDirectHandoffClampGatePass) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "directHandoffDryRunContractPass=$($checks.directHandoffDryRunContractPass); workflowDirectHandoffClampGatePass=$($checks.workflowDirectHandoffClampGatePass)"
$requirements += New-Requirement `
    -Id 'one-real-product-path-trial' `
    -Requirement 'At least one real Quest product-path trial has shown Unity -> questionnaire -> Unity video liveness -> tracer -> Unity completion without shell foreground switching after initial launch.' `
    -Status $(if ($bestRealDirect -and $bestRealDirect.passCount -ge 1 -and $bestRealDirect.failCount -eq 0) { 'proven' } else { 'missing' }) `
    -EvidencePath $(if ($bestRealDirect) { [string]$bestRealDirect.path } else { '' }) `
    -Evidence $(if ($bestRealDirect) { "status=$($bestRealDirect.status); passCount=$($bestRealDirect.passCount); failCount=$($bestRealDirect.failCount); candidateAStatus=$directCandidateStatus" } else { 'no real direct handoff summary found' })
$requirements += New-Requirement `
    -Id 'ten-clean-product-path-trials' `
    -Requirement "Direct PendingIntent Candidate A needs $RequiredCleanQuestTrials clean real Quest product-path trials before it can become the default production strategy." `
    -Status $(if ($cleanTrialGate) { 'proven' } else { 'physical-pending' }) `
    -EvidencePath $(if ($bestRealDirect) { [string]$bestRealDirect.path } else { '' }) `
    -Evidence $(if ($bestRealDirect) { "bestPassCount=$($bestRealDirect.passCount); automatedQuestTrialGatePassed=$cleanTrialGate; required=$RequiredCleanQuestTrials" } else { "bestPassCount=0; required=$RequiredCleanQuestTrials" }) `
    -Missing $(if ($cleanTrialGate) { @() } else { @("need-$RequiredCleanQuestTrials-clean-real-product-path-trials") })
$requirements += New-Requirement `
    -Id 'manual-headset-pass' `
    -Requirement 'A human/manual headset pass is required before defaulting direct PendingIntent in production.' `
    -Status $(if ($manualHeadsetPass) { 'proven' } else { 'physical-pending' }) `
    -EvidencePath $(if ($bestRealDirect) { [string]$bestRealDirect.path } else { '' }) `
    -Evidence "manualHeadsetPassStatus=$manualStatus; defaultDirectPendingIntentApproved=$defaultApproved" `
    -Missing $(if ($manualHeadsetPass) { @() } else { @('manual-headset-pass-signoff') })

$failed = @($requirements | Where-Object { $_.status -eq 'missing' -or $_.status -eq 'contradicted' })
$physicalPending = @($requirements | Where-Object { $_.status -eq 'physical-pending' })
$proven = @($requirements | Where-Object { $_.status -eq 'proven' })
$complete = $failed.Count -eq 0 -and $physicalPending.Count -eq 0 -and $cleanTrialGate -and $manualHeadsetPass -and $defaultApproved

$latestPhysicalBlock = $null
if ($latestRealDirect -and [string]$latestRealDirect.status -eq 'blocked') {
    $trialReasons = @()
    if ($latestRealDirect.json.trials) {
        $trialReasons = @($latestRealDirect.json.trials | ForEach-Object {
            if ($_.failureReasons) { $_.failureReasons }
            elseif ($_.blockedReasons) { $_.blockedReasons }
        } | ForEach-Object { $_ } | Select-Object -Unique)
    }
    $latestPhysicalBlock = [ordered]@{
        path = $latestRealDirect.path
        status = $latestRealDirect.status
        blockedCount = $latestRealDirect.blockedCount
        failCount = $latestRealDirect.failCount
        reasons = @($trialReasons)
    }
}

$status = if ($complete) {
    'complete'
}
elseif ($failed.Count -gt 0) {
    'incomplete-missing-evidence'
}
else {
    'pass-with-physical-pending'
}

$summary = [ordered]@{
    schemaVersion = 'mq.universal_handoff_readiness_audit.v1'
    status = $status
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    projectPath = $projectFull
    completionApproved = $complete
    defaultDirectPendingIntentApproved = $defaultApproved
    counts = [ordered]@{
        requirements = $requirements.Count
        proven = $proven.Count
        physicalPending = $physicalPending.Count
        failedOrMissing = $failed.Count
    }
    evidence = [ordered]@{
        companionSummaryPath = $CompanionSummaryPath
        companionReceiptStatus = $receipt.status
        companionOfflineWorkflowReady = [bool]$receipt.offlineWorkflowReady
        bestRealDirectHandoffSummaryPath = if ($bestRealDirect) { $bestRealDirect.path } else { '' }
        bestRealDirectHandoffPassCount = if ($bestRealDirect) { $bestRealDirect.passCount } else { 0 }
        latestRealDirectHandoffSummaryPath = if ($latestRealDirect) { $latestRealDirect.path } else { '' }
        latestRealDirectHandoffStatus = if ($latestRealDirect) { $latestRealDirect.status } else { '' }
        realDirectHandoffSummaryCount = $realDirectSummaries.Count
        latestPhysicalBlock = $latestPhysicalBlock
    }
    requirements = $requirements
    nextPhysicalGates = [ordered]@{
        requiredCleanQuestTrials = $RequiredCleanQuestTrials
        currentBestCleanQuestTrialPassCount = if ($bestRealDirect) { $bestRealDirect.passCount } else { 0 }
        manualHeadsetPassStatus = $manualStatus
        productPathStatus = $receipt.physicalEvidenceStillNeeded.currentProductPathStatus
        productPathBlockedReasons = @($receipt.physicalEvidenceStillNeeded.blockedReasons)
    }
}

$summaryPath = Join-Path $outputFull 'universal-handoff-readiness-audit-summary.json'
$summary | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Universal handoff readiness audit status: $status"
Write-Host "Summary: $summaryPath"
Write-Host "Proven requirements: $($proven.Count)/$($requirements.Count); physical pending: $($physicalPending.Count); failed/missing: $($failed.Count)"

if ($RequireComplete -and -not $complete) {
    throw "Universal handoff workflow is not complete. Status=$status; physicalPending=$($physicalPending.Count); failedOrMissing=$($failed.Count)."
}
if ($failed.Count -gt 0) {
    throw "Universal handoff readiness audit found missing required evidence: $(@($failed | ForEach-Object { $_.id }) -join ', ')"
}
