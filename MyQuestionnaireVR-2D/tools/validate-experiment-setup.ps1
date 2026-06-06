param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$Serial = "",
    [string]$Adb = "",
    [int]$PictographicRepeats = 2,
    [switch]$Quick,
    [switch]$SkipQuestionnaireBuild,
    [switch]$SkipChainLinkBuild,
    [switch]$SkipRender,
    [switch]$SkipBuilderSmoke,
    [switch]$SkipPublish,
    [switch]$RequireQuestOnline,
    [switch]$RunLiveDeviceBatch
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "experiment-setup-validation-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath "artifacts\experiment-setup-validation\$RunId"
}

function Resolve-Node {
    $candidates = @(
        "C:\Users\cogpsy-vrlab\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe",
        "C:\Users\cogpsy-vrlab\.cache\codex-runtimes\codex-primary-runtime\node\bin\node.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $command = Get-Command node -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return ""
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$StepDir,
        [bool]$AllowFailure = $false,
        [string]$SummaryFile = ""
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
    $status = if ($process.ExitCode -eq 0) { 'pass' } else { if ($AllowFailure) { 'warn' } else { 'fail' } }
    $summaryPath = if ([string]::IsNullOrWhiteSpace($SummaryFile)) { $null } else { Join-Path $StepDir $SummaryFile }
    if ($summaryPath -and -not (Test-Path -LiteralPath $summaryPath)) {
        $foundSummary = Get-ChildItem -LiteralPath $StepDir -Recurse -File -Filter $SummaryFile -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            Select-Object -First 1
        if ($foundSummary) {
            $summaryPath = $foundSummary.FullName
        }
    }
    $summaryStatus = $null
    if ($summaryPath -and (Test-Path -LiteralPath $summaryPath)) {
        try {
            $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
            if ($summary.PSObject.Properties.Name -contains 'status') {
                $summaryStatus = [string]$summary.status
                if ($summaryStatus -eq 'fail' -and -not $AllowFailure) { $status = 'fail' }
                elseif ($summaryStatus -eq 'warn' -and $status -eq 'pass') { $status = 'warn' }
            }
        } catch {}
    }

    return [ordered]@{
        name = $Name
        status = $status
        allowFailure = $AllowFailure
        exitCode = $process.ExitCode
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

function Get-JsonStatus {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Add-SkippedStep {
    param([string]$Name, [string]$Reason)
    return [ordered]@{
        name = $Name
        status = 'skipped'
        reason = $Reason
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$steps = @()

$adbReadinessDir = Join-Path $OutputRoot '01-adb-readiness'
$adbArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $ProjectPath 'tools\quest-adb-readiness.ps1'),
    '-ProjectPath', $ProjectPath,
    '-OutputRoot', $adbReadinessDir,
    '-RunId', 'adb-readiness',
    '-WaitSeconds', '3',
    '-PollSeconds', '1'
)
if (-not [string]::IsNullOrWhiteSpace($Adb)) { $adbArgs += @('-Adb', $Adb) }
if (-not [string]::IsNullOrWhiteSpace($Serial)) { $adbArgs += @('-ExpectedSerial', $Serial) }
if ($RequireQuestOnline -or $RunLiveDeviceBatch) { $adbArgs += '-RequireOnline' }
$steps += Invoke-Step -Name 'quest-adb-readiness' -FilePath 'powershell' -Arguments $adbArgs -StepDir $adbReadinessDir -AllowFailure:(-not ($RequireQuestOnline -or $RunLiveDeviceBatch)) -SummaryFile 'quest-adb-readiness-summary.json'
$initialAdbSummary = Get-JsonStatus (($steps | Where-Object { $_.name -eq 'quest-adb-readiness' } | Select-Object -First 1).summary)
if ($RunLiveDeviceBatch -and [string]::IsNullOrWhiteSpace($Serial) -and $initialAdbSummary -and -not [string]::IsNullOrWhiteSpace([string]$initialAdbSummary.targetSerial)) {
    $Serial = [string]$initialAdbSummary.targetSerial
}

if ($Quick -or $SkipQuestionnaireBuild) {
    $steps += Add-SkippedStep -Name 'questionnaire-build' -Reason 'Skipped by -Quick or -SkipQuestionnaireBuild.'
} else {
    $dir = Join-Path $OutputRoot '02-questionnaire-build'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\build-apk.ps1'),
        '-ProjectPath', $ProjectPath
    )
    $steps += Invoke-Step -Name 'questionnaire-build' -FilePath 'powershell' -Arguments $args -StepDir $dir
}

if ($SkipChainLinkBuild) {
    $steps += Add-SkippedStep -Name 'chainlink-build' -Reason 'Skipped by -SkipChainLinkBuild.'
} else {
    $dir = Join-Path $OutputRoot '03-chainlink-build'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\build-chainlink-apk.ps1'),
        '-ProjectPath', $ProjectPath
    )
    $steps += Invoke-Step -Name 'chainlink-build' -FilePath 'powershell' -Arguments $args -StepDir $dir
}

$dir = Join-Path $OutputRoot '04-unity-hook-validation'
$args = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $ProjectPath 'tools\validate-unity-chainlink-hook.ps1'),
    '-ProjectPath', $ProjectPath,
    '-OutputRoot', $dir,
    '-RunId', 'unity-hook'
)
$steps += Invoke-Step -Name 'unity-hook-validation' -FilePath 'powershell' -Arguments $args -StepDir $dir -SummaryFile 'unity-chainlink-hook-validation-summary.json'

if ($Quick -or $SkipRender) {
    $steps += Add-SkippedStep -Name 'android-render-preview' -Reason 'Skipped by -Quick or -SkipRender.'
} else {
    $dir = Join-Path $OutputRoot '05-android-render-preview'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\render-questionnaire-visuals.ps1'),
        '-ProjectPath', $ProjectPath,
        '-OutputRoot', $dir,
        '-RunId', 'render-preview'
    )
    $steps += Invoke-Step -Name 'android-render-preview' -FilePath 'powershell' -Arguments $args -StepDir $dir -SummaryFile 'render-summary.json'
}

if ($SkipBuilderSmoke) {
    $steps += Add-SkippedStep -Name 'builder-smoke' -Reason 'Skipped by -SkipBuilderSmoke.'
} else {
    $builderSmoke = Join-Path $ProjectPath 'tools\questionnaire-config-editor\builder-smoke-test.js'
    $node = Resolve-Node
    if ([string]::IsNullOrWhiteSpace($node) -or -not (Test-Path -LiteralPath $builderSmoke)) {
        $steps += Add-SkippedStep -Name 'builder-smoke' -Reason 'Node or builder smoke script not available in this layout.'
    } else {
        $dir = Join-Path $OutputRoot '06-builder-smoke'
        $args = @($builderSmoke, '--output-dir', $dir)
        $steps += Invoke-Step -Name 'builder-smoke' -FilePath $node -Arguments $args -StepDir $dir -SummaryFile 'builder-smoke-summary.json'
    }
}

$dir = Join-Path $OutputRoot '07-chainlink-batch-dryrun'
$args = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $ProjectPath 'tools\stress-chainlink-scenario-batch.ps1'),
    '-ProjectPath', $ProjectPath,
    '-OutputRoot', $dir,
    '-PictographicRepeats', $PictographicRepeats,
    '-DryRun'
)
$steps += Invoke-Step -Name 'chainlink-batch-dryrun' -FilePath 'powershell' -Arguments $args -StepDir $dir -SummaryFile 'chainlink-scenario-batch-summary.json'

if ($RunLiveDeviceBatch) {
    $dir = Join-Path $OutputRoot '08-chainlink-batch-device'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\stress-chainlink-scenario-batch.ps1'),
        '-ProjectPath', $ProjectPath,
        '-OutputRoot', $dir,
        '-PictographicRepeats', $PictographicRepeats,
        '-Serial', $Serial,
        '-SkipBuild'
    )
    if (-not [string]::IsNullOrWhiteSpace($Adb)) { $args += @('-Adb', $Adb) }
    $steps += Invoke-Step -Name 'chainlink-batch-device' -FilePath 'powershell' -Arguments $args -StepDir $dir -SummaryFile 'chainlink-scenario-batch-summary.json'
} else {
    $steps += Add-SkippedStep -Name 'chainlink-batch-device' -Reason 'Skipped unless -RunLiveDeviceBatch is supplied.'
}

if ($SkipPublish) {
    $steps += Add-SkippedStep -Name 'publish-experiment-chain-kit' -Reason 'Skipped by -SkipPublish.'
    $steps += Add-SkippedStep -Name 'publish-questionnaire-builder' -Reason 'Skipped by -SkipPublish.'
} else {
    $dir = Join-Path $OutputRoot '09-publish-experiment-chain-kit'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\publish-experiment-chain-kit.ps1'),
        '-ProjectPath', $ProjectPath,
        '-RunId', "$RunId-kit"
    )
    $steps += Invoke-Step -Name 'publish-experiment-chain-kit' -FilePath 'powershell' -Arguments $args -StepDir $dir

    $dir = Join-Path $OutputRoot '10-publish-questionnaire-builder'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\publish-questionnaire-builder.ps1'),
        '-ProjectPath', $ProjectPath,
        '-RunId', "$RunId-builder"
    )
    $steps += Invoke-Step -Name 'publish-questionnaire-builder' -FilePath 'powershell' -Arguments $args -StepDir $dir
}

$adbSummary = Get-JsonStatus (($steps | Where-Object { $_.name -eq 'quest-adb-readiness' } | Select-Object -First 1).summary)
$batchDryRunSummary = Get-JsonStatus (($steps | Where-Object { $_.name -eq 'chainlink-batch-dryrun' } | Select-Object -First 1).summary)
$renderSummary = Get-JsonStatus (($steps | Where-Object { $_.name -eq 'android-render-preview' } | Select-Object -First 1).summary)

$failCount = @($steps | Where-Object { $_.status -eq 'fail' }).Count
$warnCount = @($steps | Where-Object { $_.status -eq 'warn' }).Count
$passCount = @($steps | Where-Object { $_.status -eq 'pass' }).Count
$skippedCount = @($steps | Where-Object { $_.status -eq 'skipped' }).Count
$deviceReady = $adbSummary -and $adbSummary.readiness -eq 'online'
$hostCorePass = ($failCount -eq 0)
$liveDevicePass = @($steps | Where-Object { $_.name -eq 'chainlink-batch-device' -and $_.status -eq 'pass' }).Count -gt 0

$overallStatus = if ($failCount -gt 0) {
    'fail'
} elseif ($liveDevicePass) {
    'pass'
} elseif ($hostCorePass -and -not $deviceReady) {
    'host-ready-device-pending'
} else {
    'warn'
}

$recommendedArchitecture = [ordered]@{
    primary = 'ChainLink numbered block plan plus Unity foreground hook'
    reason = 'Most flexible for arbitrary APK chains: ChainLink owns plans and app switching; foreground Unity apps forward controller triggers they own.'
    useOrchestratorWhen = 'Use the orchestrator/broker as a richer plan owner or external command endpoint when a study needs centralized status, host/LSL interaction, or legacy wrapper flows.'
    closedApkMode = 'Launch-only or wrapper/manual/LSL gate; closed immersive APKs cannot provide reliable controller-trigger transitions without source hooks.'
    dataPolicy = 'Questionnaire exports remain append-only and timestamped per invocation/answer.'
}

$summary = [ordered]@{
    schemaVersion = 'viscereality.experiment-setup-validation.v1'
    status = $overallStatus
    runId = $RunId
    projectPath = $ProjectPath
    outputRoot = $OutputRoot
    passCount = $passCount
    warnCount = $warnCount
    failCount = $failCount
    skippedCount = $skippedCount
    questReadiness = if ($adbSummary) { $adbSummary.readiness } else { 'unknown' }
    questOnline = [bool]$deviceReady
    liveDeviceBatchPass = [bool]$liveDevicePass
    dryRunScenarioTargets = if ($batchDryRunSummary) { $batchDryRunSummary.targetCount } else { $null }
    dryRunScenarioPasses = if ($batchDryRunSummary) { $batchDryRunSummary.passCount } else { $null }
    renderWarningCount = if ($renderSummary) { @($renderSummary.renders | Where-Object { @($_.warn).Count -gt 0 }).Count } else { $null }
    recommendedArchitecture = $recommendedArchitecture
    steps = $steps
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'experiment-setup-validation-summary.json'
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]@{
    Status = $overallStatus
    Pass = $passCount
    Warn = $warnCount
    Fail = $failCount
    Skipped = $skippedCount
    QuestReadiness = $summary.questReadiness
    DryRunScenarioTargets = $summary.dryRunScenarioTargets
    Summary = $summaryPath
}

if ($overallStatus -eq 'fail') {
    throw "Experiment setup validation failed. See $summaryPath"
}
