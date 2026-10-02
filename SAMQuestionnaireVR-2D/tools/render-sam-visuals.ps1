param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$GradleWrapper = "",
    [string]$UnityAndroidRoot = (Join-Path $env:USERPROFILE 'Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer'),
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
    $OutputRoot = Join-Path $ProjectPath "artifacts\sam-render-validation\$RunId"
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
    "-Dsam.render.enabled=true" `
    "-Dsam.render.outputDir=$OutputRoot" `
    "-Dsam.render.runId=$RunId" `
    "-Dsam.render.sizes=$Sizes" `
    :app:testDebugUnitTest --tests org.questquestionnaire.sam2d.RenderSamVisualsTest
if ($LASTEXITCODE -ne 0) {
    throw "SAM render validation failed with exit code $LASTEXITCODE"
}

$summary = Join-Path $OutputRoot 'render-summary.json'
if (-not (Test-Path -LiteralPath $summary)) {
    throw "Render summary was not produced: $summary"
}

$renderSummary = Get-Content -LiteralPath $summary -Raw -Encoding UTF8 | ConvertFrom-Json
$failures = @($renderSummary.renders | Where-Object { $_.status -eq 'fail' })
if ($failures.Count -gt 0) {
    throw "SAM render validation has $($failures.Count) failing render(s). See $summary"
}

Write-Host "Render artifacts: $OutputRoot"
Write-Host "Summary: $summary"
