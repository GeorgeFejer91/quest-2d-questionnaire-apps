param(
    [string]$ProjectPath = $PSScriptRoot,
    [string]$Unity = "",
    [string]$TempProjectPath = "C:\qq3demo",
    [switch]$CleanTemp
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Resolve-UnityEditor {
    param([string]$RequestedUnity)

    if (-not [string]::IsNullOrWhiteSpace($RequestedUnity)) {
        if (Test-Path -LiteralPath $RequestedUnity) {
            return (Resolve-Path -LiteralPath $RequestedUnity).Path
        }
        throw "Unity editor not found: $RequestedUnity"
    }

    $command = Get-Command Unity.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source)) {
        return $command.Source
    }

    $hubRoot = Join-Path $env:USERPROFILE 'Unity\Hub\Editor'
    if (Test-Path -LiteralPath $hubRoot) {
        $candidate = Get-ChildItem -LiteralPath $hubRoot -Recurse -Filter Unity.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\Editor\\Unity\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw "Could not resolve Unity.exe. Pass -Unity with the full editor path."
}

$projectFull = (Resolve-Path -LiteralPath $ProjectPath).Path
$tempFull = [System.IO.Path]::GetFullPath($TempProjectPath)
if ([string]::IsNullOrWhiteSpace($tempFull) -or $tempFull.Length -lt 6) {
    throw "Refusing to use unsafe temp project path: $TempProjectPath"
}
if ($tempFull.StartsWith($projectFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Temp project path must not be inside the Unity source project."
}

if ($CleanTemp -and (Test-Path -LiteralPath $tempFull)) {
    $resolvedTemp = (Resolve-Path -LiteralPath $tempFull).Path
    if ($resolvedTemp -ne $tempFull) {
        throw "Unexpected temp project path: $resolvedTemp"
    }
    Remove-Item -LiteralPath $tempFull -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $tempFull | Out-Null
$excludeDirs = @('Library', 'Temp', 'Logs', 'Builds', 'obj', '.gradle')
$excludeFiles = @('*.csproj', '*.sln')
robocopy $projectFull $tempFull /MIR /XD $excludeDirs /XF $excludeFiles /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

$unityEditor = Resolve-UnityEditor -RequestedUnity $Unity
$logDir = Join-Path $tempFull 'Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'build-android-shortpath.log'

& $unityEditor --no-banner --non-interactive build $tempFull --target Android --execute-method QuestQuestionnaireCircleDemoProjectSetup.BuildAndroid --log-file $log --no-tail
if ($LASTEXITCODE -ne 0) {
    throw "Unity build failed with exit code $LASTEXITCODE. See log: $log"
}

$sourceApk = Join-Path $tempFull 'Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk'
if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Unity reported success, but the APK was not found: $sourceApk"
}

$destDir = Join-Path $projectFull 'Builds'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$destApk = Join-Path $destDir 'QuestQuestionnaireThreeCircleTriggerDemo.apk'
Copy-Item -LiteralPath $sourceApk -Destination $destApk -Force

Get-Item -LiteralPath $destApk | Select-Object FullName,@{Name='SizeMB';Expression={[math]::Round($_.Length / 1MB, 2)}},LastWriteTime
