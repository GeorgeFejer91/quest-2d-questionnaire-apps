param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$GradleWrapper = "",
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$Sizes = "1280x800,900x800"
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "render-" + (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath "artifacts\temporal-tracer-render-validation\$RunId"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($GradleWrapper)) {
    $GradleWrapper = Join-Path $ProjectPath 'gradlew.bat'
}
$GradleWrapper = [System.IO.Path]::GetFullPath($GradleWrapper)

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
    :app:testDebugUnitTest --tests org.questquestionnaire.temporaltracer2d.RenderTemporalTracerVisualsTest
if ($LASTEXITCODE -ne 0) {
    throw "Temporal tracer render validation failed with exit code $LASTEXITCODE"
}

$summary = Join-Path $OutputRoot 'render-summary.json'
if (-not (Test-Path -LiteralPath $summary)) {
    throw "Render summary was not produced: $summary"
}

Write-Host "Render artifacts: $OutputRoot"
Write-Host "Summary: $summary"
