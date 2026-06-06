param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ConfigPath = "",
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR",
    [string]$Serial = "",
    [string]$RunId = "",
    [string]$OperatorSignoffPath = "",
    [int]$ManualHardwareWaitSeconds = 90,
    [switch]$SkipBuilder,
    [switch]$SkipBuilderPackage,
    [switch]$SkipWebToApk,
    [switch]$SkipQuest,
    [switch]$RunManualHardwareGate
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $ProjectPath 'QuestionnaireConfigs\viscereality-maia2.config.json'
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "pipeline-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

function Get-SafeName {
    param([string]$Value, [string]$Fallback = "questionnaire")

    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return $Fallback
    }
    return $safe
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

$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Get-Content -LiteralPath $resolvedConfig -Encoding UTF8 -Raw | ConvertFrom-Json
$questionnaireId = Get-SafeName $config.questionnaireId
$questionnaireVersion = Get-SafeName $config.questionnaireVersion "0.0.0"
$artifactDir = Join-Path $ProjectPath ("artifacts\pipeline-validation\" + $RunId)
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

$builderStatus = if ($SkipBuilder) { "skipped" } else { "pending" }
$builderPackageSummaryPath = Join-Path $ProjectPath 'Builds\QuestionnaireBuilder-package-summary.json'
$webToApkStatus = if ($SkipBuilder -or $SkipWebToApk) { "skipped" } else { "pending" }
$webToApkRunId = "$RunId-web-to-apk"
$webToApkSummaryPath = Join-Path $ProjectPath ("artifacts\web-builder-output-apk\$webToApkRunId\web-builder-output-apk-summary.json")
$generatorRunId = "$RunId-generator"
$foregroundRunId = "render"
$generatorSummaryPath = Join-Path $ProjectPath ("artifacts\apk-generator\$generatorRunId\generator-summary.json")
$questOutputRoot = Join-Path $artifactDir 'quest-validation'
$questSummaryPath = Join-Path $questOutputRoot 'my-questionnaire-2d-validation-summary.json'
$foregroundOutputRoot = Join-Path $artifactDir 'fg'
$foregroundSummaryPath = Join-Path $foregroundOutputRoot "$foregroundRunId\render-wrapper-summary.json"
$manualHardwareSummaryPath = Join-Path $artifactDir 'manual-hardware\manual-hardware-gate-summary.json'
$manualHardwareStatus = if ($RunManualHardwareGate) { "pending" } else { "skipped" }

if (-not $SkipBuilder) {
    if ($SkipBuilderPackage) {
        Invoke-Required "Level 0 builder smoke" {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\validate-questionnaire-builder.ps1')
        }
    } else {
        Invoke-Required "Level 0 web builder package" {
            & powershell -NoProfile -ExecutionPolicy Bypass `
                -File (Join-Path $ProjectPath 'tools\publish-questionnaire-builder.ps1') `
                -ProjectPath $ProjectPath `
                -RunId "$RunId-builder"
        }
    }
    $builderStatus = "pass"

    if (-not $SkipWebToApk) {
        Invoke-Required "Level 0-2.5 web builder output to APK" {
            $webToApkArgs = @(
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                (Join-Path $ProjectPath 'tools\validate-web-builder-output-apk.ps1'),
                '-ProjectPath',
                $ProjectPath,
                '-ReferenceProjectPath',
                $ReferenceProjectPath,
                '-RunId',
                $webToApkRunId
            )
            if (-not $SkipQuest -and -not [string]::IsNullOrWhiteSpace($Serial)) {
                $webToApkArgs += @('-Serial', $Serial)
            }

            & powershell @webToApkArgs
        }
        $webToApkStatus = "pass"
    }
}

Invoke-Required "Levels 0-2.5 config, assets, tests, APK, render preview" {
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $ProjectPath 'tools\generate-questionnaire-apk.ps1') `
        -ConfigPath $resolvedConfig `
        -ReferenceProjectPath $ReferenceProjectPath `
        -RenderPreview `
        -RunId $generatorRunId
}

if (-not (Test-Path -LiteralPath $generatorSummaryPath)) {
    throw "Expected generator summary not found: $generatorSummaryPath"
}
$generatorSummary = Get-Content -LiteralPath $generatorSummaryPath -Raw | ConvertFrom-Json
$apkPath = if ($generatorSummary.apk) { [string]$generatorSummary.apk } else { Join-Path $ProjectPath ("Builds\$questionnaireId-$questionnaireVersion.apk") }
if (-not (Test-Path -LiteralPath $apkPath)) {
    throw "Expected generated APK not found: $apkPath"
}

$questStatus = "skipped"
if (-not $SkipQuest -and -not [string]::IsNullOrWhiteSpace($Serial)) {
    Invoke-Required "Level 4 Quest command replay/export" {
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $ProjectPath 'tools\quest-validate.ps1') `
            -Serial $Serial `
            -OutputRoot $questOutputRoot `
            -Apk $apkPath `
            -SkipBuild `
            -StopLegacyUnityApp `
            -LeaveForeground
    }

    Invoke-Required "Level 5 foreground-linked Android render pack" {
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $ProjectPath 'tools\render-questionnaire-visuals.ps1') `
            -ConfigPath $resolvedConfig `
            -ReferenceProjectPath $ReferenceProjectPath `
            -OutputRoot $foregroundOutputRoot `
            -RunId $foregroundRunId `
            -Serial $Serial `
            -CheckQuestForeground `
            -RequireQuestForeground `
            -LaunchBeforeForegroundCheck
    }

    if ($RunManualHardwareGate) {
        $manualArgs = @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            (Join-Path $ProjectPath 'tools\quest-manual-hardware-gate.ps1'),
            '-Serial',
            $Serial,
            '-Apk',
            $apkPath,
            '-OutputRoot',
            (Join-Path $artifactDir 'manual-hardware'),
            '-WaitSeconds',
            $ManualHardwareWaitSeconds,
            '-SkipInstall',
            '-StopLegacyUnityApp'
        )
        if (-not [string]::IsNullOrWhiteSpace($OperatorSignoffPath)) {
            $manualArgs += @('-OperatorSignoffPath', $OperatorSignoffPath, '-RequirePass')
        }

        Invoke-Required "Level 6 manual hardware input gate" {
            & powershell @manualArgs
        }

        if (Test-Path -LiteralPath $manualHardwareSummaryPath) {
            $manualHardwareStatus = (Get-Content -LiteralPath $manualHardwareSummaryPath -Raw | ConvertFrom-Json).status
        } else {
            $manualHardwareStatus = "missing-summary"
        }
    }

    $questStatus = "pass"
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.pipeline-validation.v1'
    status = 'pass'
    runId = $RunId
    questionnaireId = $config.questionnaireId
    questionnaireVersion = $config.questionnaireVersion
    configPath = $resolvedConfig
    artifactDir = $artifactDir
    builder = [ordered]@{
        status = $builderStatus
        packageSummary = if ((-not $SkipBuilder) -and (-not $SkipBuilderPackage)) { $builderPackageSummaryPath } else { $null }
        webToApkStatus = $webToApkStatus
        webToApkSummary = if ($webToApkStatus -eq 'pass') { $webToApkSummaryPath } else { $null }
    }
    generator = [ordered]@{
        status = 'pass'
        summary = $generatorSummaryPath
        apk = $apkPath
        renderSummary = $generatorSummary.renderSummary
    }
    quest = [ordered]@{
        status = $questStatus
        serial = if ([string]::IsNullOrWhiteSpace($Serial)) { $null } else { $Serial }
        validationSummary = if ($questStatus -eq 'pass') { $questSummaryPath } else { $null }
        foregroundRenderSummary = if ($questStatus -eq 'pass') { $foregroundSummaryPath } else { $null }
        manualHardwareStatus = $manualHardwareStatus
        manualHardwareSummary = if ($manualHardwareStatus -ne 'skipped') { $manualHardwareSummaryPath } else { $null }
    }
    completedAt = (Get-Date).ToString('o')
}

$summaryPath = Join-Path $artifactDir 'pipeline-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ""
Write-Host "Questionnaire pipeline validation written to $artifactDir"
Write-Host "Pipeline summary: $summaryPath"
