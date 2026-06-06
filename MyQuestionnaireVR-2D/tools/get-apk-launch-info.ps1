param(
    [Parameter(Mandatory = $true)]
    [string]$Apk,
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Apk)) {
    throw "APK not found: $Apk"
}

$buildToolsRoot = Join-Path $UnityAndroidRoot 'SDK\build-tools'
$aapt = Get-ChildItem -LiteralPath $buildToolsRoot -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $aapt) {
    throw "Could not find aapt.exe under $buildToolsRoot"
}

$badging = & $aapt.FullName dump badging $Apk 2>&1
if ($LASTEXITCODE -ne 0) {
    $badging | Write-Host
    throw "aapt dump badging failed."
}

$packageLine = $badging | Select-String -Pattern "^package:" | Select-Object -First 1
$activityLine = $badging | Select-String -Pattern "^launchable-activity:" | Select-Object -First 1
$package = if ($packageLine -and $packageLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
$activity = if ($activityLine -and $activityLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }

[pscustomobject]@{
    Apk = (Resolve-Path -LiteralPath $Apk).Path
    Package = $package
    Activity = $activity
    ChainPlanTargetPackage = $package
    ChainPlanTargetActivity = $activity
} | Format-List
