param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputApk = ""
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($OutputApk)) {
    $OutputApk = Join-Path $ProjectPath 'Builds\QuestQuestionnaireChainLink.apk'
}

$gradle = Join-Path $ProjectPath 'gradlew.bat'
if (-not (Test-Path -LiteralPath $gradle)) {
    throw "Gradle wrapper not found: $gradle"
}

& $gradle --no-daemon --max-workers=1 :chainlink:testDebugUnitTest :chainlink:assembleDebug
if ($LASTEXITCODE -ne 0) {
    throw "ChainLink Gradle build failed with exit code $LASTEXITCODE"
}

$builtApk = Join-Path $ProjectPath 'chainlink\build\outputs\apk\debug\chainlink-debug.apk'
if (-not (Test-Path -LiteralPath $builtApk)) {
    throw "Built ChainLink APK not found: $builtApk"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputApk) | Out-Null
Copy-Item -LiteralPath $builtApk -Destination $OutputApk -Force

$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.chainlink-build.v1'
    status = 'pass'
    apk = (Resolve-Path -LiteralPath $OutputApk).Path
    bytes = (Get-Item -LiteralPath $OutputApk).Length
    sha256 = (Get-FileHash -LiteralPath $OutputApk -Algorithm SHA256).Hash
    completedAt = (Get-Date).ToString('o')
}
$summaryPath = [System.IO.Path]::ChangeExtension($OutputApk, '.build-summary.json')
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "ChainLink APK: $OutputApk"
Write-Host "Build summary: $summaryPath"
