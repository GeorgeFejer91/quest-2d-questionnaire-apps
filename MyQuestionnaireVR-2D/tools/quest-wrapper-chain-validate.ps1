param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$QuestionnaireApk = "",
    [string]$WrapperApk = "",
    [string]$TargetApk = "",
    [string]$TargetPackage = "",
    [string]$TargetActivity = "",
    [string]$ChainPlanPath = "",
    [string]$OutputRoot = "",
    [int]$WaitSeconds = 34,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.viscereality.questionnaires2d"
$brokerActivity = "org.viscereality.questionnaires2d.QuestChainBrokerActivity"
$brokerAction = "org.viscereality.questionnaires2d.BROKER"
$wrapperPackage = "org.viscereality.chainhookwrapper"
$deviceFiles = "/sdcard/Android/data/$questionnairePackage/files"
$deviceBroker = "$deviceFiles/ChainBroker"
$deviceExports = "$deviceFiles/QuestionnaireExports"

if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $QuestionnaireApk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
}
if ([string]::IsNullOrWhiteSpace($WrapperApk)) {
    $WrapperApk = Join-Path $ProjectPath 'Builds\ViscerealityChainHookWrapper.apk'
}
if ([string]::IsNullOrWhiteSpace($ChainPlanPath)) {
    $ChainPlanPath = Join-Path $ProjectPath 'QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-wrapper-chain-validation\" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
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
    param($Plan, [string]$Package, [string]$Activity)
    if ([string]::IsNullOrWhiteSpace($Package)) { return $Plan }
    foreach ($step in $Plan.steps) {
        if ($step.package -eq $wrapperPackage -and $step.extras) {
            $step.extras.targetPackage = $Package
            if (-not [string]::IsNullOrWhiteSpace($Activity)) {
                $step.extras.targetActivity = $Activity
            }
        }
    }
    return $Plan
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
}
foreach ($apk in @($QuestionnaireApk, $WrapperApk)) {
    if (-not (Test-Path -LiteralPath $apk)) {
        throw "Required APK not found: $apk"
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

$installQuestionnaire = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $OutputRoot 'install-questionnaire.txt')
$installWrapper = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $WrapperApk) -OutputPath (Join-Path $OutputRoot 'install-wrapper.txt')
$installTarget = $null
if (-not [string]::IsNullOrWhiteSpace($TargetApk)) {
    $installTarget = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $TargetApk) -OutputPath (Join-Path $OutputRoot 'install-target.txt')
}
if ($installQuestionnaire -ne 0 -or $installWrapper -ne 0 -or ($null -ne $installTarget -and $installTarget -ne 0)) {
    throw "APK install failed. See $OutputRoot"
}

Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-questionnaire.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $wrapperPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-wrapper.txt') | Out-Null
if (-not [string]::IsNullOrWhiteSpace($TargetPackage)) {
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $TargetPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-target.txt') | Out-Null
}
Invoke-AdbText -Arguments @('shell', "rm -rf '$deviceExports' '$deviceBroker' && mkdir -p '$deviceFiles'") -OutputPath (Join-Path $OutputRoot 'clear-state.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$plan = Get-Content -LiteralPath $ChainPlanPath -Raw | ConvertFrom-Json
$plan = Set-TargetInPlan -Plan $plan -Package $TargetPackage -Activity $TargetActivity
$preparedPlan = Join-Path $OutputRoot 'prepared-chain-plan.json'
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $preparedPlan -Encoding UTF8
$marker = Join-Path $OutputRoot 'command-replay-english.json'
@{ ParticipantName = 'WrapperChainP001'; ExpectedAge = 33; GenderFocusId = 'gender.0' } |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $marker -Encoding UTF8

$pushMarker = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $marker, "$deviceFiles/command-replay-english.json") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-marker-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-marker-stderr.txt')
if ($pushMarker.ExitCode -ne 0) {
    throw "Could not push wrapper chain inputs."
}

$planJsonExtra = Get-Content -LiteralPath $preparedPlan -Raw
$planBase64Extra = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($planJsonExtra))
$launchExitCode = Invoke-AdbText -Arguments @(
    'shell', 'am', 'start',
    '-a', $brokerAction,
    '-n', "$questionnairePackage/$brokerActivity",
    '--es', 'mq.brokerCommand', 'startPlan',
    '--es', 'mq.chainPlanBase64', $planBase64Extra
) -OutputPath (Join-Path $OutputRoot 'launch-broker.txt')

Start-Sleep -Seconds $WaitSeconds
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $OutputRoot 'logcat.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'MyQuestionnaire2D:I', 'ViscerealityChainHook:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-chain.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $OutputRoot 'foreground-after.txt') | Out-Null

$pullRoot = Join-Path $OutputRoot 'device-files'
if (Test-Path -LiteralPath $pullRoot) { Remove-Item -LiteralPath $pullRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pullRoot | Out-Null
$pull = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $deviceFiles, $pullRoot) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-files-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-files-stderr.txt')

$logText = Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat.txt') -Raw
$foregroundText = Get-Content -LiteralPath (Join-Path $OutputRoot 'foreground-after.txt') -Raw
$fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
$hookReceivedCount = @([regex]::Matches($logText, 'CHAIN_HOOK_RECEIVED')).Count
$hookTargetStartedCount = @([regex]::Matches($logText, 'CHAIN_HOOK_TARGET_STARTED')).Count
$hookTargetFailedCount = @([regex]::Matches($logText, 'CHAIN_HOOK_TARGET_START_FAILED')).Count
$exportCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_EXPORT_COMPLETE')).Count
$exportMatchCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH')).Count
$launchCheckControllerRequiredCount = @([regex]::Matches($logText, 'REQUIRES_CONTROLLERS_LAUNCH_CHECK|LaunchCheckControllerRequiredDialogActivity|common_system_dialog_app_launch_blocked_controller_required')).Count + @([regex]::Matches($foregroundText, 'LaunchCheckControllerRequiredDialogActivity')).Count
$foregroundFocusLines = @($foregroundText -split "`r?`n" | Where-Object { $_ -match 'mCurrentFocus|mFocusedApp|mResumedActivity|mFocusedWindow' })

$exportRoot = Join-Path $pullRoot 'files\QuestionnaireExports'
$jsonExportFiles = @()
$csvExportFiles = @()
$draftFiles = @()
$indexLineCount = 0
$maia2AnswerCount = 0
$maia2ScoreCount = 0
$pictographicSelectionCount = 0
$sliderAnswerCount = 0
$exportRunId = ''
$exportChainId = ''
$exportChainStepId = ''
$exportParticipantName = ''
if (Test-Path -LiteralPath $exportRoot) {
    $jsonExportFiles = @(Get-ChildItem -LiteralPath $exportRoot -File -Filter '*.json' -ErrorAction SilentlyContinue)
    $csvExportFiles = @(Get-ChildItem -LiteralPath $exportRoot -File -Filter '*.csv' -ErrorAction SilentlyContinue)
    $draftRoot = Join-Path $exportRoot 'in_progress'
    if (Test-Path -LiteralPath $draftRoot) {
        $draftFiles = @(Get-ChildItem -LiteralPath $draftRoot -File -Filter '*.json' -ErrorAction SilentlyContinue)
    }
    $indexPath = Join-Path $exportRoot 'session-index.jsonl'
    if (Test-Path -LiteralPath $indexPath) {
        $indexLineCount = @((Get-Content -LiteralPath $indexPath -ErrorAction SilentlyContinue) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    }
    $latestJson = $jsonExportFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latestJson) {
        $record = Get-Content -LiteralPath $latestJson.FullName -Raw | ConvertFrom-Json
        $maia2AnswerCount = @($record.maia2Answers).Count
        $maia2ScoreCount = @($record.maia2Scores).Count
        $pictographicSelectionCount = @($record.pictographicSelections).Count
        $sliderAnswerCount = @($record.questionnaireAnswers).Count
        $exportRunId = [string]$record.runId
        $exportChainId = [string]$record.chainId
        $exportChainStepId = [string]$record.chainStepId
        $exportParticipantName = [string]$record.participant.name
    }
}
$questionnaireExpectedCountsOk = ($maia2AnswerCount -eq 37 -and $maia2ScoreCount -eq 8 -and $pictographicSelectionCount -eq 3 -and $sliderAnswerCount -eq 42)
$warnings = @()
if ($launchCheckControllerRequiredCount -gt 0) {
    $warnings += 'Horizon OS showed a controller-required launch check for the target APK; this is expected for some controller-only immersive APKs during no-human validation, but it means ADB alone did not prove the target scenario advanced past the system prompt.'
}
if ($foregroundText -match 'LaunchCheckControllerRequiredDialogActivity') {
    $warnings += 'Foreground evidence ended on the Quest controller-required system dialog.'
}

$status = 'pass'
if ($launchExitCode -ne 0 -or $pull.ExitCode -ne 0 -or $fatalLogCount -ne 0 -or $hookReceivedCount -lt 1) {
    $status = 'fail'
}
if ((-not [string]::IsNullOrWhiteSpace($TargetApk) -or -not [string]::IsNullOrWhiteSpace($TargetPackage)) -and ($hookTargetStartedCount -lt 1 -or $hookTargetFailedCount -gt 0)) {
    $status = 'fail'
}
if ($plan.steps.type -contains 'questionnaire' -and $exportCompleteCount -lt 1) {
    $status = 'fail'
}
if ($plan.steps.type -contains 'questionnaire' -and -not $questionnaireExpectedCountsOk) {
    $status = 'fail'
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.wrapper-chain-validation.v1'
    status = $status
    serial = $Serial
    questionnaireApk = $QuestionnaireApk
    wrapperApk = $WrapperApk
    targetApk = $TargetApk
    targetPackage = $TargetPackage
    targetActivity = $TargetActivity
    chainPlan = $preparedPlan
    evidenceDir = $OutputRoot
    launchExitCode = $launchExitCode
    pullExitCode = $pull.ExitCode
    fatalLogCount = $fatalLogCount
    hookReceivedCount = $hookReceivedCount
    hookTargetStartedCount = $hookTargetStartedCount
    hookTargetFailedCount = $hookTargetFailedCount
    exportCompleteCount = $exportCompleteCount
    exportMatchCount = $exportMatchCount
    launchCheckControllerRequiredCount = $launchCheckControllerRequiredCount
    foregroundFocusLines = $foregroundFocusLines
    exportCounts = [ordered]@{
        jsonFiles = @($jsonExportFiles).Count
        csvFiles = @($csvExportFiles).Count
        draftFiles = @($draftFiles).Count
        indexLineCount = $indexLineCount
        maia2Answers = $maia2AnswerCount
        maia2Scores = $maia2ScoreCount
        pictographicSelections = $pictographicSelectionCount
        sliderAnswers = $sliderAnswerCount
        expectedCountsOk = $questionnaireExpectedCountsOk
        runId = $exportRunId
        participantName = $exportParticipantName
        chainId = $exportChainId
        chainStepId = $exportChainStepId
    }
    warnings = $warnings
    completedAt = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $OutputRoot 'quest-wrapper-chain-validation-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest wrapper chain validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest wrapper chain validation failed. See $summaryPath"
}
