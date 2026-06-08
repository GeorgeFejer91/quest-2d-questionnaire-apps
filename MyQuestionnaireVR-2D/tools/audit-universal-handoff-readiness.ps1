param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$CompanionSummaryPath = "",
    [string]$DirectHandoffRoot = "",
    [string]$ManualSignoffRoot = "",
    [string]$BuilderToQuestRoot = "",
    [string]$TwoDFirstLauncherRoot = "",
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
        missing = @($Missing | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
}

function Get-FileEvidence {
    param([string]$Path)

    $evidence = [ordered]@{
        path = $Path
        exists = $false
        bytes = 0
        sha256 = ''
    }
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        $item = Get-Item -LiteralPath $Path
        if (-not $item.PSIsContainer) {
            $evidence.exists = $true
            $evidence.bytes = [int64]$item.Length
            $evidence.sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
        }
    }
    return $evidence
}

function Test-BundleEntrySuffix {
    param(
        [array]$Entries,
        [string]$Suffix
    )

    if ([string]::IsNullOrWhiteSpace($Suffix)) {
        return $false
    }
    $normalizedSuffix = $Suffix.Replace('\', '/')
    return @($Entries | Where-Object {
        $entryName = ([string]$_).Replace('\', '/')
        $entryName -eq $normalizedSuffix -or $entryName.EndsWith("/$normalizedSuffix", [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0
}

$projectFull = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($DirectHandoffRoot)) {
    $DirectHandoffRoot = Join-Path $projectFull 'artifacts\quest-direct-handoff'
}
if ([string]::IsNullOrWhiteSpace($ManualSignoffRoot)) {
    $ManualSignoffRoot = Join-Path $projectFull 'artifacts\direct-handoff-manual-signoff'
}
if ([string]::IsNullOrWhiteSpace($BuilderToQuestRoot)) {
    $BuilderToQuestRoot = Join-Path $projectFull 'artifacts\builder-to-quest-workflow'
}
if ([string]::IsNullOrWhiteSpace($TwoDFirstLauncherRoot)) {
    $TwoDFirstLauncherRoot = Join-Path $projectFull 'artifacts\quest-2d-first-launcher'
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
$physicalGatePacketResult = Get-FirstPropertyValue -Object $companion -Names @('physicalGatePacket') -Default $null
$physicalGatePacketSummaryPath = [string](Get-FirstPropertyValue -Object $artifacts -Names @('physicalGatePacketSummaryPath') -Default '')
$physicalGatePacketEvidenceBundlePath = [string](Get-FirstPropertyValue -Object $artifacts -Names @('physicalGatePacketEvidenceBundlePath') -Default '')
$physicalGatePacketEvidenceBundle = Get-FirstPropertyValue -Object $physicalGatePacketResult -Names @('evidenceBundle') -Default $null
$physicalGatePacketBundleEntryNames = @(Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('entryNames') -Default @() | ForEach-Object { [string]$_ })
$physicalGatePacketRequiredBundleEntries = @(
    'universal-handoff-physical-gate-packet-summary.json',
    'universal-handoff-readiness-audit-summary.json',
    'physical-gate-runbook.txt',
    'operator-signoff-template.json',
    'direct-handoff-manual-signoff-summary.json'
)
$physicalGatePacketMissingBundleEntries = @($physicalGatePacketRequiredBundleEntries | Where-Object {
    -not (Test-BundleEntrySuffix -Entries $physicalGatePacketBundleEntryNames -Suffix $_)
})
$physicalGatePacketBundleEvidenceAvailable = (
    [bool](Get-FirstPropertyValue -Object $checks -Names @('physicalGatePacketPass') -Default $false) -or
    -not [string]::IsNullOrWhiteSpace($physicalGatePacketSummaryPath) -or
    $physicalGatePacketBundleEntryNames.Count -gt 0
)
$physicalGatePacketBundlePass = (
    [bool](Get-FirstPropertyValue -Object $checks -Names @('physicalGatePacketBundlePass') -Default $false) -and
    [bool](Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('exists') -Default $false) -and
    [bool](Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('validZip') -Default $false) -and
    [bool](Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('hasManifest') -Default $false) -and
    $physicalGatePacketMissingBundleEntries.Count -eq 0
)
$evidenceBundleRequirementPass = (
    [bool]$checks.evidenceBundleEndpointPass -and
    (-not $physicalGatePacketBundleEvidenceAvailable -or $physicalGatePacketBundlePass)
)
$directHandoffDryRunSummaryPath = [string](Get-FirstPropertyValue -Object $companion.directHandoffDryRun -Names @('summaryPath') -Default '')
$directHandoffDryRunSummary = Read-JsonIfExists -Path $directHandoffDryRunSummaryPath
$demoUnityApkPath = [string](Get-FirstPropertyValue -Object $companion.directHandoffDryRun -Names @('unityApk') -Default '')
$demoUnityApkEvidence = Get-FileEvidence -Path $demoUnityApkPath
$exampleCatalogPath = Join-Path (Split-Path -Parent $projectFull) 'example-scenario-apk\questionnaire-trigger-catalog.json'
if (-not (Test-Path -LiteralPath $exampleCatalogPath)) {
    $exampleCatalogPath = Join-Path $projectFull '..\example-scenario-apk\questionnaire-trigger-catalog.json'
}
$exampleCatalogPath = [System.IO.Path]::GetFullPath($exampleCatalogPath)
$exampleCatalog = Read-JsonIfExists -Path $exampleCatalogPath
$exampleTriggers = if ($exampleCatalog -and $exampleCatalog.triggers) { @($exampleCatalog.triggers) } else { @() }
$exampleTriggerIds = @($exampleTriggers | ForEach-Object { [string]$_.triggerId })
$exampleRecommendedModes = @{}
foreach ($trigger in $exampleTriggers) {
    $exampleRecommendedModes[[string]$trigger.triggerId] = [string]$trigger.recommendedMode
}
$preflight = if ($directHandoffDryRunSummary) { $directHandoffDryRunSummary.preflight } else { $null }
$unityEmbeddedCatalog = if ($preflight) { $preflight.unityEmbeddedTriggerCatalog } else { $null }
$unityEmbeddedTriggerCount = [int](Get-FirstPropertyValue -Object $unityEmbeddedCatalog -Names @('triggerCount') -Default 0)
$demoUnityCatalogPass = (
    $exampleCatalog -and
    [string]$exampleCatalog.schemaVersion -eq 'mq.quest_questionnaire_trigger_catalog.v1' -and
    [string]$exampleCatalog.package -eq 'org.questquestionnaire.stimulusdemo' -and
    [string]$exampleCatalog.activity -eq 'org.questquestionnaire.stimulusdemo.StimulusUnityPlayerGameActivity' -and
    $exampleTriggerIds -contains 'trigger_1_launch_questionnaire' -and
    $exampleTriggerIds -contains 'trigger_2_video_complete' -and
    $exampleRecommendedModes['trigger_1_launch_questionnaire'] -eq 'demographics' -and
    $exampleRecommendedModes['trigger_2_video_complete'] -eq 'temporalTracer' -and
    [bool]$demoUnityApkEvidence.exists -and
    [int64]$demoUnityApkEvidence.bytes -gt 0 -and
    $preflight -and
    [string]$preflight.status -eq 'pass' -and
    $preflight.apkInfo -and
    $preflight.apkInfo.unity -and
    [string]$preflight.apkInfo.unity.package -eq [string]$exampleCatalog.package -and
    [string]$preflight.apkInfo.unity.activity -eq [string]$exampleCatalog.activity -and
    $unityEmbeddedCatalog -and
    [string]$unityEmbeddedCatalog.parseStatus -eq 'pass' -and
    $unityEmbeddedTriggerCount -ge 2
)

$latestTwoDFirstWorkflow = Resolve-LatestSummary `
    -Root $BuilderToQuestRoot `
    -FileName 'builder-to-quest-workflow-summary.json' `
    -Predicate {
        param($json)
        if ([string]$json.schemaVersion -ne 'mq.builder_to_quest.workflow_validation.v1') {
            return $false
        }
        $configPath = [string]$json.configPath
        $config = Read-JsonIfExists -Path $configPath
        return $config -and
            $config.chainDefaults -and
            [string]$config.chainDefaults.startMode -eq 'questionnaireFirst'
    }
$twoDFirstWorkflow = if ($latestTwoDFirstWorkflow) { $latestTwoDFirstWorkflow.json } else { $null }
$twoDFirstConfig = if ($twoDFirstWorkflow) { Read-JsonIfExists -Path ([string]$twoDFirstWorkflow.configPath) } else { $null }
$twoDFirstApkPath = if ($twoDFirstWorkflow -and $twoDFirstWorkflow.evidence -and $twoDFirstWorkflow.evidence.questionnaireApk) {
    [string]$twoDFirstWorkflow.evidence.questionnaireApk.path
} else {
    ''
}
$twoDFirstApkEvidence = Get-FileEvidence -Path $twoDFirstApkPath
$twoDFirstRender = if ($twoDFirstWorkflow -and $twoDFirstWorkflow.evidence) { $twoDFirstWorkflow.evidence.questionnaireRender } else { $null }
$twoDFirstDirectPreflight = if ($twoDFirstWorkflow -and $twoDFirstWorkflow.evidence) { $twoDFirstWorkflow.evidence.directHandoffPreflight } else { $null }
$twoDFirstCounts = if ($twoDFirstWorkflow -and $twoDFirstWorkflow.counts) { $twoDFirstWorkflow.counts } else { $null }
$twoDFirstNonPass = if ($twoDFirstWorkflow -and $twoDFirstWorkflow.requirements) {
    @($twoDFirstWorkflow.requirements | Where-Object { $_.status -ne 'pass' -and $_.status -ne 'not-applicable' })
} else {
    @()
}
$twoDFirstNonPass = @($twoDFirstNonPass)
$twoDFirstOnlyPhysicalWarning = (
    $twoDFirstNonPass.Count -eq 1 -and
    [string]($twoDFirstNonPass[0].id) -eq 'direct-pendingintent-quest-trials' -and
    [string]($twoDFirstNonPass[0].status) -eq 'warn'
)
$twoDFirstNoRemainingWorkflowIssue = ($twoDFirstNonPass.Count -eq 0 -or $twoDFirstOnlyPhysicalWarning)
$twoDFirstConfigPass = $false
if ($twoDFirstConfig -and $twoDFirstConfig.chainDefaults) {
    $twoDFirstConfigPass = (
        [string]$twoDFirstConfig.chainDefaults.startMode -eq 'questionnaireFirst' -and
        [string]$twoDFirstConfig.chainDefaults.finishBehavior -eq 'openNext' -and
        [string]$twoDFirstConfig.chainDefaults.questionnaireMode -eq 'demographics' -and
        [string]$twoDFirstConfig.chainDefaults.triggerId -eq 'trigger_1_launch_questionnaire' -and
        -not [string]::IsNullOrWhiteSpace([string]$twoDFirstConfig.chainDefaults.nextPackage)
    )
}
$twoDFirstStatusPass = ($twoDFirstWorkflow -and (@('pass', 'warn') -contains [string]$twoDFirstWorkflow.status))
$twoDFirstCountsPass = ($twoDFirstCounts -and [int]$twoDFirstCounts.failed -eq 0 -and [int]$twoDFirstCounts.blocked -eq 0 -and [int]$twoDFirstCounts.pending -eq 0)
$twoDFirstApkPass = ([bool]$twoDFirstApkEvidence.exists -and [int64]$twoDFirstApkEvidence.bytes -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$twoDFirstApkEvidence.sha256))
$twoDFirstRenderPass = ($twoDFirstRender -and [bool]$twoDFirstRender.passesArtifactGate)
$twoDFirstPreflightPass = (
    $twoDFirstDirectPreflight -and
    [string]$twoDFirstDirectPreflight.status -eq 'pass' -and
    [string]$twoDFirstDirectPreflight.preflightStatus -eq 'pass' -and
    [int](Get-FirstPropertyValue -Object $twoDFirstDirectPreflight -Names @('triggerCount') -Default 0) -ge 2
)
$twoDFirstWorkflowPass = (
    $twoDFirstStatusPass -and
    $twoDFirstCountsPass -and
    $twoDFirstNoRemainingWorkflowIssue -and
    $twoDFirstApkPass -and
    $twoDFirstRenderPass -and
    $twoDFirstPreflightPass
)
$twoDFirstPass = $twoDFirstConfigPass -and $twoDFirstWorkflowPass

$latestUnityInputModalityWorkflow = Resolve-LatestSummary `
    -Root $BuilderToQuestRoot `
    -FileName 'builder-to-quest-workflow-summary.json' `
    -Predicate {
        param($json)
        return [string]$json.schemaVersion -eq 'mq.builder_to_quest.workflow_validation.v1' -and
            $json.evidence -and
            $json.evidence.unityInputModality -and
            [string]$json.evidence.unityInputModality.status -eq 'pass'
    }
$unityInputModality = if ($latestUnityInputModalityWorkflow -and $latestUnityInputModalityWorkflow.json.evidence) {
    $latestUnityInputModalityWorkflow.json.evidence.unityInputModality
} else {
    $null
}
$unityInputModalitySourceFacts = if ($unityInputModality) { Get-FirstPropertyValue -Object $unityInputModality -Names @('source') -Default $null } else { $null }
$unityInputModalityApkFacts = if ($unityInputModality) { Get-FirstPropertyValue -Object $unityInputModality -Names @('apk') -Default $null } else { $null }
$unityInputModalityReceiptPass = [bool](Get-FirstPropertyValue -Object $checks -Names @('workflowUnityInputModalityPass') -Default $false)
$unityInputModalityPass = (
    $unityInputModalityReceiptPass -or
    ($unityInputModality -and [string]$unityInputModality.status -eq 'pass')
)

$twoDFirstLauncherSummaries = @()
if (Test-Path -LiteralPath $TwoDFirstLauncherRoot) {
    $twoDFirstLauncherSummaries = @(
        Get-ChildItem -LiteralPath $TwoDFirstLauncherRoot -Recurse -Filter 'quest-2d-first-launcher-validation-summary.json' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $json = Read-JsonIfExists -Path $_.FullName
                if ($json -and [string]$json.schemaVersion -eq 'mq.quest_2d_first_launcher_validation.v1') {
                    [PSCustomObject]@{
                        path = $_.FullName
                        lastWriteTime = $_.LastWriteTime
                        json = $json
                        dryRun = [bool](Get-FirstPropertyValue -Object $json -Names @('dryRun') -Default $false)
                        status = [string](Get-FirstPropertyValue -Object $json -Names @('status') -Default '')
                        preflightStatus = [string](Get-FirstPropertyValue -Object $json.decisionGate -Names @('preflightStatus') -Default '')
                        passCount = [int](Get-FirstPropertyValue -Object $json -Names @('passCount') -Default 0)
                        blockedCount = [int](Get-FirstPropertyValue -Object $json -Names @('blockedCount') -Default 0)
                        failCount = [int](Get-FirstPropertyValue -Object $json -Names @('failCount') -Default 0)
                        attemptedTrialCount = [int](Get-FirstPropertyValue -Object $json -Names @('attemptedTrialCount') -Default 0)
                        launcherGatePassed = [bool](Get-FirstPropertyValue -Object $json.decisionGate -Names @('twoDFirstLauncherGatePassed') -Default $false)
                    }
                }
            }
    )
}
$latestTwoDFirstLauncherPreflight = @(
    $twoDFirstLauncherSummaries |
        Where-Object { [bool]$_.dryRun -and [string]$_.preflightStatus -eq 'pass' -and [string]$_.status -eq 'pass' } |
        Sort-Object lastWriteTime -Descending |
        Select-Object -First 1
)
$realTwoDFirstLauncherSummaries = @($twoDFirstLauncherSummaries | Where-Object { -not [bool]$_.dryRun })
$bestRealTwoDFirstLauncher = @(
    $realTwoDFirstLauncherSummaries |
        Sort-Object @{ Expression = { $_.passCount }; Descending = $true }, @{ Expression = { $_.lastWriteTime }; Descending = $true } |
        Select-Object -First 1
)
$twoDFirstLauncherPreflightPass = [bool]$latestTwoDFirstLauncherPreflight
$twoDFirstLauncherPhysicalPass = (
    $bestRealTwoDFirstLauncher -and
    ([bool]$bestRealTwoDFirstLauncher.launcherGatePassed -or (
        [int]$bestRealTwoDFirstLauncher.passCount -ge 1 -and
        [int]$bestRealTwoDFirstLauncher.blockedCount -eq 0 -and
        [int]$bestRealTwoDFirstLauncher.failCount -eq 0
    ))
)

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
$latestManualSignoff = Resolve-LatestSummary `
    -Root $ManualSignoffRoot `
    -FileName 'direct-handoff-manual-signoff-summary.json' `
    -Predicate {
        param($json)
        return [string]$json.status -eq 'pass'
    }
$latestManualSignoffAny = Resolve-LatestSummary `
    -Root $ManualSignoffRoot `
    -FileName 'direct-handoff-manual-signoff-summary.json'
$cleanTrialGate = $false
$manualHeadsetPass = $false
$defaultApproved = $false
$decisionManualStatus = 'missing'
$manualSignoffStatus = 'missing'
$manualSignoffPath = ''
$latestManualSignoffStatus = ''
$decisionDefaultApproved = $false
$directCandidateStatus = 'missing'
if ($bestRealDirect) {
    $decisionGate = $bestRealDirect.json.decisionGate
    $cleanTrialGate = [bool](Get-FirstPropertyValue -Object $decisionGate -Names @('automatedQuestTrialGatePassed') -Default $false)
    $decisionManualStatus = [string](Get-FirstPropertyValue -Object $decisionGate -Names @('manualHeadsetPassStatus') -Default 'missing')
    $decisionDefaultApproved = [bool](Get-FirstPropertyValue -Object $decisionGate -Names @('defaultDirectPendingIntentApproved') -Default $false)
    $directCandidateStatus = [string](Get-FirstPropertyValue -Object $decisionGate -Names @('candidateAStatus') -Default '')
}
if ($latestManualSignoff) {
    $manualSignoffStatus = [string]$latestManualSignoff.json.status
    $manualSignoffPath = $latestManualSignoff.path
}
elseif ($latestManualSignoffAny) {
    $latestManualSignoffStatus = [string]$latestManualSignoffAny.json.status
    $manualSignoffStatus = if ([string]::IsNullOrWhiteSpace($latestManualSignoffStatus)) { 'present-not-pass' } else { $latestManualSignoffStatus }
    $manualSignoffPath = $latestManualSignoffAny.path
}
$manualHeadsetPass = $manualSignoffStatus -eq 'pass'
$defaultApproved = $cleanTrialGate -and $manualHeadsetPass

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
    -Id 'demo-unity-apk-trigger-catalog' `
    -Requirement 'The demo Unity stimulus APK and public example trigger catalog advertise the two questionnaire/tracer triggers used by the builder workflow.' `
    -Status $(if ($demoUnityCatalogPass) { 'proven' } else { 'missing' }) `
    -EvidencePath $directHandoffDryRunSummaryPath `
    -Evidence "unityApk=$($demoUnityApkEvidence.path); bytes=$($demoUnityApkEvidence.bytes); sha256=$($demoUnityApkEvidence.sha256); preflightStatus=$($preflight.status); embeddedTriggerCount=$unityEmbeddedTriggerCount; exampleCatalog=$exampleCatalogPath"
$requirements += New-Requirement `
    -Id 'unity-input-modality-guardrails' `
    -Requirement 'Generic Unity demo/stimulus APKs must pass hand-and-controller input-modality preflight before headset trials, so Horizon controller-required launch dialogs are treated as build issues unless controller-only input is explicit.' `
    -Status $(if ($unityInputModalityPass) { 'proven' } else { 'missing' }) `
    -EvidencePath $(if ($latestUnityInputModalityWorkflow) { [string]$latestUnityInputModalityWorkflow.path } else { [string]$CompanionSummaryPath }) `
    -Evidence "receiptPass=$unityInputModalityReceiptPass; modalityStatus=$([string](Get-FirstPropertyValue -Object $unityInputModality -Names @('status') -Default '')); sourceHandEnabled=$([bool](Get-FirstPropertyValue -Object (Get-FirstPropertyValue -Object $unityInputModalitySourceFacts -Names @('openXrFacts') -Default $null) -Names @('handEnabled') -Default $false)); sourceControllerEnabled=$([bool](Get-FirstPropertyValue -Object (Get-FirstPropertyValue -Object $unityInputModalitySourceFacts -Names @('openXrFacts') -Default $null) -Names @('controllerEnabled') -Default $false)); apkHandTrackingRequiredFalse=$([bool](Get-FirstPropertyValue -Object (Get-FirstPropertyValue -Object $unityInputModalityApkFacts -Names @('manifestFacts') -Default $null) -Names @('handTrackingRequiredFalse') -Default $false))" `
    -Missing $(if ($unityInputModalityPass) { @() } else { @('unity-input-modality-guardrails-pass') })
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
    -Requirement 'The local companion can package workflow evidence into typed zip bundles; once a physical-gate packet has been prepared, its bundle must include the packet summary, runbook, manual signoff artifacts, and linked audit summary.' `
    -Status $(if ($evidenceBundleRequirementPass) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "evidenceBundleEndpointPass=$($checks.evidenceBundleEndpointPass); workflowEntries=$($artifacts.evidenceBundle.entryCount); workflowBytes=$($artifacts.evidenceBundle.bytes); physicalGatePacketBundleEvidenceAvailable=$physicalGatePacketBundleEvidenceAvailable; physicalGatePacketBundlePass=$physicalGatePacketBundlePass; physicalPacketEntries=$((Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('entryCount') -Default 0)); physicalPacketTextEntries=$((Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('txtEntryCount') -Default 0)); physicalPacketBundle=$physicalGatePacketEvidenceBundlePath; missingPhysicalPacketEntries=$($physicalGatePacketMissingBundleEntries -join ',')" `
    -Missing $(if ($evidenceBundleRequirementPass) { @() } elseif (-not [bool]$checks.evidenceBundleEndpointPass) { @('workflow-evidence-bundle-endpoint') } elseif ($physicalGatePacketBundleEvidenceAvailable) { @('portable-physical-gate-packet-evidence-bundle') + $physicalGatePacketMissingBundleEntries } else { @('evidence-bundle-requirement') })
$requirements += New-Requirement `
    -Id 'direct-pendingintent-contract-preflight' `
    -Requirement 'Direct XR -> 2D panel -> same XR app PendingIntent contract preflights with the real questionnaire, tracer, and Unity APK package/catalog contract.' `
    -Status $(if ([bool]$checks.directHandoffDryRunContractPass -and [bool]$checks.workflowDirectHandoffClampGatePass) { 'proven' } else { 'missing' }) `
    -EvidencePath ([string]$CompanionSummaryPath) `
    -Evidence "directHandoffDryRunContractPass=$($checks.directHandoffDryRunContractPass); workflowDirectHandoffClampGatePass=$($checks.workflowDirectHandoffClampGatePass)"
$requirements += New-Requirement `
    -Id '2d-first-launcher-offline-spine' `
    -Requirement 'The 2D-first launcher variant has a generated questionnaire APK, local render evidence, and direct handoff dry-run preflight, with only physical Quest trials remaining.' `
    -Status $(if ($twoDFirstPass) { 'proven' } else { 'missing' }) `
    -EvidencePath $(if ($latestTwoDFirstWorkflow) { [string]$latestTwoDFirstWorkflow.path } else { '' }) `
    -Evidence $(if ($twoDFirstWorkflow) { "config=$($twoDFirstWorkflow.configPath); status=$($twoDFirstWorkflow.status); configPass=$twoDFirstConfigPass; statusPass=$twoDFirstStatusPass; countsPass=$twoDFirstCountsPass; noRemainingWorkflowIssue=$twoDFirstNoRemainingWorkflowIssue; onlyPhysicalWarning=$twoDFirstOnlyPhysicalWarning; apkPass=$twoDFirstApkPass; renderPass=$twoDFirstRenderPass; preflightPass=$twoDFirstPreflightPass; apk=$($twoDFirstApkEvidence.path); bytes=$($twoDFirstApkEvidence.bytes); sha256=$($twoDFirstApkEvidence.sha256); renderGate=$($twoDFirstRender.passesArtifactGate); preflightStatus=$($twoDFirstDirectPreflight.preflightStatus)" } else { 'no questionnaireFirst builder-to-Quest workflow summary found' }) `
    -Missing $(if ($twoDFirstPass) { @() } else { @('2d-first-builder-to-quest-offline-spine-pass') })
$requirements += New-Requirement `
    -Id '2d-first-launcher-real-product-path-trial' `
    -Requirement 'The participant-facing 2D-first front door has at least one real Quest product-path trial: questionnaire APK launched first, demographics exported, and Unity opened through openNext without ADB foreground switching after the initial questionnaire launch.' `
    -Status $(if ($twoDFirstLauncherPhysicalPass) { 'proven' } elseif ($twoDFirstLauncherPreflightPass) { 'physical-pending' } else { 'missing' }) `
    -EvidencePath $(if ($bestRealTwoDFirstLauncher) { [string]$bestRealTwoDFirstLauncher.path } elseif ($latestTwoDFirstLauncherPreflight) { [string]$latestTwoDFirstLauncherPreflight.path } else { '' }) `
    -Evidence $(if ($bestRealTwoDFirstLauncher) { "status=$($bestRealTwoDFirstLauncher.status); passCount=$($bestRealTwoDFirstLauncher.passCount); blockedCount=$($bestRealTwoDFirstLauncher.blockedCount); failCount=$($bestRealTwoDFirstLauncher.failCount); launcherGatePassed=$($bestRealTwoDFirstLauncher.launcherGatePassed); preflightStatus=$($bestRealTwoDFirstLauncher.preflightStatus)" } elseif ($latestTwoDFirstLauncherPreflight) { "dryRunStatus=$($latestTwoDFirstLauncherPreflight.status); preflightStatus=$($latestTwoDFirstLauncherPreflight.preflightStatus); physicalTrialPending=True" } else { 'no 2D-first launcher validation summary found' }) `
    -Missing $(if ($twoDFirstLauncherPhysicalPass) { @() } elseif ($twoDFirstLauncherPreflightPass) { @('one-2d-first-launcher-real-product-path-pass') } else { @('2d-first-launcher-preflight-pass', 'one-2d-first-launcher-real-product-path-pass') })
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
    -Requirement 'A structured human/manual headset pass signoff is required before defaulting direct PendingIntent in production.' `
    -Status $(if ($manualHeadsetPass) { 'proven' } else { 'physical-pending' }) `
    -EvidencePath $manualSignoffPath `
    -Evidence "manualSignoffStatus=$manualSignoffStatus; directDecisionManualStatus=$decisionManualStatus; readinessDefaultDirectPendingIntentApproved=$defaultApproved; directDecisionDefaultDirectPendingIntentApproved=$decisionDefaultApproved" `
    -Missing $(if ($manualHeadsetPass) { @() } else { @('direct-handoff-manual-signoff-pass') })

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
        demoUnityApk = $demoUnityApkEvidence
        demoUnityPreflightSummaryPath = $directHandoffDryRunSummaryPath
        demoUnityEmbeddedTriggerCount = $unityEmbeddedTriggerCount
        unityInputModalityWorkflowSummaryPath = if ($latestUnityInputModalityWorkflow) { $latestUnityInputModalityWorkflow.path } else { '' }
        unityInputModalityPass = $unityInputModalityPass
        unityInputModality = $unityInputModality
        exampleTriggerCatalogPath = $exampleCatalogPath
        twoDFirstWorkflowSummaryPath = if ($latestTwoDFirstWorkflow) { $latestTwoDFirstWorkflow.path } else { '' }
        twoDFirstWorkflowStatus = if ($twoDFirstWorkflow) { $twoDFirstWorkflow.status } else { '' }
        twoDFirstConfigPath = if ($twoDFirstWorkflow) { $twoDFirstWorkflow.configPath } else { '' }
        twoDFirstQuestionnaireApk = $twoDFirstApkEvidence
        twoDFirstRenderGatePass = if ($twoDFirstRender) { [bool]$twoDFirstRender.passesArtifactGate } else { $false }
        twoDFirstDirectHandoffPreflightStatus = if ($twoDFirstDirectPreflight) { [string]$twoDFirstDirectPreflight.preflightStatus } else { '' }
        twoDFirstLauncherPreflightSummaryPath = if ($latestTwoDFirstLauncherPreflight) { $latestTwoDFirstLauncherPreflight.path } else { '' }
        twoDFirstLauncherPreflightStatus = if ($latestTwoDFirstLauncherPreflight) { $latestTwoDFirstLauncherPreflight.preflightStatus } else { '' }
        bestRealTwoDFirstLauncherSummaryPath = if ($bestRealTwoDFirstLauncher) { $bestRealTwoDFirstLauncher.path } else { '' }
        bestRealTwoDFirstLauncherPassCount = if ($bestRealTwoDFirstLauncher) { $bestRealTwoDFirstLauncher.passCount } else { 0 }
        twoDFirstLauncherPhysicalPass = $twoDFirstLauncherPhysicalPass
        bestRealDirectHandoffSummaryPath = if ($bestRealDirect) { $bestRealDirect.path } else { '' }
        bestRealDirectHandoffPassCount = if ($bestRealDirect) { $bestRealDirect.passCount } else { 0 }
        latestRealDirectHandoffSummaryPath = if ($latestRealDirect) { $latestRealDirect.path } else { '' }
        latestRealDirectHandoffStatus = if ($latestRealDirect) { $latestRealDirect.status } else { '' }
        realDirectHandoffSummaryCount = $realDirectSummaries.Count
        directHandoffManualSignoffSummaryPath = $manualSignoffPath
        directHandoffManualSignoffStatus = $manualSignoffStatus
        physicalGatePacketSummaryPath = $physicalGatePacketSummaryPath
        physicalGatePacketEvidenceBundlePath = $physicalGatePacketEvidenceBundlePath
        physicalGatePacketEvidenceBundleAvailable = $physicalGatePacketBundleEvidenceAvailable
        physicalGatePacketEvidenceBundlePass = $physicalGatePacketBundlePass
        physicalGatePacketEvidenceBundleEntryCount = [int](Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('entryCount') -Default 0)
        physicalGatePacketEvidenceBundleTextEntryCount = [int](Get-FirstPropertyValue -Object $physicalGatePacketEvidenceBundle -Names @('txtEntryCount') -Default 0)
        physicalGatePacketMissingBundleEntries = $physicalGatePacketMissingBundleEntries
        directDecisionManualHeadsetPassStatus = $decisionManualStatus
        directDecisionDefaultDirectPendingIntentApproved = $decisionDefaultApproved
        latestPhysicalBlock = $latestPhysicalBlock
    }
    requirements = $requirements
    nextPhysicalGates = [ordered]@{
        requiredCleanQuestTrials = $RequiredCleanQuestTrials
        currentBestCleanQuestTrialPassCount = if ($bestRealDirect) { $bestRealDirect.passCount } else { 0 }
        twoDFirstLauncherPhysicalPass = $twoDFirstLauncherPhysicalPass
        twoDFirstLauncherBestPassCount = if ($bestRealTwoDFirstLauncher) { $bestRealTwoDFirstLauncher.passCount } else { 0 }
        twoDFirstLauncherPreflightStatus = if ($latestTwoDFirstLauncherPreflight) { $latestTwoDFirstLauncherPreflight.preflightStatus } else { 'missing' }
        manualHeadsetPassStatus = $manualSignoffStatus
        manualHeadsetPassSignoffSummaryPath = $manualSignoffPath
        directDecisionManualHeadsetPassStatus = $decisionManualStatus
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
