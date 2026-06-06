param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR",
    [string]$Serial = "",
    [string]$RunId = "",
    [int]$QuestWaitSeconds = 20,
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$SkipQuest
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "web-to-apk-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

function Invoke-Required {
    param(
        [string]$Label,
        [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "== $Label =="
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

$artifactDir = Join-Path $ProjectPath ("artifacts\web-builder-output-apk\" + $RunId)
$builderOutputDir = Join-Path $artifactDir 'builder-output'
New-Item -ItemType Directory -Force -Path $builderOutputDir | Out-Null

$builderSummaryPath = Join-Path $builderOutputDir 'builder-smoke-summary.json'
$builderConfigPath = Join-Path $builderOutputDir 'demo-slider.config.json'
$builderQualityPath = Join-Path $builderOutputDir 'demo-slider.quality-report.json'
$generatorRunId = "$RunId-generator"
$generatorSummaryPath = Join-Path $ProjectPath ("artifacts\apk-generator\$generatorRunId\generator-summary.json")
$questOutputRoot = Join-Path $artifactDir 'quest-validation'
$foregroundOutputRoot = Join-Path $artifactDir 'fg'
$foregroundSummaryPath = Join-Path $foregroundOutputRoot 'render\render-wrapper-summary.json'

Invoke-Required "Web builder export" {
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $ProjectPath 'tools\validate-questionnaire-builder.ps1') `
        -ProjectPath $ProjectPath `
        -OutputDir $builderOutputDir
}

if (-not (Test-Path -LiteralPath $builderConfigPath)) {
    throw "Expected builder-emitted config not found: $builderConfigPath"
}

Invoke-Required "Builder-emitted config validation" {
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $ProjectPath 'tools\validate-questionnaire-config.ps1') `
        -ConfigPath $builderConfigPath `
        -ReferenceProjectPath $ReferenceProjectPath
}

$generatorArgs = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $ProjectPath 'tools\generate-questionnaire-apk.ps1'),
    '-ConfigPath',
    $builderConfigPath,
    '-ReferenceProjectPath',
    $ReferenceProjectPath,
    '-RenderPreview',
    '-RunId',
    $generatorRunId
)
if ($SkipBuild) {
    $generatorArgs += '-SkipBuild'
}
if ($SkipTests) {
    $generatorArgs += '-SkipTests'
}

Invoke-Required "Builder-emitted APK and render preview" {
    & powershell @generatorArgs
}

if (-not (Test-Path -LiteralPath $generatorSummaryPath)) {
    throw "Expected generator summary not found: $generatorSummaryPath"
}

$builderSummary = Get-Content -LiteralPath $builderSummaryPath -Raw | ConvertFrom-Json
$builderQuality = if (Test-Path -LiteralPath $builderQualityPath) { Get-Content -LiteralPath $builderQualityPath -Raw | ConvertFrom-Json } else { $null }
if ($null -eq $builderQuality) {
    throw "Expected builder quality report not found: $builderQualityPath"
}
if ($builderQuality.status -ne 'pass') {
    throw "Builder quality report did not pass: $builderQualityPath"
}
$generatorSummary = Get-Content -LiteralPath $generatorSummaryPath -Raw | ConvertFrom-Json
$apkPath = [string]$generatorSummary.apk
$renderSummaryPath = [string]$generatorSummary.renderSummary
$renderCount = $null
$renderWarnings = $null
$renderFailures = $null
if (-not [string]::IsNullOrWhiteSpace($renderSummaryPath) -and (Test-Path -LiteralPath $renderSummaryPath)) {
    $renderSummary = Get-Content -LiteralPath $renderSummaryPath -Raw | ConvertFrom-Json
    $renderCount = @($renderSummary.renders).Count
    $renderWarnings = @($renderSummary.renders | Where-Object { @($_.warn).Count -gt 0 }).Count
    $renderFailures = @($renderSummary.renders | Where-Object { @($_.fail).Count -gt 0 -or $_.status -ne 'pass' }).Count
}

$questStatus = "skipped"
$questSummaryPath = $null
if (-not $SkipQuest -and -not [string]::IsNullOrWhiteSpace($Serial)) {
    if ([string]::IsNullOrWhiteSpace($apkPath) -or -not (Test-Path -LiteralPath $apkPath)) {
        throw "Cannot run Quest validation because generated APK is missing: $apkPath"
    }

    Invoke-Required "Builder-emitted Quest command replay/export" {
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $ProjectPath 'tools\quest-validate.ps1') `
            -Serial $Serial `
            -OutputRoot $questOutputRoot `
            -Apk $apkPath `
            -SkipBuild `
            -StopLegacyUnityApp `
            -LeaveForeground `
            -WaitSeconds $QuestWaitSeconds
    }
    $questSummaryPath = Join-Path $questOutputRoot 'my-questionnaire-2d-validation-summary.json'

    Invoke-Required "Builder-emitted foreground-linked render pack" {
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $ProjectPath 'tools\render-questionnaire-visuals.ps1') `
            -ConfigPath $builderConfigPath `
            -ReferenceProjectPath $ReferenceProjectPath `
            -OutputRoot $foregroundOutputRoot `
            -RunId 'render' `
            -Serial $Serial `
            -CheckQuestForeground `
            -RequireQuestForeground `
            -LaunchBeforeForegroundCheck
    }
    $questStatus = "pass"
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.web-builder-output-apk.v1'
    status = 'pass'
    runId = $RunId
    artifactDir = $artifactDir
    builder = [ordered]@{
        summary = $builderSummaryPath
        generatedConfig = $builderConfigPath
        qualityReport = $builderQualityPath
        questionnaireId = $builderSummary.importedQuestionnaireId
        sliderItems = $builderSummary.importedSliderItems
        qualityStatus = $builderQuality.status
        qualityErrors = $builderQuality.issueCounts.error
        qualityWarnings = $builderQuality.issueCounts.warning
    }
    generator = [ordered]@{
        summary = $generatorSummaryPath
        apk = $apkPath
        apkSha256 = $generatorSummary.apkSha256
        renderSummary = $renderSummaryPath
        renderCount = $renderCount
        renderWarningScreens = $renderWarnings
        renderFailureScreens = $renderFailures
    }
    quest = [ordered]@{
        status = $questStatus
        serial = if ([string]::IsNullOrWhiteSpace($Serial)) { $null } else { $Serial }
        validationSummary = $questSummaryPath
        foregroundRenderSummary = if ($questStatus -eq 'pass') { $foregroundSummaryPath } else { $null }
    }
    completedAt = (Get-Date).ToString('o')
}

$summaryPath = Join-Path $artifactDir 'web-builder-output-apk-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ""
Write-Host "Web builder output APK validation written to $artifactDir"
Write-Host "Builder-emitted config: $builderConfigPath"
Write-Host "Summary: $summaryPath"
