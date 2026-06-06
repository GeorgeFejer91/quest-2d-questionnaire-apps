param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$QuestionnaireApk = "",
    [string]$ChainLinkApk = "",
    [string]$TargetApk = "",
    [string]$TargetPackage = "",
    [string]$TargetActivity = "",
    [string]$ChainPlanPath = "",
    [string]$ParticipantName = "ChainLinkStressP001",
    [string]$SessionId = "",
    [int]$PictographicRepeats = 2,
    [int]$AutoStepWaitSeconds = 22,
    [int]$FinalCompleteWaitSeconds = 5,
    [switch]$SkipBuild,
    [switch]$InstallTarget,
    [switch]$NoFinalCompleteCommand,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.mesmerprism.viscereality.questionnaires2d"
$questionnaireActivity = "org.mesmerprism.viscereality.questionnaires2d.MainActivity"
$chainLinkPackage = "org.mesmerprism.viscereality.chainlink"
$chainLinkActivity = "org.mesmerprism.viscereality.chainlink.ChainLinkActivity"
$chainLinkRunAction = "org.mesmerprism.viscereality.chainlink.RUN"
$chainLinkCommandAction = "org.mesmerprism.viscereality.chainlink.COMMAND"
$questionnaireFiles = "/sdcard/Android/data/$questionnairePackage/files"
$questionnaireExports = "$questionnaireFiles/QuestionnaireExports"
$chainLinkFiles = "/sdcard/Android/data/$chainLinkPackage/files"
$chainLinkStateDir = "$chainLinkFiles/ChainLink"
$devicePlanPath = "$chainLinkFiles/chainlink-plan-validation.json"

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = "chainlink-plan-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-chainlink-plan-validation\" + $SessionId)
}
if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $packagedQuestionnaireApk = Join-Path $ProjectPath 'apks\MyQuestionnaireVR-2D.apk'
    if (Test-Path -LiteralPath $packagedQuestionnaireApk) {
        $QuestionnaireApk = $packagedQuestionnaireApk
    } else {
        $QuestionnaireApk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
    }
}
if ([string]::IsNullOrWhiteSpace($ChainLinkApk)) {
    $packagedChainLinkApk = Join-Path $ProjectPath 'apks\ViscerealityChainLink.apk'
    if (Test-Path -LiteralPath $packagedChainLinkApk) {
        $ChainLinkApk = $packagedChainLinkApk
    } else {
        $ChainLinkApk = Join-Path $ProjectPath 'Builds\ViscerealityChainLink.apk'
    }
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

function Resolve-Aapt {
    $root = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\build-tools"
    $aapt = Get-ChildItem -LiteralPath $root -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $aapt) { throw "Could not find aapt.exe under $root" }
    return $aapt.FullName
}

function Get-ApkLaunchInfo {
    param([string]$Apk)
    $aapt = Resolve-Aapt
    $badging = & $aapt dump badging $Apk 2>&1
    if ($LASTEXITCODE -ne 0) {
        $badging | Write-Host
        throw "aapt dump badging failed for $Apk"
    }
    $packageLine = $badging | Select-String -Pattern "^package:" | Select-Object -First 1
    $activityLine = $badging | Select-String -Pattern "^launchable-activity:" | Select-Object -First 1
    $package = if ($packageLine -and $packageLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
    $activity = if ($activityLine -and $activityLine.ToString() -match "name='([^']+)'") { $Matches[1] } else { "" }
    return [pscustomobject]@{ Package = $package; Activity = $activity }
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
    $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return $exitCode
}

function Set-TargetInPlan {
    param(
        [object]$Plan,
        [string]$Package,
        [string]$Activity
    )

    if ([string]::IsNullOrWhiteSpace($Package)) {
        return $Plan
    }

    foreach ($step in $Plan.steps) {
        if ($step.type -ne 'questionnaire') {
            $step.package = $Package
            if (-not [string]::IsNullOrWhiteSpace($Activity)) {
                $step.activity = $Activity
            }
        }
    }
    if ($Plan.blockRegistry -and $Plan.blockRegistry.targetApp) {
        $Plan.blockRegistry.targetApp.package = $Package
        if (-not [string]::IsNullOrWhiteSpace($Activity)) {
            $Plan.blockRegistry.targetApp.activity = $Activity
        }
    }
    return $Plan
}

function Get-FinalExportRecords {
    param([string]$ExportRoot)

    $records = @()
    if (-not (Test-Path -LiteralPath $ExportRoot)) {
        return $records
    }
    $jsonFiles = Get-ChildItem -LiteralPath $ExportRoot -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]in_progress[\\/]' -and $_.Name -ne 'session-index.jsonl' }
    foreach ($jsonFile in $jsonFiles) {
        try {
            $record = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
            if ($record.PSObject.Properties.Name -contains 'runId') {
                $records += [pscustomobject]@{ File = $jsonFile; Record = $record }
            }
        }
        catch {
            Write-Warning "Could not parse export JSON: $($jsonFile.FullName)"
        }
    }
    return $records
}

function Count-ResponseTimestamps {
    param([object[]]$Records)

    $missing = 0
    $total = 0
    foreach ($entry in $Records) {
        foreach ($collectionName in @('maia2Answers', 'pictographicSelections', 'questionnaireAnswers')) {
            $items = @($entry.Record.$collectionName)
            foreach ($item in $items) {
                $total++
                if ([string]::IsNullOrWhiteSpace([string]$item.responseTimestampUtc) -or [string]::IsNullOrWhiteSpace([string]$item.responseTimestampUnixMs)) {
                    $missing++
                }
            }
        }
    }
    return [pscustomobject]@{ Total = $total; Missing = $missing }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

if (-not $SkipBuild -and -not $DryRun) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-apk.ps1') -ProjectPath $ProjectPath -SkipTests | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Questionnaire APK build failed with exit code $LASTEXITCODE" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-chainlink-apk.ps1') -ProjectPath $ProjectPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "ChainLink APK build failed with exit code $LASTEXITCODE" }
}

foreach ($required in @($QuestionnaireApk, $ChainLinkApk)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required APK not found: $required"
    }
}

if (-not [string]::IsNullOrWhiteSpace($TargetApk)) {
    if (-not (Test-Path -LiteralPath $TargetApk)) {
        throw "Target APK not found: $TargetApk"
    }
    $info = Get-ApkLaunchInfo -Apk $TargetApk
    if ([string]::IsNullOrWhiteSpace($TargetPackage)) { $TargetPackage = $info.Package }
    if ([string]::IsNullOrWhiteSpace($TargetActivity)) { $TargetActivity = $info.Activity }
}

if ([string]::IsNullOrWhiteSpace($ChainPlanPath)) {
    $generatedPlan = Join-Path $OutputRoot 'generated-chainlink-plan.json'
    if (-not [string]::IsNullOrWhiteSpace($TargetApk)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\new-chainlink-plan.ps1') `
            -TargetApk $TargetApk `
            -PictographicRepeats $PictographicRepeats `
            -OutputPath $generatedPlan | Out-Host
    } else {
        if ([string]::IsNullOrWhiteSpace($TargetPackage)) {
            $defaultTarget = Join-Path $ProjectPath 'Builds\ViscerealitySourceHookStub.apk'
            if (Test-Path -LiteralPath $defaultTarget) {
                $TargetApk = $defaultTarget
                $InstallTarget = $true
                $info = Get-ApkLaunchInfo -Apk $TargetApk
                $TargetPackage = $info.Package
                $TargetActivity = $info.Activity
            } else {
                $TargetPackage = $chainLinkPackage
                $TargetActivity = $chainLinkActivity
            }
        }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\new-chainlink-plan.ps1') `
            -TargetPackage $TargetPackage `
            -TargetActivity $TargetActivity `
            -TargetLabel 'ChainLink Stress Target' `
            -PictographicRepeats $PictographicRepeats `
            -OutputPath $generatedPlan | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Could not generate ChainLink plan."
    }
    $ChainPlanPath = $generatedPlan
}

if (-not (Test-Path -LiteralPath $ChainPlanPath)) {
    throw "ChainLink plan not found: $ChainPlanPath"
}

$plan = Get-Content -LiteralPath $ChainPlanPath -Raw | ConvertFrom-Json
$plan = Set-TargetInPlan -Plan $plan -Package $TargetPackage -Activity $TargetActivity
$preparedPlan = Join-Path $OutputRoot 'prepared-chainlink-plan.json'
$plan | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $preparedPlan -Encoding UTF8

$steps = @($plan.steps)
$questionnaireSteps = @($steps | Where-Object { $_.type -eq 'questionnaire' })
$baselineSteps = @($questionnaireSteps | Where-Object { $_.extras.'mq.questionnaireMode' -eq 'baseline' -or $_.questionnaireMode -eq 'baseline' -or $_.saveNamespace -match 'baseline' })
$pictographicSteps = @($questionnaireSteps | Where-Object { $_.extras.'mq.questionnaireMode' -eq 'pictographic' -or $_.questionnaireMode -eq 'pictographic' -or $_.saveNamespace -match 'pictographic' })
$controllerTriggerSteps = @($steps | Where-Object { $_.trigger -and $_.trigger.type -eq 'controllerButton' })
$nextBlockCommandCount = $controllerTriggerSteps.Count
if (-not $NoFinalCompleteCommand) {
    $nextBlockCommandCount++
}

$plannedAdbCommands = @(
    "install questionnaire: adb install -r -d -g $QuestionnaireApk",
    "install ChainLink: adb install -r -d -g $ChainLinkApk",
    "push plan: adb push $preparedPlan $devicePlanPath",
    "start plan: adb shell am start -a $chainLinkRunAction -n $chainLinkPackage/$chainLinkActivity --es mq.command startPlan --es mq.chainPlanPath $devicePlanPath",
    "send nextBlock x${nextBlockCommandCount}: adb shell am start -a $chainLinkCommandAction -n $chainLinkPackage/$chainLinkActivity --es mq.command nextBlock"
)
if ($InstallTarget -and -not [string]::IsNullOrWhiteSpace($TargetApk)) {
    $plannedAdbCommands = @("install target: adb install -r -d -g $TargetApk") + $plannedAdbCommands
}

if ($DryRun) {
    $summary = [ordered]@{
        schemaVersion = 'viscereality.quest-chainlink-plan-validation.v1'
        status = 'pass'
        dryRun = $true
        projectPath = $ProjectPath
        outputRoot = $OutputRoot
        chainPlan = $preparedPlan
        targetPackage = $TargetPackage
        targetActivity = $TargetActivity
        stepCount = $steps.Count
        baselineSteps = $baselineSteps.Count
        pictographicSteps = $pictographicSteps.Count
        controllerTriggerSteps = $controllerTriggerSteps.Count
        plannedNextBlockCommands = $nextBlockCommandCount
        expectedExports = ($baselineSteps.Count + $pictographicSteps.Count)
        expectedBaselineExports = $baselineSteps.Count
        expectedPictographicExports = $pictographicSteps.Count
        plannedAdbCommands = $plannedAdbCommands
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $summaryPath = Join-Path $OutputRoot 'quest-chainlink-plan-validation-summary.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    [pscustomobject]@{
        Status = $summary.status
        DryRun = $true
        Steps = $steps.Count
        ExpectedExports = $summary.expectedExports
        PlannedNextBlockCommands = $nextBlockCommandCount
        Summary = $summaryPath
    }
    return
}

$Adb = Resolve-Adb $Adb
if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = & $Adb devices -l | Select-String -Pattern '\sdevice\s'
    if (@($devices).Count -eq 1) {
        $Serial = (@($devices)[0].ToString() -split '\s+')[0]
    }
}
if ([string]::IsNullOrWhiteSpace($Serial)) {
    throw "No unique Quest serial detected. Pass -Serial explicitly."
}

Invoke-AdbText -Arguments @('devices', '-l') -OutputPath (Join-Path $OutputRoot 'adb-devices.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.product.model') -OutputPath (Join-Path $OutputRoot 'device-model.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.build.version.release') -OutputPath (Join-Path $OutputRoot 'android-version.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'wm', 'size') -OutputPath (Join-Path $OutputRoot 'wm-size.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'wm', 'density') -OutputPath (Join-Path $OutputRoot 'wm-density.txt') | Out-Null

$installQuestionnaire = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $OutputRoot 'install-questionnaire.txt')
$installChainLink = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $ChainLinkApk) -OutputPath (Join-Path $OutputRoot 'install-chainlink.txt')
$installTargetExitCode = $null
if ($InstallTarget -and -not [string]::IsNullOrWhiteSpace($TargetApk)) {
    $installTargetExitCode = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $TargetApk) -OutputPath (Join-Path $OutputRoot 'install-target.txt')
}
if ($installQuestionnaire -ne 0 -or $installChainLink -ne 0 -or ($null -ne $installTargetExitCode -and $installTargetExitCode -ne 0)) {
    throw "APK install failed. See $OutputRoot"
}

Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-questionnaire.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $chainLinkPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-chainlink.txt') | Out-Null
if (-not [string]::IsNullOrWhiteSpace($TargetPackage)) {
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $TargetPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-target.txt') | Out-Null
}
Invoke-AdbText -Arguments @('shell', "rm -rf '$questionnaireExports' '$chainLinkStateDir' && mkdir -p '$questionnaireFiles' '$chainLinkFiles'") -OutputPath (Join-Path $OutputRoot 'clear-state.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$marker = Join-Path $OutputRoot 'command-replay-english.json'
@{
    ParticipantName = $ParticipantName
    ExpectedAge = 33
    GenderFocusId = 'gender.0'
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $marker -Encoding UTF8

$pushMarker = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $marker, "$questionnaireFiles/command-replay-english.json") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-marker-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-marker-stderr.txt')
$pushPlan = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $preparedPlan, $devicePlanPath) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-plan-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-plan-stderr.txt')
if ($pushMarker.ExitCode -ne 0 -or $pushPlan.ExitCode -ne 0) {
    throw "Could not push ChainLink validation inputs. See $OutputRoot"
}

$launchExitCode = Invoke-AdbText -Arguments @(
    'shell', 'am', 'start',
    '-a', $chainLinkRunAction,
    '-n', "$chainLinkPackage/$chainLinkActivity",
    '--es', 'mq.command', 'startPlan',
    '--es', 'mq.chainPlanPath', $devicePlanPath,
    '--es', 'mq.chainId', $SessionId,
    '--es', 'mq.sessionId', $SessionId,
    '--es', 'mq.participantName', $ParticipantName,
    '--es', 'mq.participantId', $ParticipantName,
    '--es', 'mq.language', 'English'
) -OutputPath (Join-Path $OutputRoot 'launch-chainlink-start-plan.txt')

Start-Sleep -Seconds $AutoStepWaitSeconds
$commandRuns = @()
for ($i = 1; $i -le $nextBlockCommandCount; $i++) {
    $commandDir = Join-Path $OutputRoot ("nextblock-{0:00}" -f $i)
    New-Item -ItemType Directory -Force -Path $commandDir | Out-Null
    $markerPushExit = Invoke-AdbText -Arguments @('push', $marker, "$questionnaireFiles/command-replay-english.json") -OutputPath (Join-Path $commandDir 'refresh-command-replay-marker.txt')
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $commandDir 'foreground-before.txt') | Out-Null
    $utc = (Get-Date).ToUniversalTime().ToString('o')
    $exit = Invoke-AdbText -Arguments @(
        'shell', 'am', 'start',
        '-a', $chainLinkCommandAction,
        '-n', "$chainLinkPackage/$chainLinkActivity",
        '--es', 'mq.command', 'nextBlock',
        '--es', 'mq.triggerSource', 'quest-chainlink-plan-validate',
        '--es', 'mq.triggerIndex', "$i",
        '--es', 'mq.triggerTimestampUtc', $utc
    ) -OutputPath (Join-Path $commandDir 'send-nextblock.txt')
    if ($i -eq $nextBlockCommandCount -and -not $NoFinalCompleteCommand) {
        Start-Sleep -Seconds $FinalCompleteWaitSeconds
    } else {
        Start-Sleep -Seconds $AutoStepWaitSeconds
    }
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $commandDir 'foreground-after.txt') | Out-Null
    $commandRuns += [ordered]@{ index = $i; exitCode = $exit; markerPushExitCode = $markerPushExit; timestampUtc = $utc }
}

Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $OutputRoot 'logcat.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'ViscerealityChainLink:I', 'MyQuestionnaire2D:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-chainlink-questionnaire.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $OutputRoot 'foreground-final.txt') | Out-Null

$pullRoot = Join-Path $OutputRoot 'd'
if (Test-Path -LiteralPath $pullRoot) { Remove-Item -LiteralPath $pullRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pullRoot | Out-Null
$questionnaireExportPullRoot = Join-Path $pullRoot 'q'
New-Item -ItemType Directory -Force -Path $questionnaireExportPullRoot | Out-Null
$pullQuestionnaireStdout = Join-Path $OutputRoot 'pull-questionnaire-stdout.txt'
$pullQuestionnaireStderr = Join-Path $OutputRoot 'pull-questionnaire-stderr.txt'
"" | Set-Content -LiteralPath $pullQuestionnaireStdout -Encoding UTF8
"" | Set-Content -LiteralPath $pullQuestionnaireStderr -Encoding UTF8
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $findOutput = & $Adb -s $Serial shell find $questionnaireExports -type f 2>&1
    $findExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorAction
}
$findOutput | Set-Content -LiteralPath (Join-Path $OutputRoot 'pull-questionnaire-file-list.txt') -Encoding UTF8
$pullQuestionnaireExitCode = $findExitCode
$pullMap = @()
if ($findExitCode -eq 0) {
    $pullIndex = 0
    foreach ($rawDeviceFile in @($findOutput)) {
        $deviceFile = $rawDeviceFile.ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($deviceFile) -or $deviceFile -notlike "$questionnaireExports*") {
            continue
        }
        $relative = $deviceFile.Substring($questionnaireExports.Length).TrimStart('/', '\')
        if ([string]::IsNullOrWhiteSpace($relative)) {
            continue
        }
        $pullIndex++
        $extension = [System.IO.Path]::GetExtension($relative)
        if ([string]::IsNullOrWhiteSpace($extension)) { $extension = '.bin' }
        if ($relative -eq 'session-index.jsonl') {
            $localFile = Join-Path $questionnaireExportPullRoot 'session-index.jsonl'
        } elseif ($relative -like 'in_progress/*') {
            $localFile = Join-Path (Join-Path $questionnaireExportPullRoot 'in_progress') ("draft-{0:000}{1}" -f $pullIndex, $extension)
        } else {
            $localFile = Join-Path $questionnaireExportPullRoot ("export-{0:000}{1}" -f $pullIndex, $extension)
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $localFile) | Out-Null
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $pullOutput = & $Adb -s $Serial pull $deviceFile $localFile 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorAction
        }
        $pullOutput | Add-Content -LiteralPath $pullQuestionnaireStdout -Encoding UTF8
        $pullMap += [ordered]@{
            deviceFile = $deviceFile
            relativePath = $relative
            localFile = $localFile
            exitCode = $exitCode
        }
        if ($exitCode -ne 0) {
            $pullOutput | Add-Content -LiteralPath $pullQuestionnaireStderr -Encoding UTF8
            $pullQuestionnaireExitCode = $exitCode
        }
    }
    $pullMap | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputRoot 'pull-questionnaire-file-map.json') -Encoding UTF8
}
$pullQuestionnaire = [pscustomobject]@{ ExitCode = $pullQuestionnaireExitCode }
$chainLinkPullRoot = Join-Path $pullRoot 'c'
New-Item -ItemType Directory -Force -Path $chainLinkPullRoot | Out-Null
$pullChainLink = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', "$chainLinkFiles/.", $chainLinkPullRoot) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-chainlink-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-chainlink-stderr.txt')

$exportRoot = $questionnaireExportPullRoot
$records = @(Get-FinalExportRecords -ExportRoot $exportRoot)
$runIds = @($records | ForEach-Object { $_.Record.runId } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$baselineRecords = @($records | Where-Object { $_.Record.questionnaireMode -eq 'baseline' })
$pictographicRecords = @($records | Where-Object { $_.Record.questionnaireMode -eq 'pictographic' })
$baselineValidCount = @($baselineRecords | Where-Object { @($_.Record.maia2Answers).Count -eq 37 -and @($_.Record.maia2Scores).Count -eq 8 }).Count
$pictographicValidCount = @($pictographicRecords | Where-Object { @($_.Record.pictographicSelections).Count -eq 3 }).Count
$timestampCoverage = Count-ResponseTimestamps -Records $records

$warnings = @()
$expectedQuestionnaireBlockNumbers = @(@($baselineSteps) + @($pictographicSteps) | ForEach-Object { $_.blockNumber } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$combinedCsvEntries = @($pullMap | Where-Object { $_.relativePath -like "session_*_combined.csv" })
$combinedCsvRows = @()
foreach ($entry in $combinedCsvEntries) {
    try {
        $combinedCsvRows += @(Import-Csv -LiteralPath $entry.localFile)
    } catch {
        $warnings += "Could not parse combined session CSV: $($entry.relativePath)"
    }
}
$combinedCsvBlockNumbers = @($combinedCsvRows | ForEach-Object { $_.blockNumber } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
$combinedCsvMissingBlockNumbers = @($expectedQuestionnaireBlockNumbers | Where-Object { $combinedCsvBlockNumbers -notcontains $_ })
$combinedCsvTimestampMissing = @($combinedCsvRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.timestampUtc) }).Count
$combinedCsvParticipantMismatchCount = @($combinedCsvRows | Where-Object {
    -not [string]::IsNullOrWhiteSpace($ParticipantName) -and [string]$_.name -ne $ParticipantName
}).Count

$indexPath = Join-Path $exportRoot 'session-index.jsonl'
$indexLineCount = 0
if (Test-Path -LiteralPath $indexPath) {
    $indexLineCount = @((Get-Content -LiteralPath $indexPath -ErrorAction SilentlyContinue) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}
$draftFiles = @()
$completeDraftCount = 0
$draftRoot = Join-Path $exportRoot 'in_progress'
if (Test-Path -LiteralPath $draftRoot) {
    $draftFiles = @(Get-ChildItem -LiteralPath $draftRoot -File -Filter '*.json' -ErrorAction SilentlyContinue)
    foreach ($draft in $draftFiles) {
        try {
            $draftRecord = Get-Content -LiteralPath $draft.FullName -Raw | ConvertFrom-Json
            if ($draftRecord.draftStatus -eq 'complete') { $completeDraftCount++ }
        } catch {}
    }
}

$chainStatePath = Join-Path $chainLinkPullRoot 'ChainLink\chainlink-state.json'
$chainEventsPath = Join-Path $chainLinkPullRoot 'ChainLink\chainlink-events.jsonl'
$chainState = $null
if (Test-Path -LiteralPath $chainStatePath) {
    $chainState = Get-Content -LiteralPath $chainStatePath -Raw | ConvertFrom-Json
}
$chainEvents = @()
if (Test-Path -LiteralPath $chainEventsPath) {
    $chainEvents = @(Get-Content -LiteralPath $chainEventsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
}

$logText = ""
foreach ($logPath in @((Join-Path $OutputRoot 'logcat.txt'), (Join-Path $OutputRoot 'logcat-chainlink-questionnaire.txt'))) {
    if (Test-Path -LiteralPath $logPath) {
        $logText += "`n" + (Get-Content -LiteralPath $logPath -Raw)
    }
}
$foregroundText = ""
$foregroundPath = Join-Path $OutputRoot 'foreground-final.txt'
if (Test-Path -LiteralPath $foregroundPath) {
    $foregroundText = Get-Content -LiteralPath $foregroundPath -Raw
}

$fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
$chainLinkErrorCount = @([regex]::Matches($logText, 'CHAINLINK_ERROR|CHAINLINK_CONTROLLER_TRIGGER_FAILED')).Count
$chainLinkLaunchStepCount = @($chainEvents | Where-Object { $_.event -eq 'launch-step' }).Count
$chainLinkPlanCompleteCount = @($chainEvents | Where-Object { $_.event -eq 'plan-complete' }).Count
$exportCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_EXPORT_COMPLETE')).Count
$commandReplayMatchCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH')).Count
$launchCheckControllerRequiredCount = @([regex]::Matches($logText + "`n" + $foregroundText, 'REQUIRES_CONTROLLERS_LAUNCH_CHECK|LaunchCheckControllerRequiredDialogActivity|common_system_dialog_app_launch_blocked_controller_required')).Count

$expectedExports = $baselineSteps.Count + $pictographicSteps.Count
if ($launchCheckControllerRequiredCount -gt 0) {
    $warnings += 'Horizon OS showed a controller-required launch check for the target APK; this can be expected for controller-only immersive targets during no-human validation.'
}
if ($NoFinalCompleteCommand) {
    $warnings += 'Final complete command was skipped, so ChainLink state is expected to remain on the last launched step.'
}

$status = 'pass'
if ($launchExitCode -ne 0 -or $pullQuestionnaire.ExitCode -ne 0 -or $pullChainLink.ExitCode -ne 0) { $status = 'fail' }
if ($fatalLogCount -ne 0 -or $chainLinkErrorCount -ne 0) { $status = 'fail' }
if ($records.Count -lt $expectedExports -or $runIds.Count -lt $expectedExports) { $status = 'fail' }
if ($baselineValidCount -lt $baselineSteps.Count -or $pictographicValidCount -lt $pictographicSteps.Count) { $status = 'fail' }
if ($timestampCoverage.Missing -ne 0 -or $timestampCoverage.Total -eq 0) { $status = 'fail' }
if ($indexLineCount -lt $records.Count -or $completeDraftCount -lt $records.Count) { $status = 'fail' }
if ($combinedCsvEntries.Count -lt 1 -or $combinedCsvRows.Count -lt $expectedExports -or $combinedCsvMissingBlockNumbers.Count -gt 0) { $status = 'fail' }
if ($combinedCsvTimestampMissing -ne 0 -or $combinedCsvParticipantMismatchCount -ne 0) { $status = 'fail' }
if ($chainLinkLaunchStepCount -lt $steps.Count) { $status = 'fail' }
if (-not $NoFinalCompleteCommand -and ($chainLinkPlanCompleteCount -lt 1 -or $chainState.status -ne 'complete')) { $status = 'fail' }

$summary = [ordered]@{
    schemaVersion = 'viscereality.quest-chainlink-plan-validation.v1'
    status = $status
    dryRun = $false
    serial = $Serial
    projectPath = $ProjectPath
    outputRoot = $OutputRoot
    questionnaireApk = $QuestionnaireApk
    chainLinkApk = $ChainLinkApk
    targetApk = $TargetApk
    targetPackage = $TargetPackage
    targetActivity = $TargetActivity
    chainPlan = $preparedPlan
    sessionId = $SessionId
    participantName = $ParticipantName
    stepCount = $steps.Count
    baselineSteps = $baselineSteps.Count
    pictographicSteps = $pictographicSteps.Count
    controllerTriggerSteps = $controllerTriggerSteps.Count
    sentNextBlockCommands = @($commandRuns).Count
    expectedExports = $expectedExports
    finalExportCount = $records.Count
    uniqueRunIds = $runIds.Count
    baselineValidCount = $baselineValidCount
    pictographicValidCount = $pictographicValidCount
    responseTimestampTotal = $timestampCoverage.Total
    responseTimestampMissing = $timestampCoverage.Missing
    combinedCsvCount = $combinedCsvEntries.Count
    combinedCsvRows = $combinedCsvRows.Count
    combinedCsvMissingBlockNumbers = @($combinedCsvMissingBlockNumbers)
    combinedCsvTimestampMissing = $combinedCsvTimestampMissing
    combinedCsvParticipantMismatchCount = $combinedCsvParticipantMismatchCount
    sessionIndexLineCount = $indexLineCount
    draftCount = $draftFiles.Count
    completeDraftCount = $completeDraftCount
    chainLinkStateStatus = if ($chainState) { $chainState.status } else { $null }
    chainLinkCurrentStepIndex = if ($chainState) { $chainState.currentStepIndex } else { $null }
    chainLinkEventCount = @($chainEvents).Count
    chainLinkLaunchStepCount = $chainLinkLaunchStepCount
    chainLinkPlanCompleteCount = $chainLinkPlanCompleteCount
    fatalLogCount = $fatalLogCount
    chainLinkErrorCount = $chainLinkErrorCount
    exportCompleteCount = $exportCompleteCount
    commandReplayMatchCount = $commandReplayMatchCount
    launchCheckControllerRequiredCount = $launchCheckControllerRequiredCount
    warnings = $warnings
    commandRuns = @($commandRuns)
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'quest-chainlink-plan-validation-summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest ChainLink plan validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest ChainLink plan validation failed. See $summaryPath"
}
