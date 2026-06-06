param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ApkDirectory = "",
    [string]$OutputRoot = "",
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer",
    [int]$PictographicRepeats = 2,
    [int]$MaxScenarios = 0,
    [switch]$IncludeCoreApks,
    [switch]$DryRun,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($ApkDirectory)) {
    $packagedApkDirectory = Join-Path $ProjectPath 'apks'
    if (Test-Path -LiteralPath $packagedApkDirectory) {
        $ApkDirectory = $packagedApkDirectory
    } else {
        $ApkDirectory = Join-Path $ProjectPath 'Builds'
    }
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\chainlink-scenario-batch\" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
}

function Resolve-Aapt {
    $buildToolsRoot = Join-Path $UnityAndroidRoot 'SDK\build-tools'
    $aapt = Get-ChildItem -LiteralPath $buildToolsRoot -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $aapt) { throw "Could not find aapt.exe under $buildToolsRoot" }
    return $aapt.FullName
}

function Get-ApkInfo {
    param(
        [string]$Apk,
        [string]$Aapt
    )

    $badging = & $Aapt dump badging $Apk 2>&1
    $exitCode = $LASTEXITCODE
    $package = ''
    $activity = ''
    $label = ''
    if ($exitCode -eq 0) {
        $packageLine = $badging | Select-String -Pattern "^package:" | Select-Object -First 1
        $activityLine = $badging | Select-String -Pattern "^launchable-activity:" | Select-Object -First 1
        $labelLine = $badging | Select-String -Pattern "^application-label:" | Select-Object -First 1
        $package = if ($packageLine -and $packageLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
        $activity = if ($activityLine -and $activityLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
        $label = if ($labelLine -and $labelLine.ToString() -match "'([^']*)'") { $Matches[1] } else { "" }
    }

    return [ordered]@{
        apk = (Resolve-Path -LiteralPath $Apk).Path
        fileName = [System.IO.Path]::GetFileName($Apk)
        bytes = (Get-Item -LiteralPath $Apk).Length
        sha256 = (Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash
        aaptExitCode = $exitCode
        package = $package
        activity = $activity
        label = $label
        badgingPreview = @($badging | Select-Object -First 20)
    }
}

function Get-SafeStem {
    param([string]$Value)
    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'scenario' }
    if ($safe.Length -gt 80) { return $safe.Substring(0, 80).Trim('-') }
    return $safe
}

function Get-ShortRunName {
    param(
        [int]$Index,
        [string]$PackageName,
        [string]$Label
    )

    $source = if (-not [string]::IsNullOrWhiteSpace($PackageName)) { $PackageName } else { $Label }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($source)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    $hash = -join ($hashBytes[0..3] | ForEach-Object { $_.ToString('x2') })
    return "{0:00}-{1}" -f $Index, $hash
}

function Is-CorePackage {
    param([string]$PackageName)
    $corePackages = @(
        'org.viscereality.questionnaires2d',
        'org.viscereality.chainlink',
        'org.viscereality.orchestrator',
        'org.viscereality.chainhookwrapper'
    )
    return $corePackages -contains $PackageName
}

function Get-ArgumentLine {
    param([string[]]$Arguments)
    return ($Arguments | ForEach-Object {
        $arg = [string]$_
        if ($arg -match '[\s"]') { '"' + ($arg -replace '"', '\"') + '"' } else { $arg }
    }) -join ' '
}

$validator = Join-Path $ProjectPath 'tools\quest-chainlink-plan-validate.ps1'
if (-not (Test-Path -LiteralPath $validator)) {
    throw "ChainLink plan validator not found: $validator"
}
if (-not (Test-Path -LiteralPath $ApkDirectory)) {
    throw "APK directory not found: $ApkDirectory"
}
if (-not $DryRun -and [string]::IsNullOrWhiteSpace($Serial)) {
    throw "Device batch mode requires -Serial. Use -DryRun for host-only scenario coverage."
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$aapt = Resolve-Aapt
$apkFiles = @(Get-ChildItem -LiteralPath $ApkDirectory -File -Filter '*.apk' | Sort-Object Name)

$discoveries = @()
foreach ($apk in $apkFiles) {
    $info = Get-ApkInfo -Apk $apk.FullName -Aapt $aapt
    $skipReasons = @()
    if ($info.aaptExitCode -ne 0) { $skipReasons += 'aapt-failed' }
    if ([string]::IsNullOrWhiteSpace($info.package)) { $skipReasons += 'missing-package' }
    if ([string]::IsNullOrWhiteSpace($info.activity)) { $skipReasons += 'missing-launchable-activity' }
    if (-not $IncludeCoreApks -and (Is-CorePackage $info.package)) { $skipReasons += 'core-apk' }
    $info['skipReasons'] = $skipReasons
    $discoveries += [pscustomobject]$info
}

$targets = @($discoveries | Where-Object { @($_.skipReasons).Count -eq 0 })
if ($MaxScenarios -gt 0) {
    $targets = @($targets | Select-Object -First $MaxScenarios)
}

$runs = @()
$index = 0
foreach ($target in $targets) {
    $index++
    $targetName = if (-not [string]::IsNullOrWhiteSpace([string]$target.label)) { [string]$target.label } else { [string]$target.package }
    $runName = Get-ShortRunName -Index $index -PackageName ([string]$target.package) -Label $targetName
    $runDir = Join-Path $OutputRoot $runName
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $stdout = Join-Path $runDir 'validator-stdout.txt'
    $stderr = Join-Path $runDir 'validator-stderr.txt'

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $validator,
        '-ProjectPath', $ProjectPath,
        '-TargetApk', $target.apk,
        '-PictographicRepeats', $PictographicRepeats,
        '-OutputRoot', $runDir
    )
    if ($DryRun) {
        $args += '-DryRun'
    } else {
        $args += @('-Serial', $Serial, '-InstallTarget')
        if (-not [string]::IsNullOrWhiteSpace($Adb)) {
            $args += @('-Adb', $Adb)
        }
        if ($SkipBuild) {
            $args += '-SkipBuild'
        }
    }

    $process = Start-Process -FilePath 'powershell' -ArgumentList (Get-ArgumentLine $args) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $summaryPath = Join-Path $runDir 'quest-chainlink-plan-validation-summary.json'
    $runStatus = if ($process.ExitCode -eq 0) { 'pass' } else { 'fail' }
    $expectedExports = $null
    $plannedNextBlockCommands = $null
    if (Test-Path -LiteralPath $summaryPath) {
        try {
            $runSummary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
            $runStatus = [string]$runSummary.status
            $expectedExports = $runSummary.expectedExports
            $plannedNextBlockCommands = if ($DryRun) { $runSummary.plannedNextBlockCommands } else { $runSummary.sentNextBlockCommands }
        } catch {}
    }

    $runs += [ordered]@{
        index = $index
        status = $runStatus
        exitCode = $process.ExitCode
        package = $target.package
        activity = $target.activity
        label = $target.label
        apk = $target.apk
        outputRoot = $runDir
        summary = if (Test-Path -LiteralPath $summaryPath) { $summaryPath } else { $null }
        expectedExports = $expectedExports
        nextBlockCommands = $plannedNextBlockCommands
    }
}

$skipped = @($discoveries | Where-Object { @($_.skipReasons).Count -gt 0 })
$failedRuns = @($runs | Where-Object { $_.status -ne 'pass' })
$status = if ($failedRuns.Count -eq 0) { 'pass' } else { 'fail' }

$summary = [ordered]@{
    schemaVersion = 'viscereality.chainlink-scenario-batch.v1'
    status = $status
    dryRun = [bool]$DryRun
    projectPath = $ProjectPath
    apkDirectory = (Resolve-Path -LiteralPath $ApkDirectory).Path
    outputRoot = $OutputRoot
    serial = $Serial
    pictographicRepeats = $PictographicRepeats
    discoveredApkCount = $discoveries.Count
    targetCount = $targets.Count
    skippedCount = $skipped.Count
    passCount = @($runs | Where-Object { $_.status -eq 'pass' }).Count
    failCount = $failedRuns.Count
    discoveries = $discoveries
    runs = $runs
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'chainlink-scenario-batch-summary.json'
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]@{
    Status = $status
    DryRun = [bool]$DryRun
    Discovered = $discoveries.Count
    Targets = $targets.Count
    Passed = $summary.passCount
    Failed = $summary.failCount
    Skipped = $skipped.Count
    Summary = $summaryPath
}

if ($status -ne 'pass') {
    throw "ChainLink scenario batch stress failed. See $summaryPath"
}
