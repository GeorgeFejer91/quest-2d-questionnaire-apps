param(
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$javaHome = Join-Path $UnityAndroidRoot 'OpenJDK'
$sdk = Join-Path $UnityAndroidRoot 'SDK'
if (-not (Test-Path -LiteralPath (Join-Path $javaHome 'bin\java.exe'))) {
    throw "Unity OpenJDK not found under: $javaHome"
}
if (-not (Test-Path -LiteralPath $sdk)) {
    throw "Unity Android SDK not found under: $sdk"
}

$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:UNITY_ANDROID_ROOT = $UnityAndroidRoot

$localProperties = Join-Path $ProjectPath 'local.properties'
$sdkForward = $sdk -replace '\\', '/'
[System.IO.File]::WriteAllText($localProperties, "sdk.dir=$sdkForward`n", [System.Text.UTF8Encoding]::new($false))

Push-Location $ProjectPath
try {
    & .\gradlew.bat --no-daemon --max-workers=1 :hookwrapper:assembleDebug
    if ($LASTEXITCODE -ne 0) {
        throw "Hook wrapper APK build failed."
    }
}
finally {
    Pop-Location
}

$sourceApk = Join-Path $ProjectPath 'hookwrapper\build\outputs\apk\debug\hookwrapper-debug.apk'
if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Expected hook wrapper APK not found: $sourceApk"
}

$builds = Join-Path $ProjectPath 'Builds'
New-Item -ItemType Directory -Force -Path $builds | Out-Null
$targetApk = Join-Path $builds 'ViscerealityChainHookWrapper.apk'
Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force

[pscustomobject]@{
    Apk = $targetApk
    SizeBytes = (Get-Item -LiteralPath $targetApk).Length
    SHA256 = (Get-FileHash -LiteralPath $targetApk -Algorithm SHA256).Hash
    Status = 'OK'
} | Format-List
