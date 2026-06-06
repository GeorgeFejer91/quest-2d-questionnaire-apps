param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string[]]$TargetPackages = @(),
    [string]$TargetActivity = "com.unity3d.player.UnityPlayerGameActivity",
    [ValidateSet('ScenarioThenQuestionnaire', 'QuestionnaireThenScenario', 'Both')]
    [string]$Order = 'Both',
    [string]$OutputRoot = "",
    [int]$MaxTargets = 5,
    [int]$WaitSeconds = 36,
    [int]$WrapperAutoContinueDelayMs = 6000,
    [switch]$SkipBuild,
    [switch]$StopOnFailure
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.viscereality.questionnaires2d"
$wrapperPackage = "org.viscereality.chainhookwrapper"
$singleValidator = Join-Path $ProjectPath 'tools\quest-orchestrator-wrapper-chain-validate.ps1'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\qbatch\" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
}

function Resolve-Adb {
    param([string]$RequestedAdb)
    if (-not [string]::IsNullOrWhiteSpace($RequestedAdb)) {
        if (Test-Path -LiteralPath $RequestedAdb) { return $RequestedAdb }
        throw "ADB not found: $RequestedAdb"
    }
    $mqdhAdb = "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe"
    $unityAdb = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
    foreach ($candidate in @($mqdhAdb, $unityAdb)) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "ADB not found. Pass -Adb explicitly."
}

function Invoke-AdbText {
    param([string[]]$Arguments, [string]$OutputPath)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Adb -s $Serial @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) }
}

function ConvertTo-Slug {
    param([string]$Value)
    $leaf = (($Value -split '\.')[-1] -replace '^Viscereality', '')
    $spaced = $leaf -creplace '([a-z0-9])([A-Z])', '$1-$2'
    $spaced = $spaced -creplace '([A-Z]+)([A-Z][a-z])', '$1-$2'
    $slug = ($spaced -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return 'scenario'
    }
    return $slug
}

function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments)
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        }
        else {
            $argument
        }
    }
    return ($quoted -join ' ')
}

function New-Plan {
    param([string]$PackageName, [string]$ActivityName, [string]$PlanOrder, [string]$Slug, [int]$DelayMs)

    $chainId = "batch-$Slug-" + $(if ($PlanOrder -eq 'ScenarioThenQuestionnaire') { 'scenario-questionnaire' } else { 'questionnaire-scenario' })
    $wrapperStep = [ordered]@{
        id = "$Slug-wrapper"
        type = "scenario"
        package = $wrapperPackage
        activity = ".ChainHookActivity"
        action = "org.viscereality.CHAIN_COMMAND"
        command = "launchTarget"
        extras = [ordered]@{
            targetPackage = $PackageName
            targetActivity = $ActivityName
            scenarioId = $Slug
            "mq.autoContinueDelayMs" = $DelayMs
        }
    }
    $questionnaireStepId = if ($PlanOrder -eq 'ScenarioThenQuestionnaire') { "questionnaire-after-$Slug" } else { "questionnaire-before-$Slug" }
    $questionnaireStep = [ordered]@{
        id = $questionnaireStepId
        type = "questionnaire"
        package = $questionnairePackage
        activity = ".MainActivity"
        extras = [ordered]@{
            "mq.sessionId" = "$chainId-session"
            "mq.experimentId" = "batch-installed-scenario-validation"
            "mq.scenarioId" = $Slug
            "mq.trialId" = "trial-01"
            "mq.participantId" = "BatchP001"
            "mq.participantName" = "BatchP001"
            "mq.language" = "English"
            "mq.autoCloseDelayMs" = 0
        }
    }
    $steps = if ($PlanOrder -eq 'ScenarioThenQuestionnaire') {
        @($wrapperStep, $questionnaireStep)
    }
    else {
        @($questionnaireStep, $wrapperStep)
    }
    return [ordered]@{
        schemaVersion = "my-questionnaire-2d.chain-plan.v1"
        chainId = $chainId
        questionnaireId = "viscereality-maia2"
        questionnaireVersion = "1.0.0"
        defaultFinishBehavior = "resumeCaller"
        steps = $steps
    }
}

function Get-InstalledScenarioPackages {
    $preferred = @(
        'com.Viscereality.ViscerealityPeriPersonalSpaceRight',
        'com.Viscereality.ViscerealityPeriPersonalSpaceLeft',
        'com.Viscereality.ViscerealityPeriPersonalRight2',
        'com.Viscereality.ViscerealitySphere',
        'com.Viscereality.ViscerealityEggspansion',
        'com.Viscereality.ViscerealityTracers',
        'com.Viscereality.SussexPolarController',
        'com.Viscereality.ViscerealityPolarTest'
    )
    $probe = Invoke-AdbText -Arguments @('shell', 'pm', 'list', 'packages') -OutputPath (Join-Path $OutputRoot 'pm-list-packages.txt')
    if ($probe.ExitCode -ne 0) {
        throw "Could not list installed packages."
    }
    $installed = @($probe.Output | ForEach-Object { $_.ToString().Trim().Replace('package:', '') } | Where-Object { $_ -match '^com\.Viscereality\.' })
    $selected = @()
    foreach ($candidate in $preferred) {
        if ($installed -contains $candidate) {
            $selected += $candidate
        }
    }
    if ($selected.Count -lt $MaxTargets) {
        foreach ($candidate in ($installed | Sort-Object)) {
            if ($selected -notcontains $candidate) {
                $selected += $candidate
            }
            if ($selected.Count -ge $MaxTargets) {
                break
            }
        }
    }
    return @($selected | Select-Object -First $MaxTargets)
}

if (-not (Test-Path -LiteralPath $singleValidator)) {
    throw "Single-run orchestrator wrapper validator not found: $singleValidator"
}

$Adb = Resolve-Adb $Adb
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = & $Adb devices -l | Select-String -Pattern '\sdevice\s'
    if (@($devices).Count -eq 1) {
        $Serial = (@($devices)[0].ToString() -split '\s+')[0]
    }
}
if ([string]::IsNullOrWhiteSpace($Serial)) {
    throw "No unique Quest serial detected. Pass -Serial explicitly."
}

if (-not $SkipBuild) {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-apk.ps1') -SkipTests
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-hook-wrapper-apk.ps1')
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-orchestrator-apk.ps1')
}

if ($TargetPackages.Count -eq 0) {
    $TargetPackages = @(Get-InstalledScenarioPackages)
}
if ($TargetPackages.Count -eq 0) {
    throw "No target packages were provided or discovered."
}

$orders = if ($Order -eq 'Both') { @('ScenarioThenQuestionnaire', 'QuestionnaireThenScenario') } else { @($Order) }
$resultsPath = Join-Path $OutputRoot 'batch-results.jsonl'
if (Test-Path -LiteralPath $resultsPath) {
    Remove-Item -LiteralPath $resultsPath -Force
}

$runs = @()
$runIndex = 0
foreach ($packageName in $TargetPackages) {
    foreach ($runOrder in $orders) {
        $runIndex += 1
        $slug = ConvertTo-Slug $packageName
        $orderSlug = if ($runOrder -eq 'ScenarioThenQuestionnaire') { 'scenario-then-questionnaire' } else { 'questionnaire-then-scenario' }
        $runDir = Join-Path $OutputRoot ("r{0:D2}" -f $runIndex)
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        $planPath = Join-Path $runDir 'chain-plan.json'
        New-Plan -PackageName $packageName -ActivityName $TargetActivity -PlanOrder $runOrder -Slug $slug -DelayMs $WrapperAutoContinueDelayMs |
            ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath $planPath -Encoding UTF8

        $stdoutPath = Join-Path $runDir 'validator-stdout.txt'
        $stderrPath = Join-Path $runDir 'validator-stderr.txt'
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $singleValidator,
            '-Serial', $Serial,
            '-Adb', $Adb,
            '-ProjectPath', $ProjectPath,
            '-TargetPackage', $packageName,
            '-TargetActivity', $TargetActivity,
            '-ChainPlanPath', $planPath,
            '-OutputRoot', $runDir,
            '-WaitSeconds', $WaitSeconds,
            '-WrapperAutoContinueDelayMs', $WrapperAutoContinueDelayMs,
            '-SkipBuild'
        )
        $process = Start-Process -FilePath 'powershell' -ArgumentList (ConvertTo-ProcessArgumentString -Arguments $arguments) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $summaryPath = Join-Path $runDir 'quest-orchestrator-wrapper-chain-validation-summary.json'
        $summary = $null
        $status = 'fail'
        $warnings = @()
        if (Test-Path -LiteralPath $summaryPath) {
            $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
            $status = [string]$summary.status
            $warnings = @($summary.warnings)
        }
        else {
            $warnings = @('Single-run validator did not write a summary.')
        }
        if ($process.ExitCode -ne 0) {
            $status = 'fail'
            $warnings += "Single-run validator exited with code $($process.ExitCode)."
        }

        $result = [ordered]@{
            package = $packageName
            activity = $TargetActivity
            order = $runOrder
            slug = $slug
            status = $status
            exitCode = $process.ExitCode
            summaryPath = $summaryPath
            evidenceDir = $runDir
            fatalLogCount = if ($summary) { $summary.fatalLogCount } else { $null }
            hookTargetStartedCount = if ($summary) { $summary.hookTargetStartedCount } else { $null }
            orchestratorCompleteCount = if ($summary) { $summary.orchestratorCompleteCount } else { $null }
            exportCounts = if ($summary) { $summary.exportCounts } else { $null }
            launchCheckControllerRequiredCount = if ($summary) { $summary.launchCheckControllerRequiredCount } else { $null }
            warnings = $warnings
        }
        ($result | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath $resultsPath -Encoding UTF8
        $runs += [pscustomobject]$result

        if ($status -ne 'pass' -and $StopOnFailure) {
            break
        }
    }
    if ($StopOnFailure -and @($runs | Where-Object { $_.status -ne 'pass' }).Count -gt 0) {
        break
    }
}

$passCount = @($runs | Where-Object { $_.status -eq 'pass' }).Count
$failCount = @($runs | Where-Object { $_.status -ne 'pass' }).Count
$controllerPromptCount = @($runs | Where-Object { $_.launchCheckControllerRequiredCount -gt 0 }).Count
$summaryRoot = [ordered]@{
    schemaVersion = 'viscereality.installed-scenario-batch-validation.v1'
    status = if ($failCount -eq 0) { 'pass' } else { 'fail' }
    serial = $Serial
    targetActivity = $TargetActivity
    targetPackageCount = @($TargetPackages).Count
    runCount = @($runs).Count
    passCount = $passCount
    failCount = $failCount
    controllerPromptRunCount = $controllerPromptCount
    waitSeconds = $WaitSeconds
    wrapperAutoContinueDelayMs = $WrapperAutoContinueDelayMs
    outputRoot = $OutputRoot
    resultsJsonl = $resultsPath
    targets = @($TargetPackages)
    runs = $runs
    completedAt = (Get-Date).ToString('o')
}
$summaryFile = Join-Path $OutputRoot 'quest-installed-scenario-batch-validation-summary.json'
$summaryRoot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryFile -Encoding UTF8
Write-Host "Quest installed scenario batch validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryFile"
if ($failCount -gt 0) {
    throw "Quest installed scenario batch validation had $failCount failing run(s). See $summaryFile"
}
