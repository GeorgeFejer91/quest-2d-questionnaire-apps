param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$QuestionnaireApk = "",
    [string]$SourceHookStubApk = "",
    [string]$OutputRoot = "",
    [int]$WaitSeconds = 24,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.viscereality.questionnaires2d"
$brokerActivity = "org.viscereality.questionnaires2d.QuestChainBrokerActivity"
$brokerAction = "org.viscereality.questionnaires2d.BROKER"
$sourcePackage = "org.viscereality.sourcehookstub"
$sourceActivity = "org.viscereality.sourcehookstub.SourceHookStubActivity"
$deviceFiles = "/sdcard/Android/data/$questionnairePackage/files"
$deviceExports = "$deviceFiles/QuestionnaireExports"
$deviceBroker = "$deviceFiles/ChainBroker"

if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $QuestionnaireApk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
}
if ([string]::IsNullOrWhiteSpace($SourceHookStubApk)) {
    $SourceHookStubApk = Join-Path $ProjectPath 'Builds\ViscerealitySourceHookStub.apk'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-source-hook-chain-validation\" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
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
    $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return $exitCode
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
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-source-hook-stub-apk.ps1')
}
foreach ($apk in @($QuestionnaireApk, $SourceHookStubApk)) {
    if (-not (Test-Path -LiteralPath $apk)) {
        throw "Required APK not found: $apk"
    }
}

$installQuestionnaire = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $OutputRoot 'install-questionnaire.txt')
$installSourceHook = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $SourceHookStubApk) -OutputPath (Join-Path $OutputRoot 'install-source-hook-stub.txt')
if ($installQuestionnaire -ne 0 -or $installSourceHook -ne 0) {
    throw "APK install failed. See $OutputRoot"
}

Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-questionnaire.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $sourcePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-source-hook-stub.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', "rm -rf '$deviceExports' '$deviceBroker' && mkdir -p '$deviceFiles'") -OutputPath (Join-Path $OutputRoot 'clear-state.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$chainId = "source-hook-stub-chain-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
$planPath = Join-Path $OutputRoot 'source-hook-chain-plan.json'
$plan = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.chain-plan.v1'
    chainId = $chainId
    questionnaireId = 'viscereality-maia2'
    questionnaireVersion = '1.0.0'
    defaultFinishBehavior = 'resumeCaller'
    steps = @(
        [ordered]@{
            id = 'source-hook-stub-scenario'
            type = 'scenario'
            package = $sourcePackage
            activity = $sourceActivity
            action = 'org.viscereality.CHAIN_COMMAND'
            command = 'startScenario'
            extras = [ordered]@{
                scenarioId = 'source-hook-stub'
                'mq.autoContinueDelayMs' = 1500
            }
        },
        [ordered]@{
            id = 'questionnaire-after-source-hook-stub'
            type = 'questionnaire'
            package = $questionnairePackage
            activity = '.MainActivity'
            extras = [ordered]@{
                'mq.sessionId' = "$chainId-session"
                'mq.experimentId' = 'source-hook-validation'
                'mq.scenarioId' = 'source-hook-stub'
                'mq.trialId' = 'trial-01'
                'mq.participantId' = 'SourceHookP001'
                'mq.participantName' = 'SourceHookP001'
                'mq.language' = 'English'
                'mq.autoCloseDelayMs' = 0
            }
        }
    )
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding UTF8

$marker = Join-Path $OutputRoot 'command-replay-english.json'
@{ ParticipantName = 'SourceHookP001'; ExpectedAge = 33; GenderFocusId = 'gender.0' } |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $marker -Encoding UTF8

$pushMarker = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $marker, "$deviceFiles/command-replay-english.json") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-marker-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-marker-stderr.txt')
if ($pushMarker.ExitCode -ne 0) {
    throw "Could not push source-hook chain input marker."
}

$planJsonExtra = Get-Content -LiteralPath $planPath -Raw
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
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'MyQuestionnaire2D:I', 'ViscerealitySourceHook:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-chain.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $OutputRoot 'foreground-after.txt') | Out-Null

$pullRoot = Join-Path $OutputRoot 'device-files'
if (Test-Path -LiteralPath $pullRoot) { Remove-Item -LiteralPath $pullRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pullRoot | Out-Null
$pull = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $deviceFiles, $pullRoot) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-files-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-files-stderr.txt')

$logText = Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat.txt') -Raw
$fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
$sourceHookReceivedCount = @([regex]::Matches($logText, 'SOURCE_HOOK_STUB_RECEIVED')).Count
$sourceHookContinueCount = @([regex]::Matches($logText, 'SOURCE_HOOK_STUB_BROKER_CONTINUE')).Count
$brokerScenarioCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_BROKER status=app:source-hook-stub-scenario')).Count
$brokerQuestionnaireCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_BROKER status=questionnaire:questionnaire-after-source-hook-stub')).Count
$brokerCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_BROKER status=plan-complete')).Count
$exportCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_EXPORT_COMPLETE')).Count
$exportMatchCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH')).Count

$exportRoot = Join-Path $pullRoot 'files\QuestionnaireExports'
$jsonExportFiles = @()
$csvExportFiles = @()
$draftFiles = @()
$indexLineCount = 0
$maia2AnswerCount = 0
$maia2ScoreCount = 0
$pictographicSelectionCount = 0
$sliderAnswerCount = 0
$exportChainId = ''
$exportChainStepId = ''
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
        $exportChainId = [string]$record.chainId
        $exportChainStepId = [string]$record.chainStepId
    }
}

$questionnaireExpectedCountsOk = ($maia2AnswerCount -eq 37 -and $maia2ScoreCount -eq 8 -and $pictographicSelectionCount -eq 3 -and $sliderAnswerCount -eq 42)
$status = 'pass'
if ($installQuestionnaire -ne 0 -or $installSourceHook -ne 0 -or $launchExitCode -ne 0 -or $pull.ExitCode -ne 0 -or $fatalLogCount -ne 0) {
    $status = 'fail'
}
if ($sourceHookReceivedCount -lt 1 -or $sourceHookContinueCount -lt 1 -or $brokerScenarioCount -lt 1 -or $brokerQuestionnaireCount -lt 1 -or $brokerCompleteCount -lt 1) {
    $status = 'fail'
}
if ($exportCompleteCount -lt 1 -or $exportMatchCount -lt 1 -or -not $questionnaireExpectedCountsOk -or $exportChainId -ne $chainId -or $exportChainStepId -ne 'questionnaire-after-source-hook-stub') {
    $status = 'fail'
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.source-hook-chain-validation.v1'
    status = $status
    serial = $Serial
    questionnaireApk = $QuestionnaireApk
    sourceHookStubApk = $SourceHookStubApk
    sourcePackage = $sourcePackage
    sourceActivity = $sourceActivity
    chainPlan = $planPath
    evidenceDir = $OutputRoot
    launchExitCode = $launchExitCode
    pullExitCode = $pull.ExitCode
    fatalLogCount = $fatalLogCount
    sourceHookReceivedCount = $sourceHookReceivedCount
    sourceHookContinueCount = $sourceHookContinueCount
    brokerScenarioCount = $brokerScenarioCount
    brokerQuestionnaireCount = $brokerQuestionnaireCount
    brokerCompleteCount = $brokerCompleteCount
    exportCompleteCount = $exportCompleteCount
    exportMatchCount = $exportMatchCount
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
        chainId = $exportChainId
        chainStepId = $exportChainStepId
    }
    completedAt = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $OutputRoot 'quest-source-hook-chain-validation-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest source-hook chain validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest source-hook chain validation failed. See $summaryPath"
}
