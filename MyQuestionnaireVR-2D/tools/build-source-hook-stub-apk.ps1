param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputApk = ""
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($OutputApk)) {
    $OutputApk = Join-Path $ProjectPath 'Builds\ViscerealitySourceHookStub.apk'
}

$gradle = Join-Path $ProjectPath 'gradlew.bat'
if (-not (Test-Path -LiteralPath $gradle)) {
    throw "Gradle wrapper not found: $gradle"
}

& $gradle --no-daemon --max-workers=1 :sourcehookstub:assembleDebug
if ($LASTEXITCODE -ne 0) {
    throw "sourcehookstub Gradle build failed with exit code $LASTEXITCODE"
}

$builtApk = Join-Path $ProjectPath 'sourcehookstub\build\outputs\apk\debug\sourcehookstub-debug.apk'
if (-not (Test-Path -LiteralPath $builtApk)) {
    throw "Built source hook stub APK not found: $builtApk"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputApk) | Out-Null
Copy-Item -LiteralPath $builtApk -Destination $OutputApk -Force

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.source-hook-stub-build.v1'
    status = 'pass'
    apk = (Resolve-Path -LiteralPath $OutputApk).Path
    bytes = (Get-Item -LiteralPath $OutputApk).Length
    sha256 = (Get-FileHash -LiteralPath $OutputApk -Algorithm SHA256).Hash
    completedAt = (Get-Date).ToString('o')
}
$summaryPath = [System.IO.Path]::ChangeExtension($OutputApk, '.build-summary.json')
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Source hook stub APK: $OutputApk"
Write-Host "Build summary: $summaryPath"
