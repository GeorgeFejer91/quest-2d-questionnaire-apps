param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ApkDirectory = "",
    [int]$WaitSeconds = 90,
    [int]$PollSeconds = 3,
    [int]$PictographicRepeats = 2,
    [int]$MaxScenarios = 0,
    [switch]$RestartServer,
    [switch]$SkipDryRun,
    [switch]$SkipBuild,
    [switch]$RequireQuestOnline
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "live-chainlink-stress-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath "artifacts\live-chainlink-stress\$RunId"
}

function Invoke-LoggedProcess {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$StepDir,
        [string]$SummaryFile = "",
        [bool]$AllowFailure = $false
    )

    New-Item -ItemType Directory -Force -Path $StepDir | Out-Null
    $stdout = Join-Path $StepDir 'stdout.txt'
    $stderr = Join-Path $StepDir 'stderr.txt'
    $started = Get-Date
    $argumentLine = ($Arguments | ForEach-Object {
        $arg = [string]$_
        if ($arg -match '[\s"]') { '"' + ($arg -replace '"', '\"') + '"' } else { $arg }
    }) -join ' '
    $process = Start-Process -FilePath $FilePath -ArgumentList $argumentLine -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $completed = Get-Date
    $summaryPath = if ([string]::IsNullOrWhiteSpace($SummaryFile)) { $null } else { Join-Path $StepDir $SummaryFile }
    if ($summaryPath -and -not (Test-Path -LiteralPath $summaryPath)) {
        $found = Get-ChildItem -LiteralPath $StepDir -Recurse -File -Filter $SummaryFile -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            Select-Object -First 1
        if ($found) { $summaryPath = $found.FullName }
    }

    $summaryStatus = $null
    if ($summaryPath -and (Test-Path -LiteralPath $summaryPath)) {
        try {
            $json = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
            if ($json.PSObject.Properties.Name -contains 'status') {
                $summaryStatus = [string]$json.status
            }
        } catch {}
    }

    $status = if ($process.ExitCode -eq 0) { 'pass' } else { if ($AllowFailure) { 'warn' } else { 'fail' } }
    if ($summaryStatus -eq 'fail' -and -not $AllowFailure) { $status = 'fail' }
    elseif ($summaryStatus -eq 'warn' -and $status -eq 'pass') { $status = 'warn' }

    return [ordered]@{
        name = $Name
        status = $status
        exitCode = $process.ExitCode
        allowFailure = $AllowFailure
        command = $FilePath + ' ' + $argumentLine
        startedAt = $started.ToUniversalTime().ToString('o')
        completedAt = $completed.ToUniversalTime().ToString('o')
        durationSeconds = [Math]::Round(($completed - $started).TotalSeconds, 3)
        stdout = $stdout
        stderr = $stderr
        summary = $summaryPath
        summaryStatus = $summaryStatus
    }
}

function Get-Json {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Add-ArgIfValue {
    param(
        [string[]]$Arguments,
        [string]$Name,
        [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        return $Arguments + @($Name, $Value)
    }
    return $Arguments
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$steps = @()

$readinessDir = Join-Path $OutputRoot '01-readiness'
$readinessArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $ProjectPath 'tools\quest-adb-readiness.ps1'),
    '-ProjectPath', $ProjectPath,
    '-OutputRoot', $readinessDir,
    '-RunId', 'readiness',
    '-WaitSeconds', ([string]$WaitSeconds),
    '-PollSeconds', ([string]$PollSeconds)
)
$readinessArgs = Add-ArgIfValue -Arguments $readinessArgs -Name '-Adb' -Value $Adb
$readinessArgs = Add-ArgIfValue -Arguments $readinessArgs -Name '-ExpectedSerial' -Value $Serial
if ($RestartServer) { $readinessArgs += '-RestartServer' }
if ($RequireQuestOnline) { $readinessArgs += '-RequireOnline' }

$steps += Invoke-LoggedProcess -Name 'quest-adb-readiness' -FilePath 'powershell' -Arguments $readinessArgs -StepDir $readinessDir -SummaryFile 'quest-adb-readiness-summary.json' -AllowFailure:(-not $RequireQuestOnline)
$readiness = Get-Json (($steps | Where-Object { $_.name -eq 'quest-adb-readiness' } | Select-Object -First 1).summary)
$targetSerial = ""
if ($readiness -and -not [string]::IsNullOrWhiteSpace([string]$readiness.targetSerial)) {
    $targetSerial = [string]$readiness.targetSerial
} elseif (-not [string]::IsNullOrWhiteSpace($Serial)) {
    $targetSerial = $Serial
}

if (-not $SkipDryRun) {
    $dryDir = Join-Path $OutputRoot '02-dryrun'
    $dryArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\stress-chainlink-scenario-batch.ps1'),
        '-ProjectPath', $ProjectPath,
        '-OutputRoot', $dryDir,
        '-PictographicRepeats', ([string]$PictographicRepeats),
        '-DryRun'
    )
    $dryArgs = Add-ArgIfValue -Arguments $dryArgs -Name '-ApkDirectory' -Value $ApkDirectory
    if ($MaxScenarios -gt 0) { $dryArgs += @('-MaxScenarios', ([string]$MaxScenarios)) }
    $steps += Invoke-LoggedProcess -Name 'chainlink-batch-dryrun' -FilePath 'powershell' -Arguments $dryArgs -StepDir $dryDir -SummaryFile 'chainlink-scenario-batch-summary.json'
}

$liveStep = $null
$questOnline = $readiness -and [string]$readiness.readiness -eq 'online' -and -not [string]::IsNullOrWhiteSpace($targetSerial)
if ($questOnline) {
    $liveDir = Join-Path $OutputRoot '03-live-device'
    $liveArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\stress-chainlink-scenario-batch.ps1'),
        '-ProjectPath', $ProjectPath,
        '-OutputRoot', $liveDir,
        '-Serial', $targetSerial,
        '-PictographicRepeats', ([string]$PictographicRepeats)
    )
    $liveArgs = Add-ArgIfValue -Arguments $liveArgs -Name '-Adb' -Value $Adb
    $liveArgs = Add-ArgIfValue -Arguments $liveArgs -Name '-ApkDirectory' -Value $ApkDirectory
    if ($MaxScenarios -gt 0) { $liveArgs += @('-MaxScenarios', ([string]$MaxScenarios)) }
    if ($SkipBuild) { $liveArgs += '-SkipBuild' }
    $liveStep = Invoke-LoggedProcess -Name 'chainlink-batch-live-device' -FilePath 'powershell' -Arguments $liveArgs -StepDir $liveDir -SummaryFile 'chainlink-scenario-batch-summary.json'
    $steps += $liveStep
} else {
    $steps += [ordered]@{
        name = 'chainlink-batch-live-device'
        status = 'skipped'
        reason = 'Quest ADB transport is not online; live install/launch/export stress was not attempted.'
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
}

$drySummary = Get-Json (($steps | Where-Object { $_.name -eq 'chainlink-batch-dryrun' } | Select-Object -First 1).summary)
$liveSummary = Get-Json (($steps | Where-Object { $_.name -eq 'chainlink-batch-live-device' } | Select-Object -First 1).summary)
$failCount = @($steps | Where-Object { $_.status -eq 'fail' }).Count
$dryRunPass = $SkipDryRun -or ($drySummary -and [string]$drySummary.status -eq 'pass')
$livePass = $liveSummary -and [string]$liveSummary.status -eq 'pass'

$status = if ($failCount -gt 0) {
    'fail'
} elseif ($livePass) {
    'pass'
} elseif (-not $questOnline -and $dryRunPass) {
    'device-pending'
} elseif ($dryRunPass) {
    'warn'
} else {
    'fail'
}

$recommendations = @()
if ($status -eq 'device-pending') {
    $recommendations += 'Quest was not visible to ADB. Keep the headset awake, accept USB debugging, check cable/port, then rerun this script.'
}
if ($status -eq 'pass') {
    $recommendations += 'Live ChainLink stress completed; inspect the pulled export/state artifacts in the live-device output folder.'
}
if ($readiness -and $readiness.recommendations) {
    $recommendations += @($readiness.recommendations)
}

$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.live-chainlink-stress.v1'
    status = $status
    runId = $RunId
    projectPath = $ProjectPath
    outputRoot = $OutputRoot
    requestedSerial = $Serial
    targetSerial = $targetSerial
    questReadiness = if ($readiness) { [string]$readiness.readiness } else { 'unknown' }
    questOnline = [bool]$questOnline
    pictographicRepeats = $PictographicRepeats
    dryRunScenarioTargets = if ($drySummary) { $drySummary.targetCount } else { $null }
    dryRunScenarioPasses = if ($drySummary) { $drySummary.passCount } else { $null }
    liveScenarioTargets = if ($liveSummary) { $liveSummary.targetCount } else { $null }
    liveScenarioPasses = if ($liveSummary) { $liveSummary.passCount } else { $null }
    recommendations = $recommendations
    steps = $steps
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'live-chainlink-stress-summary.json'
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]@{
    Status = $status
    QuestReadiness = $summary.questReadiness
    TargetSerial = $targetSerial
    DryRunScenarioTargets = $summary.dryRunScenarioTargets
    DryRunScenarioPasses = $summary.dryRunScenarioPasses
    LiveScenarioTargets = $summary.liveScenarioTargets
    LiveScenarioPasses = $summary.liveScenarioPasses
    Summary = $summaryPath
}

if ($status -eq 'fail' -or ($RequireQuestOnline -and $status -ne 'pass')) {
    throw "Live ChainLink stress did not pass. See $summaryPath"
}
