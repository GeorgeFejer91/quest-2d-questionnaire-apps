param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$RepoRoot = "",
    [string]$TemporalTracerPath = "",
    [string]$UnityDemoPath = "",
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR",
    [string]$Serial = "",
    [string]$RunId = "",
    [int]$QuestTrials = 10,
    [switch]$SkipApkBuild,
    [switch]$SkipUnity,
    [switch]$RunQuest
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "universal-handoff-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
}
if ([string]::IsNullOrWhiteSpace($TemporalTracerPath)) {
    $TemporalTracerPath = Join-Path $RepoRoot 'TemporalExperienceTracerVR-2D'
}
if ([string]::IsNullOrWhiteSpace($UnityDemoPath)) {
    $UnityDemoPath = Join-Path $RepoRoot 'AweGreatDictatorUnity'
}

$artifactRoot = Join-Path $ProjectPath ("artifacts\universal-handoff\" + $RunId)
$builderOut = Join-Path $artifactRoot 'builder'
$questionnaireGeneratorRunId = "$RunId-questionnaire"
$questionnaireGeneratorSummary = Join-Path $ProjectPath ("artifacts\apk-generator\$questionnaireGeneratorRunId\generator-summary.json")
$temporalRenderOut = Join-Path $artifactRoot 'temporal-render'
$unityOut = Join-Path $artifactRoot 'unity-video'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$steps = New-Object 'System.Collections.Generic.List[object]'

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Command,
        [switch]$AllowFailure
    )

    $started = Get-Date
    Write-Host ""
    Write-Host "== $Name =="
    try {
        & $Command
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE"
        }
        $steps.Add([ordered]@{
            name = $Name
            status = 'pass'
            started = $started.ToString('o')
            completed = (Get-Date).ToString('o')
        }) | Out-Null
    }
    catch {
        $stepStatus = 'fail'
        if ($AllowFailure) {
            $stepStatus = 'warn'
        }
        $steps.Add([ordered]@{
            name = $Name
            status = $stepStatus
            started = $started.ToString('o')
            completed = (Get-Date).ToString('o')
            error = $_.Exception.Message
        }) | Out-Null
        if (-not $AllowFailure) {
            throw
        }
    }
}

Invoke-Step 'builder-smoke-and-handoff-config' {
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $ProjectPath 'tools\validate-questionnaire-builder.ps1') `
        -ProjectPath $ProjectPath `
        -OutputDir $builderOut
}

$handoffConfig = Join-Path $builderOut 'awe-great-dictator-handoff.config.json'
$handoffQuality = Join-Path $builderOut 'awe-great-dictator-handoff.quality-report.json'
$handoffChainPlan = Join-Path $builderOut 'awe-great-dictator-handoff.chainlink-plan.json'
foreach ($required in @($handoffConfig, $handoffQuality, $handoffChainPlan)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Expected handoff builder output is missing: $required"
    }
}

Invoke-Step 'handoff-config-validation' {
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $ProjectPath 'tools\validate-questionnaire-config.ps1') `
        -ConfigPath $handoffConfig `
        -ReferenceProjectPath $ReferenceProjectPath
}

$generatorArgs = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $ProjectPath 'tools\generate-questionnaire-apk.ps1'),
    '-ConfigPath',
    $handoffConfig,
    '-ReferenceProjectPath',
    $ReferenceProjectPath,
    '-RenderPreview',
    '-RunId',
    $questionnaireGeneratorRunId
)
if ($SkipApkBuild) {
    $generatorArgs += '-SkipBuild'
}

Invoke-Step 'questionnaire-apk-generation-and-local-render' {
    & powershell @generatorArgs
}

Invoke-Step 'temporal-tracer-assets' {
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $TemporalTracerPath 'tools\validate-temporal-tracer-assets.ps1')
}

Invoke-Step 'temporal-tracer-local-render' {
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $TemporalTracerPath 'tools\render-temporal-tracer-visuals.ps1') `
        -OutputRoot $temporalRenderOut `
        -RunId 'render' `
        -Sizes '1280x800,900x800'
}

if (-not $SkipUnity) {
    Invoke-Step 'unity-video-local-validation' {
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $UnityDemoPath 'tools\validate-video-playback.ps1') `
            -OutDir $unityOut
    }
}

if ($RunQuest) {
    if ([string]::IsNullOrWhiteSpace($Serial)) {
        throw '-RunQuest requires -Serial.'
    }

    $questionnaireApk = $null
    if (Test-Path -LiteralPath $questionnaireGeneratorSummary) {
        $questionnaireApk = [string]((Get-Content -LiteralPath $questionnaireGeneratorSummary -Raw | ConvertFrom-Json).apk)
    }
    if ([string]::IsNullOrWhiteSpace($questionnaireApk) -or -not (Test-Path -LiteralPath $questionnaireApk)) {
        throw "Questionnaire APK not found for Quest validation. Expected generator summary: $questionnaireGeneratorSummary"
    }

    Invoke-Step 'quest-questionnaire-command-replay' {
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $ProjectPath 'tools\quest-validate.ps1') `
            -Serial $Serial `
            -Apk $questionnaireApk `
            -SkipBuild `
            -LeaveForeground `
            -OutputRoot (Join-Path $artifactRoot 'quest-questionnaire')
    }

    Invoke-Step -Name 'quest-direct-handoff-manual-required' -AllowFailure -Command {
        throw "Run the recipe examples\session-recipe.xr-questionnaire-panel-handoff.json for $QuestTrials direct PendingIntent trials. This gate needs headset observation and must not be faked."
    }
}

$unityValidationOutput = $null
if (-not $SkipUnity) {
    $unityValidationOutput = $unityOut
}

$questSerial = $null
if (-not [string]::IsNullOrWhiteSpace($Serial)) {
    $questSerial = $Serial
}

$failed = @($steps | Where-Object { $_.status -eq 'fail' }).Count
$workflowStatus = 'fail'
if ($failed -eq 0) {
    $workflowStatus = 'pass'
}

$questRequested = $RunQuest.IsPresent
$questRecipe = Join-Path $RepoRoot 'examples\session-recipe.xr-questionnaire-panel-handoff.json'
$stepArray = @($steps.ToArray())

$summary = [ordered]@{
    schemaVersion = 'mq.universal_handoff.workflow_validation.v1'
    status = $workflowStatus
    runId = $RunId
    artifactRoot = $artifactRoot
    builder = [ordered]@{
        outputDir = $builderOut
        handoffConfig = $handoffConfig
        handoffQualityReport = $handoffQuality
        handoffChainPlan = $handoffChainPlan
    }
    questionnaire = [ordered]@{
        generatorSummary = $questionnaireGeneratorSummary
    }
    temporalTracer = [ordered]@{
        projectPath = $TemporalTracerPath
        renderOutput = $temporalRenderOut
    }
    unityDemo = [ordered]@{
        projectPath = $UnityDemoPath
        validationOutput = $unityValidationOutput
    }
    quest = [ordered]@{
        requested = $questRequested
        serial = $questSerial
        requiredTrials = $QuestTrials
        recipe = $questRecipe
    }
    steps = $stepArray
    completedAt = (Get-Date).ToString('o')
}

$summaryPath = Join-Path $artifactRoot 'universal-handoff-workflow-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ""
Write-Host "Universal handoff workflow summary: $summaryPath"
