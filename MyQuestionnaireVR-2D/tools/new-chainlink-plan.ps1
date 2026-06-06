param(
    [string]$TargetApk = "",
    [string]$TargetPackage = "",
    [string]$TargetActivity = "",
    [string]$TargetLabel = "",
    [string]$ExperimentId = "",
    [string]$PlanId = "",
    [string]$QuestionnaireId = "viscereality-maia2",
    [string]$QuestionnaireVersion = "1.0.0",
    [int]$PictographicRepeats = 2,
    [string]$TriggerButton = "auto-unused-non-breath-tracking",
    [string]$OutputPath = "",
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer"
)

$ErrorActionPreference = 'Stop'

function Get-SafeFileStem {
    param([string]$Value, [string]$Fallback = "target-apk")
    $raw = if ($null -eq $Value) { '' } else { $Value }
    $safe = $raw.ToLowerInvariant() -replace '[^a-z0-9._-]+', '-'
    $safe = $safe.Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { return $Fallback }
    return $safe
}

function Get-ApkLaunchInfo {
    param([string]$ApkPath)
    if ([string]::IsNullOrWhiteSpace($ApkPath)) { return $null }
    if (-not (Test-Path -LiteralPath $ApkPath)) {
        throw "Target APK not found: $ApkPath"
    }

    $buildToolsRoot = Join-Path $UnityAndroidRoot 'SDK\build-tools'
    $aapt = Get-ChildItem -LiteralPath $buildToolsRoot -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $aapt) {
        throw "Could not find aapt.exe under $buildToolsRoot"
    }

    $badging = & $aapt.FullName dump badging $ApkPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $badging | Write-Host
        throw "aapt dump badging failed for $ApkPath."
    }

    $packageLine = $badging | Select-String -Pattern "^package:" | Select-Object -First 1
    $activityLine = $badging | Select-String -Pattern "^launchable-activity:" | Select-Object -First 1
    $labelLine = $badging | Select-String -Pattern "^application-label:" | Select-Object -First 1
    $package = if ($packageLine -and $packageLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
    $activity = if ($activityLine -and $activityLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
    $label = if ($labelLine -and $labelLine.ToString() -match "'([^']*)'") { $Matches[1] } else { "" }

    [pscustomobject]@{
        apk = (Resolve-Path -LiteralPath $ApkPath).Path
        package = $package
        activity = $activity
        label = $label
    }
}

function New-RegisteredBlock {
    param(
        [int]$Index,
        [string]$Id,
        [string]$Type,
        [string]$Label,
        [hashtable]$Trigger,
        [string]$Package,
        [string]$Activity,
        [string]$Action,
        [string]$QuestionnaireMode = "",
        [string]$TargetMode = "",
        [string]$SaveNamespace,
        [hashtable]$ExpectedOutputs,
        [hashtable]$Extras
    )

    $number = "{0:000}" -f $Index
    [ordered]@{
        number = $number
        id = "${number}_$(Get-SafeFileStem $Id "block-$number")"
        type = $Type
        label = $Label
        trigger = $Trigger
        package = $Package
        activity = $Activity
        action = $Action
        questionnaireMode = $QuestionnaireMode
        targetMode = $TargetMode
        saveNamespace = $SaveNamespace
        expectedOutputs = $ExpectedOutputs
        extras = $Extras
    }
}

$apkInfo = Get-ApkLaunchInfo -ApkPath $TargetApk
if ($apkInfo) {
    if ([string]::IsNullOrWhiteSpace($TargetPackage)) { $TargetPackage = $apkInfo.package }
    if ([string]::IsNullOrWhiteSpace($TargetActivity)) { $TargetActivity = $apkInfo.activity }
    if ([string]::IsNullOrWhiteSpace($TargetLabel)) { $TargetLabel = $apkInfo.label }
}

if ([string]::IsNullOrWhiteSpace($TargetPackage)) {
    throw "TargetPackage is required. Pass -TargetApk or -TargetPackage."
}
if ([string]::IsNullOrWhiteSpace($TargetLabel)) {
    $TargetLabel = $TargetPackage
}
if ([string]::IsNullOrWhiteSpace($ExperimentId)) {
    $ExperimentId = "$(Get-SafeFileStem $TargetLabel)-experiment"
}
if ([string]::IsNullOrWhiteSpace($PlanId)) {
    $PlanId = "$(Get-SafeFileStem $TargetLabel)-chainlink-plan"
}
if ($PictographicRepeats -lt 1) { $PictographicRepeats = 1 }
if ($PictographicRepeats -gt 50) { $PictographicRepeats = 50 }
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) "QuestionnaireConfigs\examples\$(Get-SafeFileStem $PlanId).chain-plan.json"
}

$questionnairePackage = 'org.mesmerprism.viscereality.questionnaires2d'
$questionnaireActivity = 'org.mesmerprism.viscereality.questionnaires2d.MainActivity'
$questionnaireAction = 'org.mesmerprism.viscereality.questionnaires2d.RUN'
$blocks = New-Object System.Collections.Generic.List[object]

$blocks.Add((New-RegisteredBlock -Index 1 -Id 'baseline_questionnaire' -Type 'questionnaire' -Label 'Language, demographics, MAIA-2' `
    -Trigger @{ type = 'onPlanStart' } `
    -Package $questionnairePackage -Activity $questionnaireActivity -Action $questionnaireAction `
    -QuestionnaireMode 'baseline' -SaveNamespace 'baseline_maia2' `
    -ExpectedOutputs @{ demographics = $true; maia2Answers = 37; maia2Scores = 8 } `
    -Extras @{ 'mq.questionnaireMode' = 'baseline'; 'mq.flowMode' = 'baseline'; 'mq.finishBehavior' = 'resumeCaller'; 'mq.autoCloseDelayMs' = 2000 }))

$blocks.Add((New-RegisteredBlock -Index 2 -Id 'target_apk_start' -Type 'apk' -Label $TargetLabel `
    -Trigger @{ type = 'afterBlock'; blockNumber = '001' } `
    -Package $TargetPackage -Activity $TargetActivity -Action 'android.intent.action.MAIN' `
    -TargetMode 'startOrResume' -SaveNamespace 'target_apk' `
    -ExpectedOutputs @{ targetForeground = $true } `
    -Extras @{ 'mq.targetRole' = 'experiment-apk'; 'mq.controllerButton' = $TriggerButton; 'mq.controllerButtonPolicy' = 'unused-non-breath-tracking' }))

$index = 3
for ($repeat = 1; $repeat -le $PictographicRepeats; $repeat++) {
    $repeatText = "{0:00}" -f $repeat
    $blocks.Add((New-RegisteredBlock -Index $index -Id "pictographic_$repeatText" -Type 'questionnaire' -Label "Pictographic scales $repeat" `
        -Trigger @{ type = 'controllerButton'; button = $TriggerButton; foregroundPackage = $TargetPackage } `
        -Package $questionnairePackage -Activity $questionnaireActivity -Action $questionnaireAction `
        -QuestionnaireMode 'pictographic' -SaveNamespace "pictographic_$repeatText" `
        -ExpectedOutputs @{ pictographicSelections = 3 } `
        -Extras @{ 'mq.questionnaireMode' = 'pictographic'; 'mq.flowMode' = 'pictographic'; 'mq.blockInstance' = $repeat; 'mq.finishBehavior' = 'resumeCaller'; 'mq.autoCloseDelayMs' = 2000 }))
    $index++

    $blocks.Add((New-RegisteredBlock -Index $index -Id "resume_target_apk_$repeatText" -Type 'apk' -Label "$TargetLabel resume $repeat" `
        -Trigger @{ type = 'afterBlock'; blockRole = 'pictographic'; instance = $repeat } `
        -Package $TargetPackage -Activity $TargetActivity -Action 'android.intent.action.MAIN' `
        -TargetMode 'resume' -SaveNamespace "target_resume_$repeatText" `
        -ExpectedOutputs @{ targetForeground = $true } `
        -Extras @{ 'mq.targetRole' = 'experiment-apk'; 'mq.resumeAfterPictographic' = $repeat; 'mq.controllerButton' = $TriggerButton; 'mq.controllerButtonPolicy' = 'unused-non-breath-tracking' }))
    $index++
}

$registry = [ordered]@{
    schemaVersion = 'viscereality.chainlink.block-registry.v1'
    experimentId = $ExperimentId
    planId = $PlanId
    questionnaireId = $QuestionnaireId
    questionnaireVersion = $QuestionnaireVersion
    controllerTriggerButton = $TriggerButton
    targetApp = [ordered]@{
        label = $TargetLabel
        package = $TargetPackage
        activity = $TargetActivity
        sourceApk = if ($apkInfo) { $apkInfo.apk } else { '' }
    }
    dataPolicy = [ordered]@{
        uniqueRunPerBlock = $true
        perResponseTimestampUtc = $true
        appendOnlyExports = $true
        noOverwrite = $true
    }
    blocks = @($blocks.ToArray())
}

$steps = @($registry.blocks | ForEach-Object {
    $extras = [ordered]@{}
    foreach ($entry in $_.extras.GetEnumerator()) {
        $extras[$entry.Key] = $entry.Value
    }
    $extras['mq.experimentId'] = $ExperimentId
    $extras['mq.chainPlanId'] = $PlanId
    $extras['mq.blockNumber'] = $_.number
    $extras['mq.blockId'] = $_.id
    $extras['mq.saveNamespace'] = $_.saveNamespace

    [ordered]@{
        id = $_.id
        blockNumber = $_.number
        type = if ($_.type -eq 'apk') { 'scenario' } else { $_.type }
        package = $_.package
        activity = $_.activity
        action = $_.action
        trigger = $_.trigger
        saveNamespace = $_.saveNamespace
        expectedOutputs = $_.expectedOutputs
        extras = $extras
    }
})

$plan = [ordered]@{
    schemaVersion = 'viscereality.chainlink.plan.v1'
    legacySchemaVersion = 'my-questionnaire-2d.chain-plan.v1'
    planKind = 'registered-block-sequence'
    experimentId = $ExperimentId
    planId = $PlanId
    questionnaireId = $QuestionnaireId
    questionnaireVersion = $QuestionnaireVersion
    chainId = "$(Get-SafeFileStem $PlanId)-chain"
    defaultFinishBehavior = 'resumeCaller'
    dataPolicy = $registry.dataPolicy
    blockRegistry = $registry
    steps = $steps
}

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}
$plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

$summary = [ordered]@{
    schemaVersion = 'viscereality.chainlink-plan-generator.v1'
    status = 'pass'
    targetPackage = $TargetPackage
    targetActivity = $TargetActivity
    targetLabel = $TargetLabel
    sourceApk = if ($apkInfo) { $apkInfo.apk } else { '' }
    outputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    blockCount = @($registry.blocks).Count
    pictographicRepeats = $PictographicRepeats
    completedAt = (Get-Date).ToString('o')
}

$summary | ConvertTo-Json -Depth 10
