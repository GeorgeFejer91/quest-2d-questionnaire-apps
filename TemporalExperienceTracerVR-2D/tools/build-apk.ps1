param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$GradleWrapper = "",
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer",
    [string]$OutputApk = ""
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($GradleWrapper)) {
    $GradleWrapper = Join-Path $ProjectPath 'gradlew.bat'
}

if (-not (Test-Path -LiteralPath $GradleWrapper)) {
    throw "Gradle wrapper not found: $GradleWrapper"
}

$jdk = Join-Path $UnityAndroidRoot 'OpenJDK'
if (Test-Path -LiteralPath $jdk) {
    $env:JAVA_HOME = $jdk
    $env:PATH = (Join-Path $jdk 'bin') + [IO.Path]::PathSeparator + $env:PATH
}

& $GradleWrapper -p $ProjectPath --no-daemon :app:assembleDebug
if ($LASTEXITCODE -ne 0) {
    throw "Gradle APK build failed with exit code $LASTEXITCODE"
}

if ([string]::IsNullOrWhiteSpace($OutputApk)) {
    $OutputApk = Join-Path $ProjectPath 'Builds\TemporalExperienceTracerVR-2D.apk'
}

$source = Join-Path $ProjectPath 'app\build\outputs\apk\debug\app-debug.apk'
if (-not (Test-Path -LiteralPath $source)) {
    throw "Expected APK not found: $source"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputApk) | Out-Null
Copy-Item -LiteralPath $source -Destination $OutputApk -Force
Write-Host "Built APK: $OutputApk"
