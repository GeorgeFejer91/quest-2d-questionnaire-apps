param(
    [string]$UnityProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\Viscereality\Viscereality",
    [string]$UnityEditorPath = "",
    [string]$ScenePath = "Assets\Scenes\Main Questionnaire.unity",
    [string]$PackageId = "com.Viscereality.ViscerealityPeriPersonalSpaceRight.SourceHook",
    [string]$ProductName = "Viscereality Peripersonal Source Hook Candidate",
    [string]$OutputApk = "",
    [string]$OutputRoot = "",
    [switch]$Development,
    [switch]$SkipPreflight,
    [switch]$SkipCandidateAudit,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Find-UnityEditor {
    if (-not [string]::IsNullOrWhiteSpace($UnityEditorPath)) {
        return (Resolve-Path -LiteralPath $UnityEditorPath -ErrorAction Stop).Path
    }

    $projectVersionPath = Join-Path $UnityProjectPath 'ProjectSettings\ProjectVersion.txt'
    $projectUnityVersion = ''
    if (Test-Path -LiteralPath $projectVersionPath) {
        $projectVersionText = Get-Content -LiteralPath $projectVersionPath -Raw
        if ($projectVersionText -match 'm_EditorVersion:\s*(.+)') {
            $projectUnityVersion = $Matches[1].Trim()
        }
    }

    $hubRoots = @(
        'C:\Users\cogpsy-vrlab\Unity\Hub\Editor',
        (Join-Path $env:USERPROFILE 'Unity\Hub\Editor'),
        'C:\Program Files\Unity\Hub\Editor',
        (Join-Path $env:LOCALAPPDATA 'Programs\Unity\Hub\Editor'),
        (Join-Path $env:LOCALAPPDATA 'Unity\Hub\Editor')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    if (-not [string]::IsNullOrWhiteSpace($projectUnityVersion)) {
        foreach ($hubRoot in $hubRoots) {
            $versioned = Join-Path $hubRoot "$projectUnityVersion\Editor\Unity.exe"
            if (Test-Path -LiteralPath $versioned) {
                return $versioned
            }
        }
    }

    foreach ($hubRoot in $hubRoots) {
        if (Test-Path -LiteralPath $hubRoot) {
            $candidate = Get-ChildItem -LiteralPath $hubRoot -Directory |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'Editor\Unity.exe' } |
                Where-Object { Test-Path -LiteralPath $_ } |
                Select-Object -First 1
            if ($candidate) {
                return $candidate
            }
        }
    }

    $cmd = Get-Command Unity.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($cmd.Source)
        if ($versionInfo.ProductName -notmatch 'Bun') {
            return $cmd.Source
        }
    }

    throw "Unity.exe not found. Pass -UnityEditorPath explicitly."
}

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$projectPath = (Resolve-Path -LiteralPath $UnityProjectPath -ErrorAction Stop).Path
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $runId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $OutputRoot = Join-Path $projectRoot "artifacts\unity-source-hook-build\$runId"
}
$outputRootFull = Get-FullPath $OutputRoot
New-Item -ItemType Directory -Force -Path $outputRootFull | Out-Null

if ([string]::IsNullOrWhiteSpace($OutputApk)) {
    $OutputApk = Join-Path $projectRoot 'Builds\ViscerealityPeripersonalSourceHookCandidate.apk'
}
$outputApkFull = Get-FullPath $OutputApk
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputApkFull) | Out-Null

$sceneUnityPath = $ScenePath.Replace('/', '\')
$sceneFull = if ([System.IO.Path]::IsPathRooted($sceneUnityPath)) {
    Get-FullPath $sceneUnityPath
} else {
    Get-FullPath (Join-Path $projectPath $sceneUnityPath)
}
if (-not (Test-Path -LiteralPath $sceneFull)) {
    throw "Scene not found: $sceneFull"
}

$preflightPath = Join-Path $outputRootFull 'unity-source-hook-preflight.json'
$candidateAuditPath = Join-Path $outputRootFull 'unity-source-hook-candidates.json'
$logPath = Join-Path $outputRootFull 'unity-source-hook-build.log'

if (-not $SkipPreflight) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tools\unity-source-hook-preflight.ps1') `
        -UnityProjectPath $projectPath `
        -OutputPath $preflightPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Unity source-hook preflight failed with exit code $LASTEXITCODE"
    }
}

if (-not $SkipCandidateAudit) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tools\audit-unity-source-hook-candidates.ps1') `
        -UnityProjectPath $projectPath `
        -TargetPackage $PackageId `
        -OutputPath $candidateAuditPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Unity source-hook candidate audit failed with exit code $LASTEXITCODE"
    }
}

$unity = Find-UnityEditor
$sceneArg = $sceneUnityPath.Replace('\', '/')
$arguments = @(
    '-batchmode',
    '-quit',
    '-projectPath', $projectPath,
    '-executeMethod', 'QuestSourceHookBuild.BuildFromCommandLine',
    '-chainBuildOutput', $outputApkFull,
    '-chainBuildScene', $sceneArg,
    '-chainPackageId', $PackageId,
    '-chainProductName', $ProductName,
    '-logFile', $logPath
)
if ($Development) {
    $arguments += '-chainDevelopment'
}

$summary = [ordered]@{
    schemaVersion = 'viscereality.unity-source-hook-build-wrapper.v1'
    status = if ($DryRun) { 'dry-run' } else { 'pending' }
    unityEditor = $unity
    unityProjectPath = $projectPath
    scene = $sceneArg
    packageId = $PackageId
    productName = $ProductName
    outputApk = $outputApkFull
    outputRoot = $outputRootFull
    preflight = if ($SkipPreflight) { $null } else { $preflightPath }
    candidateAudit = if ($SkipCandidateAudit) { $null } else { $candidateAuditPath }
    log = $logPath
    command = @($unity) + $arguments
    startedAt = (Get-Date).ToString('o')
}

$summaryPath = Join-Path $outputRootFull 'unity-source-hook-build-wrapper-summary.json'
if ($DryRun) {
    $summary.completedAt = (Get-Date).ToString('o')
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-Host "Dry run summary: $summaryPath"
    exit 0
}

& $unity @arguments | Out-Host
$exitCode = $LASTEXITCODE
$summary.exitCode = $exitCode
$summary.completedAt = (Get-Date).ToString('o')

if ($exitCode -ne 0) {
    $summary.status = 'fail'
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    throw "Unity source-hook build failed with exit code $exitCode. Log: $logPath"
}

if (-not (Test-Path -LiteralPath $outputApkFull)) {
    $summary.status = 'fail'
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    throw "Unity source-hook build reported success but APK was not found: $outputApkFull"
}

$summary.status = 'pass'
$summary.apkBytes = (Get-Item -LiteralPath $outputApkFull).Length
$summary.apkSha256 = (Get-FileHash -LiteralPath $outputApkFull -Algorithm SHA256).Hash
$unityBuildSummary = "$outputApkFull.build-summary.json"
if (Test-Path -LiteralPath $unityBuildSummary) {
    $summary.unityBuildSummary = $unityBuildSummary
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Unity source-hook APK: $outputApkFull"
Write-Host "Build wrapper summary: $summaryPath"
