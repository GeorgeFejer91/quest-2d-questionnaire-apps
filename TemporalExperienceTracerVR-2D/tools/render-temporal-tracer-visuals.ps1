param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$GradleWrapper = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR-2D\gradlew.bat",
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$Sizes = "1280x800,900x800"
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "render-" + (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath "artifacts\temporal-tracer-render-validation\$RunId"
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

if (-not (Test-Path -LiteralPath $GradleWrapper)) {
    throw "Gradle wrapper not found: $GradleWrapper"
}

$jdk = Join-Path $UnityAndroidRoot 'OpenJDK'
if (Test-Path -LiteralPath $jdk) {
    $env:JAVA_HOME = $jdk
    $env:PATH = (Join-Path $jdk 'bin') + [IO.Path]::PathSeparator + $env:PATH
}

& $GradleWrapper -p $ProjectPath --no-daemon `
    "-DtemporalTracer.render.enabled=true" `
    "-DtemporalTracer.render.outputDir=$OutputRoot" `
    "-DtemporalTracer.render.runId=$RunId" `
    "-DtemporalTracer.render.sizes=$Sizes" `
    :app:testDebugUnitTest --tests org.mesmerprism.viscereality.temporaltracer2d.RenderTemporalTracerVisualsTest
if ($LASTEXITCODE -ne 0) {
    throw "Temporal tracer render validation failed with exit code $LASTEXITCODE"
}

$summary = Join-Path $OutputRoot 'render-summary.json'
if (-not (Test-Path -LiteralPath $summary)) {
    throw "Render summary was not produced: $summary"
}

Write-Host "Render artifacts: $OutputRoot"
Write-Host "Summary: $summary"
