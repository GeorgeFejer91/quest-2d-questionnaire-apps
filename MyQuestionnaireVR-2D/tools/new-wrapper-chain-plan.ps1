param(
    [string]$TargetApk = "",
    [string]$TargetPackage = "",
    [string]$TargetActivity = "",
    [string]$ScenarioId = "",
    [string]$ChainId = "",
    [ValidateSet('Wrapper', 'Source')]
    [string]$HookMode = 'Wrapper',
    [ValidateSet('ScenarioThenQuestionnaire', 'QuestionnaireThenScenario')]
    [string]$Order = 'ScenarioThenQuestionnaire',
    [string]$OutputPath = "",
    [int]$AutoContinueDelayMs = 10000,
    [string]$ParticipantId = "P001",
    [string]$ParticipantName = "P001",
    [string]$Language = "English",
    [string]$ExperimentId = "viscereality-experiment",
    [string]$SessionId = "",
    [string]$TrialId = "trial-01",
    [string]$QuestionnaireId = "viscereality-maia2",
    [string]$QuestionnaireVersion = "1.0.0",
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer"
)

$ErrorActionPreference = 'Stop'

function Resolve-Aapt {
    param([string]$AndroidRoot)
    $buildToolsRoot = Join-Path $AndroidRoot 'SDK\build-tools'
    $aapt = Get-ChildItem -LiteralPath $buildToolsRoot -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $aapt) {
        throw "Could not find aapt.exe under $buildToolsRoot"
    }
    return $aapt.FullName
}

function Get-ApkLaunchInfo {
    param(
        [string]$Apk,
        [string]$AndroidRoot
    )
    if (-not (Test-Path -LiteralPath $Apk)) {
        throw "APK not found: $Apk"
    }

    $aapt = Resolve-Aapt -AndroidRoot $AndroidRoot
    $badging = & $aapt dump badging $Apk 2>&1
    if ($LASTEXITCODE -ne 0) {
        $badging | Write-Host
        throw "aapt dump badging failed for $Apk"
    }

    $packageLine = $badging | Select-String -Pattern "^package:" | Select-Object -First 1
    $activityLine = $badging | Select-String -Pattern "^launchable-activity:" | Select-Object -First 1
    $package = if ($packageLine -and $packageLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
    $activity = if ($activityLine -and $activityLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
    [pscustomobject]@{ Package = $package; Activity = $activity }
}

function ConvertTo-Slug {
    param([string]$Value)
    $slug = ($Value -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return 'scenario'
    }
    return $slug
}

if (-not [string]::IsNullOrWhiteSpace($TargetApk)) {
    $info = Get-ApkLaunchInfo -Apk $TargetApk -AndroidRoot $UnityAndroidRoot
    if ([string]::IsNullOrWhiteSpace($TargetPackage)) {
        $TargetPackage = $info.Package
    }
    if ([string]::IsNullOrWhiteSpace($TargetActivity)) {
        $TargetActivity = $info.Activity
    }
}

if ([string]::IsNullOrWhiteSpace($TargetPackage)) {
    throw "TargetPackage is required, either directly or via -TargetApk."
}

if ([string]::IsNullOrWhiteSpace($ScenarioId)) {
    $ScenarioId = ConvertTo-Slug $TargetPackage
}
if ([string]::IsNullOrWhiteSpace($ChainId)) {
    $ChainId = "$ScenarioId-questionnaire-chain"
}
if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = "$ScenarioId-session"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) ("QuestionnaireConfigs\examples\$ChainId.chain-plan.json")
}

$scenarioStep = if ($HookMode -eq 'Wrapper') {
    $step = [ordered]@{
        id = "$ScenarioId-wrapper"
        type = "scenario"
        package = "org.viscereality.chainhookwrapper"
        activity = ".ChainHookActivity"
        action = "org.viscereality.CHAIN_COMMAND"
        command = "launchTarget"
        extras = [ordered]@{
            targetPackage = $TargetPackage
            scenarioId = $ScenarioId
            trialId = $TrialId
            "mq.scenarioId" = $ScenarioId
            "mq.trialId" = $TrialId
            "mq.autoContinueDelayMs" = $AutoContinueDelayMs
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetActivity)) {
        $step.extras.targetActivity = $TargetActivity
    }
    $step
}
else {
    $step = [ordered]@{
        id = "$ScenarioId-source-hook"
        type = "scenario"
        package = $TargetPackage
        action = "org.viscereality.CHAIN_COMMAND"
        command = "startScenario"
        extras = [ordered]@{
            scenarioId = $ScenarioId
            trialId = $TrialId
            "mq.sessionId" = $SessionId
            "mq.experimentId" = $ExperimentId
            "mq.scenarioId" = $ScenarioId
            "mq.trialId" = $TrialId
            "mq.participantId" = $ParticipantId
            "mq.participantName" = $ParticipantName
            "mq.language" = $Language
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetActivity)) {
        $step.activity = $TargetActivity
    }
    $step
}

$questionnaireStepId = if ($Order -eq 'ScenarioThenQuestionnaire') { "questionnaire-after-$ScenarioId" } else { "questionnaire-before-$ScenarioId" }
$questionnaireStep = [ordered]@{
    id = $questionnaireStepId
    type = "questionnaire"
    package = "org.viscereality.questionnaires2d"
    activity = ".MainActivity"
    extras = [ordered]@{
        "mq.sessionId" = $SessionId
        "mq.experimentId" = $ExperimentId
        "mq.scenarioId" = $ScenarioId
        "mq.trialId" = $TrialId
        "mq.participantId" = $ParticipantId
        "mq.participantName" = $ParticipantName
        "mq.language" = $Language
        "mq.autoCloseDelayMs" = 2000
    }
}

$steps = if ($Order -eq 'ScenarioThenQuestionnaire') {
    @($scenarioStep, $questionnaireStep)
}
else {
    @($questionnaireStep, $scenarioStep)
}

$plan = [ordered]@{
    schemaVersion = "my-questionnaire-2d.chain-plan.v1"
    chainId = $ChainId
    questionnaireId = $QuestionnaireId
    questionnaireVersion = $QuestionnaireVersion
    defaultFinishBehavior = "resumeCaller"
    steps = $steps
}

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    Status = "pass"
    OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    ChainId = $ChainId
    HookMode = $HookMode
    Order = $Order
    TargetPackage = $TargetPackage
    TargetActivity = $TargetActivity
    ScenarioId = $ScenarioId
    AutoContinueDelayMs = $AutoContinueDelayMs
} | Format-List
