param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [string]$ProjectPath = "",
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR",
    [string]$RunId = "",
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$RenderPreview
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Split-Path -Parent $PSScriptRoot
}

function Get-SafeName {
    param([string]$Value)

    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'questionnaire'
    }
    return $safe
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "generate-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Get-Content -LiteralPath $resolvedConfig -Encoding UTF8 -Raw | ConvertFrom-Json
$questionnaireId = Get-SafeName $config.questionnaireId
$questionnaireVersion = Get-SafeName $config.questionnaireVersion
$artifactDir = Join-Path $ProjectPath ("artifacts\apk-generator\" + $RunId)
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

$copiedConfig = Join-Path $artifactDir ([System.IO.Path]::GetFileName($resolvedConfig))
Copy-Item -LiteralPath $resolvedConfig -Destination $copiedConfig -Force

$validateConfigScript = Join-Path $ProjectPath 'tools\validate-questionnaire-config.ps1'
$applyScript = Join-Path $ProjectPath 'tools\apply-questionnaire-config.ps1'
$validateAssetsScript = Join-Path $ProjectPath 'tools\validate-questionnaire-assets.ps1'
& $validateConfigScript -ConfigPath $resolvedConfig -ReferenceProjectPath $ReferenceProjectPath | Out-Host
& $applyScript -ConfigPath $resolvedConfig -ReferenceProjectPath $ReferenceProjectPath | Out-Host
& $validateAssetsScript | Out-Host

$apkPath = $null
$apkSha256 = $null
if (-not $SkipBuild) {
    $buildArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $ProjectPath 'tools\build-apk.ps1'),
        '-ConfigPath',
        $resolvedConfig,
        '-ReferenceProjectPath',
        $ReferenceProjectPath
    )
    if ($SkipTests) {
        $buildArgs += '-SkipTests'
    }
    powershell @buildArgs | Out-Host
    $sourceApk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
    if (-not (Test-Path -LiteralPath $sourceApk)) {
        throw "Expected APK not found after build: $sourceApk"
    }

    $apkPath = Join-Path $ProjectPath ("Builds\" + $questionnaireId + "-" + $questionnaireVersion + ".apk")
    Copy-Item -LiteralPath $sourceApk -Destination $apkPath -Force
    $apkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
}

$renderSummary = $null
if ($RenderPreview) {
    $renderOutputRoot = Join-Path $artifactDir 'render-validation'
    powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $ProjectPath 'tools\render-questionnaire-visuals.ps1') `
        -ConfigPath $resolvedConfig `
        -ReferenceProjectPath $ReferenceProjectPath `
        -OutputRoot $renderOutputRoot `
        -RunId 'render' `
        -SkipAssetRefresh | Out-Host
    $renderSummary = Join-Path $renderOutputRoot 'render\render-summary.json'
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.apk-generator.v1'
    status = 'OK'
    runId = $RunId
    sourceConfig = $resolvedConfig
    copiedConfig = $copiedConfig
    questionnaireId = $config.questionnaireId
    questionnaireVersion = $config.questionnaireVersion
    artifactDir = $artifactDir
    apk = $apkPath
    apkSha256 = $apkSha256
    renderSummary = $renderSummary
    completedAt = (Get-Date).ToString('o')
}

$summaryPath = Join-Path $artifactDir 'generator-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Questionnaire APK generation artifacts written to $artifactDir"
if ($apkPath) {
    Write-Host "Generated APK: $apkPath"
}
Write-Host "Summary: $summaryPath"
