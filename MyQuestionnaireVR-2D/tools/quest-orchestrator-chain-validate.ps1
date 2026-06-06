param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$QuestionnaireApk = "",
    [string]$SourceHookStubApk = "",
    [string]$OrchestratorApk = "",
    [string]$OutputRoot = "",
    [int]$WaitSeconds = 32,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.viscereality.questionnaires2d"
$sourcePackage = "org.viscereality.sourcehookstub"
$sourceActivity = "org.viscereality.sourcehookstub.SourceHookStubActivity"
$orchestratorPackage = "org.viscereality.orchestrator"
$orchestratorActivity = "org.viscereality.orchestrator.ExperimentOrchestratorActivity"
$orchestratorAction = "org.viscereality.orchestrator.BROKER"
$questionnaireFiles = "/sdcard/Android/data/$questionnairePackage/files"
$questionnaireExports = "$questionnaireFiles/QuestionnaireExports"
$orchestratorFiles = "/sdcard/Android/data/$orchestratorPackage/files"
$orchestratorState = "$orchestratorFiles/ExperimentOrchestrator"

if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $QuestionnaireApk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
}
if ([string]::IsNullOrWhiteSpace($SourceHookStubApk)) {
    $SourceHookStubApk = Join-Path $ProjectPath 'Builds\ViscerealitySourceHookStub.apk'
}
if ([string]::IsNullOrWhiteSpace($OrchestratorApk)) {
    $OrchestratorApk = Join-Path $ProjectPath 'Builds\ViscerealityExperimentOrchestrator.apk'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-orchestrator-chain-validation\" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
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
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-orchestrator-apk.ps1')
}
foreach ($apk in @($QuestionnaireApk, $SourceHookStubApk, $OrchestratorApk)) {
    if (-not (Test-Path -LiteralPath $apk)) {
        throw "Required APK not found: $apk"
    }
}

$installQuestionnaire = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $OutputRoot 'install-questionnaire.txt')
$installSourceHook = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $SourceHookStubApk) -OutputPath (Join-Path $OutputRoot 'install-source-hook-stub.txt')
$installOrchestrator = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $OrchestratorApk) -OutputPath (Join-Path $OutputRoot 'install-orchestrator.txt')
if ($installQuestionnaire -ne 0 -or $installSourceHook -ne 0 -or $installOrchestrator -ne 0) {
    throw "APK install failed. See $OutputRoot"
}

Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-questionnaire.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $sourcePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-source-hook-stub.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $orchestratorPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-orchestrator.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', "rm -rf '$questionnaireExports' '$orchestratorState' && mkdir -p '$questionnaireFiles' '$orchestratorFiles'") -OutputPath (Join-Path $OutputRoot 'clear-state.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$chainId = "orchestrator-chain-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
$planPath = Join-Path $OutputRoot 'orchestrator-chain-plan.json'
$plan = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.chain-plan.v1'
    chainId = $chainId
    questionnaireId = 'viscereality-maia2'
    questionnaireVersion = '1.0.0'
    defaultFinishBehavior = 'resumeCaller'
    steps = @(
        [ordered]@{
            id = 'source-hook-before-questionnaire'
            type = 'scenario'
            package = $sourcePackage
            activity = $sourceActivity
            action = 'org.viscereality.CHAIN_COMMAND'
            command = 'startScenario'
            extras = [ordered]@{
                scenarioId = 'source-hook-before'
                'mq.autoContinueDelayMs' = 1200
            }
        },
        [ordered]@{
            id = 'questionnaire-mid-chain'
            type = 'questionnaire'
            package = $questionnairePackage
            activity = '.MainActivity'
            extras = [ordered]@{
                'mq.sessionId' = "$chainId-session"
                'mq.experimentId' = 'orchestrator-validation'
                'mq.scenarioId' = 'source-hook-before'
                'mq.trialId' = 'trial-01'
                'mq.participantId' = 'OrchestratorP001'
                'mq.participantName' = 'OrchestratorP001'
                'mq.language' = 'English'
                'mq.autoCloseDelayMs' = 0
            }
        },
        [ordered]@{
            id = 'source-hook-after-questionnaire'
            type = 'scenario'
            package = $sourcePackage
            activity = $sourceActivity
            action = 'org.viscereality.CHAIN_COMMAND'
            command = 'startScenario'
            extras = [ordered]@{
                scenarioId = 'source-hook-after'
                'mq.autoContinueDelayMs' = 1200
            }
        }
    )
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding UTF8

$marker = Join-Path $OutputRoot 'command-replay-english.json'
@{ ParticipantName = 'OrchestratorP001'; ExpectedAge = 33; GenderFocusId = 'gender.0' } |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $marker -Encoding UTF8

$pushMarker = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $marker, "$questionnaireFiles/command-replay-english.json") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-marker-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-marker-stderr.txt')
if ($pushMarker.ExitCode -ne 0) {
    throw "Could not push orchestrator chain input marker."
}

$planJsonExtra = Get-Content -LiteralPath $planPath -Raw
$planBase64Extra = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($planJsonExtra))
$launchExitCode = Invoke-AdbText -Arguments @(
    'shell', 'am', 'start',
    '-a', $orchestratorAction,
    '-n', "$orchestratorPackage/$orchestratorActivity",
    '--es', 'mq.brokerCommand', 'startPlan',
    '--es', 'mq.chainPlanBase64', $planBase64Extra
) -OutputPath (Join-Path $OutputRoot 'launch-orchestrator.txt')

Start-Sleep -Seconds $WaitSeconds
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $OutputRoot 'logcat.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'ViscerealityOrchestrator:I', 'ViscerealitySourceHook:I', 'MyQuestionnaire2D:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-chain.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $OutputRoot 'foreground-after.txt') | Out-Null

$pullRoot = Join-Path $OutputRoot 'device-files'
if (Test-Path -LiteralPath $pullRoot) { Remove-Item -LiteralPath $pullRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pullRoot | Out-Null
$questionnairePullBase = Join-Path $pullRoot 'questionnaire'
$orchestratorPullBase = Join-Path $pullRoot 'orchestrator'
New-Item -ItemType Directory -Force -Path $questionnairePullBase | Out-Null
New-Item -ItemType Directory -Force -Path $orchestratorPullBase | Out-Null
$pullQuestionnaire = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $questionnaireExports, $questionnairePullBase) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-questionnaire-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-questionnaire-stderr.txt')
$pullOrchestrator = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $orchestratorState, $orchestratorPullBase) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-orchestrator-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-orchestrator-stderr.txt')

$logText = Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat.txt') -Raw
$fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
$orchestratorScenarioBeforeCount = @([regex]::Matches($logText, 'ORCHESTRATOR status=app:source-hook-before-questionnaire')).Count
$orchestratorQuestionnaireCount = @([regex]::Matches($logText, 'ORCHESTRATOR status=questionnaire:questionnaire-mid-chain')).Count
$orchestratorScenarioAfterCount = @([regex]::Matches($logText, 'ORCHESTRATOR status=app:source-hook-after-questionnaire')).Count
$orchestratorCompleteCount = @([regex]::Matches($logText, 'ORCHESTRATOR status=plan-complete')).Count
$sourceHookReceivedCount = @([regex]::Matches($logText, 'SOURCE_HOOK_STUB_RECEIVED')).Count
$sourceHookContinueCount = @([regex]::Matches($logText, 'SOURCE_HOOK_STUB_BROKER_CONTINUE')).Count
$exportCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_EXPORT_COMPLETE')).Count
$exportMatchCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH')).Count

$questionnairePull = Join-Path $pullRoot 'questionnaire\QuestionnaireExports'
$orchestratorPull = Join-Path $pullRoot 'orchestrator\ExperimentOrchestrator'
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
if (Test-Path -LiteralPath $questionnairePull) {
    $jsonExportFiles = @(Get-ChildItem -LiteralPath $questionnairePull -File -Filter '*.json' -ErrorAction SilentlyContinue)
    $csvExportFiles = @(Get-ChildItem -LiteralPath $questionnairePull -File -Filter '*.csv' -ErrorAction SilentlyContinue)
    $draftRoot = Join-Path $questionnairePull 'in_progress'
    if (Test-Path -LiteralPath $draftRoot) {
        $draftFiles = @(Get-ChildItem -LiteralPath $draftRoot -File -Filter '*.json' -ErrorAction SilentlyContinue)
    }
    $indexPath = Join-Path $questionnairePull 'session-index.jsonl'
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

$stateStatus = ''
$stateStepIndex = -1
$stateFile = Join-Path $orchestratorPull 'orchestrator-state.json'
if (Test-Path -LiteralPath $stateFile) {
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    $stateStatus = [string]$state.status
    $stateStepIndex = [int]$state.currentStepIndex
}

$questionnaireExpectedCountsOk = ($maia2AnswerCount -eq 37 -and $maia2ScoreCount -eq 8 -and $pictographicSelectionCount -eq 3 -and $sliderAnswerCount -eq 42)
$status = 'pass'
if ($installQuestionnaire -ne 0 -or $installSourceHook -ne 0 -or $installOrchestrator -ne 0 -or $launchExitCode -ne 0 -or $pullQuestionnaire.ExitCode -ne 0 -or $pullOrchestrator.ExitCode -ne 0 -or $fatalLogCount -ne 0) {
    $status = 'fail'
}
if ($orchestratorScenarioBeforeCount -lt 1 -or $orchestratorQuestionnaireCount -lt 1 -or $orchestratorScenarioAfterCount -lt 1 -or $orchestratorCompleteCount -lt 1) {
    $status = 'fail'
}
if ($sourceHookReceivedCount -lt 2 -or $sourceHookContinueCount -lt 2) {
    $status = 'fail'
}
if ($exportCompleteCount -lt 1 -or $exportMatchCount -lt 1 -or -not $questionnaireExpectedCountsOk -or $exportChainId -ne $chainId -or $exportChainStepId -ne 'questionnaire-mid-chain') {
    $status = 'fail'
}
if ($stateStatus -ne 'complete' -or $stateStepIndex -ne 2) {
    $status = 'fail'
}

$summary = [ordered]@{
    schemaVersion = 'viscereality.orchestrator-chain-validation.v1'
    status = $status
    serial = $Serial
    questionnaireApk = $QuestionnaireApk
    sourceHookStubApk = $SourceHookStubApk
    orchestratorApk = $OrchestratorApk
    orchestratorPackage = $orchestratorPackage
    orchestratorActivity = $orchestratorActivity
    chainPlan = $planPath
    evidenceDir = $OutputRoot
    launchExitCode = $launchExitCode
    pullQuestionnaireExitCode = $pullQuestionnaire.ExitCode
    pullOrchestratorExitCode = $pullOrchestrator.ExitCode
    fatalLogCount = $fatalLogCount
    orchestratorScenarioBeforeCount = $orchestratorScenarioBeforeCount
    orchestratorQuestionnaireCount = $orchestratorQuestionnaireCount
    orchestratorScenarioAfterCount = $orchestratorScenarioAfterCount
    orchestratorCompleteCount = $orchestratorCompleteCount
    sourceHookReceivedCount = $sourceHookReceivedCount
    sourceHookContinueCount = $sourceHookContinueCount
    exportCompleteCount = $exportCompleteCount
    exportMatchCount = $exportMatchCount
    stateStatus = $stateStatus
    stateStepIndex = $stateStepIndex
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
$summaryPath = Join-Path $OutputRoot 'quest-orchestrator-chain-validation-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest orchestrator chain validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest orchestrator chain validation failed. See $summaryPath"
}
