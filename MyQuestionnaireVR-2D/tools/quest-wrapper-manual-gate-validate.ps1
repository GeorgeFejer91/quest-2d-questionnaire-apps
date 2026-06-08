param(
    [ValidateSet('Start','Continue','Full')]
    [string]$Mode = 'Full',
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$QuestionnaireApk = "",
    [string]$WrapperApk = "",
    [string]$OrchestratorApk = "",
    [string]$TargetPackage = "org.questquestionnaire.stimulusdemo",
    [string]$TargetActivity = "com.unity3d.player.UnityPlayerGameActivity",
    [string]$ChainPlanPath = "",
    [string]$OutputRoot = "",
    [int]$ScenarioWarmupSeconds = 10,
    [int]$QuestionnaireWaitSeconds = 42,
    [int]$AutoContinueAfterSeconds = -1,
    [switch]$PauseForOperator,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.questquestionnaire.questionnaires2d"
$wrapperPackage = "org.questquestionnaire.chainhookwrapper"
$orchestratorPackage = "org.questquestionnaire.orchestrator"
$orchestratorActivity = "org.questquestionnaire.orchestrator.ExperimentOrchestratorActivity"
$orchestratorAction = "org.questquestionnaire.orchestrator.BROKER"
$questionnaireFiles = "/sdcard/Android/data/$questionnairePackage/files"
$questionnaireExports = "$questionnaireFiles/QuestionnaireExports"
$orchestratorFiles = "/sdcard/Android/data/$orchestratorPackage/files"
$orchestratorState = "$orchestratorFiles/ExperimentOrchestrator"

if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $QuestionnaireApk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
}
if ([string]::IsNullOrWhiteSpace($WrapperApk)) {
    $WrapperApk = Join-Path $ProjectPath 'Builds\QuestQuestionnaireChainHookWrapper.apk'
}
if ([string]::IsNullOrWhiteSpace($OrchestratorApk)) {
    $OrchestratorApk = Join-Path $ProjectPath 'Builds\QuestQuestionnaireExperimentOrchestrator.apk'
}
if ([string]::IsNullOrWhiteSpace($ChainPlanPath)) {
    $ChainPlanPath = Join-Path $ProjectPath 'QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\qmanual\" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
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

function Ensure-ObjectProperty {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Ensure-StepExtras {
    param($Step)
    if (-not $Step.extras) {
        Ensure-ObjectProperty -Object $Step -Name 'extras' -Value ([pscustomobject]@{})
    }
    return $Step.extras
}

function Prepare-ManualGatePlan {
    param($Plan)
    foreach ($step in @($Plan.steps)) {
        if ($step.package -eq $wrapperPackage) {
            $extras = Ensure-StepExtras -Step $step
            Ensure-ObjectProperty -Object $extras -Name 'targetPackage' -Value $TargetPackage
            Ensure-ObjectProperty -Object $extras -Name 'targetActivity' -Value $TargetActivity
            Ensure-ObjectProperty -Object $extras -Name 'mq.autoContinueDelayMs' -Value -1
            Ensure-ObjectProperty -Object $extras -Name 'mq.manualGate' -Value 'operator'
        }
    }
    return $Plan
}

function Count-Regex {
    param([string]$Text, [string]$Pattern)
    return @([regex]::Matches($Text, $Pattern)).Count
}

function Write-OperatorInstructions {
    param([string]$Path)
    $lines = @(
        '# Manual Wrapper Gate',
        '',
        'The legacy scenario has been launched through the wrapper with auto-continue disabled.',
        '',
        '1. Put on the headset.',
        '2. Use the Quest controller to dismiss any Horizon OS controller-required launch prompt.',
        '3. Run or inspect the scenario until it reaches the intended completion point.',
        '4. Return to the host and run:',
        '',
        '```powershell',
        "powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 ``",
        "  -Mode Continue ``",
        "  -Serial $Serial ``",
        "  -OutputRoot `"$OutputRoot`"",
        '```',
        '',
        'The Continue phase sends `mq.brokerCommand=continuePlan` to the standalone orchestrator, then validates the questionnaire export and pulled broker state.'
    )
    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Install-CoreApks {
    if (-not $SkipBuild) {
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-apk.ps1') -SkipTests
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-hook-wrapper-apk.ps1')
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-orchestrator-apk.ps1')
    }
    foreach ($apk in @($QuestionnaireApk, $WrapperApk, $OrchestratorApk)) {
        if (-not (Test-Path -LiteralPath $apk)) {
            throw "Required APK not found: $apk"
        }
    }
    $installQuestionnaire = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $OutputRoot 'install-questionnaire.txt')
    $installWrapper = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $WrapperApk) -OutputPath (Join-Path $OutputRoot 'install-wrapper.txt')
    $installOrchestrator = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $OrchestratorApk) -OutputPath (Join-Path $OutputRoot 'install-orchestrator.txt')
    if ($installQuestionnaire.ExitCode -ne 0 -or $installWrapper.ExitCode -ne 0 -or $installOrchestrator.ExitCode -ne 0) {
        throw "APK install failed. See $OutputRoot"
    }
}

function Start-ManualGate {
    if (-not (Test-Path -LiteralPath $ChainPlanPath)) {
        throw "Chain plan not found: $ChainPlanPath"
    }
    Install-CoreApks
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-questionnaire.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $wrapperPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-wrapper.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $orchestratorPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-orchestrator.txt') | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($TargetPackage)) {
        Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $TargetPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-target.txt') | Out-Null
    }
    Invoke-AdbText -Arguments @('shell', "rm -rf '$questionnaireExports' '$orchestratorState' && mkdir -p '$questionnaireFiles' '$orchestratorFiles'") -OutputPath (Join-Path $OutputRoot 'clear-state.txt') | Out-Null
    Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

    $marker = Join-Path $OutputRoot 'command-replay-english.json'
    @{ ParticipantName = 'ManualGateP001'; ExpectedAge = 33; GenderFocusId = 'gender.0' } |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $marker -Encoding UTF8
    $pushMarker = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $marker, "$questionnaireFiles/command-replay-english.json") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-marker-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-marker-stderr.txt')
    if ($pushMarker.ExitCode -ne 0) {
        throw "Could not push manual-gate command replay marker."
    }

    $plan = Get-Content -LiteralPath $ChainPlanPath -Raw | ConvertFrom-Json
    $plan = Prepare-ManualGatePlan -Plan $plan
    $preparedPlan = Join-Path $OutputRoot 'manual-gate-chain-plan.json'
    $plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $preparedPlan -Encoding UTF8
    $planBase64Extra = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath $preparedPlan -Raw)))
    $launch = Invoke-AdbText -Arguments @(
        'shell', 'am', 'start',
        '-a', $orchestratorAction,
        '-n', "$orchestratorPackage/$orchestratorActivity",
        '--es', 'mq.brokerCommand', 'startPlan',
        '--es', 'mq.chainPlanBase64', $planBase64Extra
    ) -OutputPath (Join-Path $OutputRoot 'launch-orchestrator.txt')

    Start-Sleep -Seconds $ScenarioWarmupSeconds
    Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $OutputRoot 'logcat-before-manual-continue.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $OutputRoot 'foreground-before-manual-continue.txt') | Out-Null
    Write-OperatorInstructions -Path (Join-Path $OutputRoot 'operator-instructions.md')

    $summary = [ordered]@{
        schemaVersion = 'questquestionnaire.wrapper-manual-gate-validation.v1'
        status = if ($launch.ExitCode -eq 0) { 'waiting-for-manual-continue' } else { 'fail' }
        mode = 'Start'
        serial = $Serial
        targetPackage = $TargetPackage
        targetActivity = $TargetActivity
        chainPlan = $preparedPlan
        evidenceDir = $OutputRoot
        launchExitCode = $launch.ExitCode
        operatorInstructions = (Join-Path $OutputRoot 'operator-instructions.md')
        completedAt = (Get-Date).ToString('o')
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'manual-gate-start-summary.json') -Encoding UTF8
    return [pscustomobject]$summary
}

function Continue-ManualGate {
    $manualContinueExtras = [ordered]@{
        'mq.brokerCommand' = 'continuePlan'
        'mq.scenarioResultStatus' = 'manualComplete'
        'mq.scenarioVersion' = 'manual-wrapper-gate'
        'mq.scenarioParticipantDataPath' = 'manual-operator-confirmed'
    }
    $continue = Invoke-AdbText -Arguments @(
        'shell', 'am', 'start',
        '-a', $orchestratorAction,
        '-n', "$orchestratorPackage/$orchestratorActivity",
        '--es', 'mq.brokerCommand', $manualContinueExtras['mq.brokerCommand'],
        '--es', 'mq.scenarioResultStatus', $manualContinueExtras['mq.scenarioResultStatus'],
        '--es', 'mq.scenarioVersion', $manualContinueExtras['mq.scenarioVersion'],
        '--es', 'mq.scenarioParticipantDataPath', $manualContinueExtras['mq.scenarioParticipantDataPath']
    ) -OutputPath (Join-Path $OutputRoot 'continue-orchestrator.txt')

    Start-Sleep -Seconds $QuestionnaireWaitSeconds
    Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $OutputRoot 'logcat-after-manual-continue.txt') | Out-Null
    Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'Quest 2D QuestionnaireOrchestrator:I', 'QuestQuestionnaireChainHook:I', 'MyQuestionnaire2D:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-chain-after-manual-continue.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $OutputRoot 'foreground-after-manual-continue.txt') | Out-Null

    $pullRoot = Join-Path $OutputRoot 'files-after'
    if (Test-Path -LiteralPath $pullRoot) { Remove-Item -LiteralPath $pullRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $pullRoot | Out-Null
    $questionnairePullBase = Join-Path $pullRoot 'questionnaire'
    $orchestratorPullBase = Join-Path $pullRoot 'orchestrator'
    New-Item -ItemType Directory -Force -Path $questionnairePullBase | Out-Null
    New-Item -ItemType Directory -Force -Path $orchestratorPullBase | Out-Null
    $pullQuestionnaire = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $questionnaireExports, $questionnairePullBase) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-questionnaire-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-questionnaire-stderr.txt')
    $pullOrchestrator = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $orchestratorState, $orchestratorPullBase) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-orchestrator-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-orchestrator-stderr.txt')

    $logText = Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat-after-manual-continue.txt') -Raw
    $fatalLogCount = Count-Regex -Text $logText -Pattern 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b'
    $orchestratorCompleteCount = Count-Regex -Text $logText -Pattern 'ORCHESTRATOR status=plan-complete'
    $exportCompleteCount = Count-Regex -Text $logText -Pattern 'MYQUESTIONNAIRE_EXPORT_COMPLETE'
    $exportMatchCount = Count-Regex -Text $logText -Pattern 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH'
    $manualResultCount = Count-Regex -Text $logText -Pattern 'mq\.scenarioResultStatus|manualComplete'

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
        }
    }

    $stateStatus = ''
    $stateStepIndex = -1
    $stateLastResult = $null
    $stateFile = Join-Path $orchestratorPull 'orchestrator-state.json'
    if (Test-Path -LiteralPath $stateFile) {
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $stateStatus = [string]$state.status
        $stateStepIndex = [int]$state.currentStepIndex
        $stateLastResult = $state.lastResult
    }

    $questionnaireExpectedCountsOk = ($maia2AnswerCount -eq 37 -and $maia2ScoreCount -eq 8 -and $pictographicSelectionCount -eq 3 -and $sliderAnswerCount -eq 42)
    $status = 'pass'
    if ($continue.ExitCode -ne 0 -or $pullQuestionnaire.ExitCode -ne 0 -or $pullOrchestrator.ExitCode -ne 0 -or $fatalLogCount -ne 0) {
        $status = 'fail'
    }
    if ($orchestratorCompleteCount -lt 1 -or $exportCompleteCount -lt 1 -or $exportMatchCount -lt 1 -or -not $questionnaireExpectedCountsOk) {
        $status = 'fail'
    }
    if ($stateStatus -ne 'complete') {
        $status = 'fail'
    }

    $summary = [ordered]@{
        schemaVersion = 'questquestionnaire.wrapper-manual-gate-validation.v1'
        status = $status
        mode = 'Continue'
        serial = $Serial
        targetPackage = $TargetPackage
        targetActivity = $TargetActivity
        evidenceDir = $OutputRoot
        continueExitCode = $continue.ExitCode
        manualContinueSent = ($continue.ExitCode -eq 0)
        manualContinueExtras = $manualContinueExtras
        pullQuestionnaireExitCode = $pullQuestionnaire.ExitCode
        pullOrchestratorExitCode = $pullOrchestrator.ExitCode
        fatalLogCount = $fatalLogCount
        orchestratorCompleteCount = $orchestratorCompleteCount
        exportCompleteCount = $exportCompleteCount
        exportMatchCount = $exportMatchCount
        manualResultCount = $manualResultCount
        stateStatus = $stateStatus
        stateStepIndex = $stateStepIndex
        stateLastResult = $stateLastResult
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
        }
        completedAt = (Get-Date).ToString('o')
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputRoot 'quest-wrapper-manual-gate-validation-summary.json') -Encoding UTF8
    return [pscustomObject]$summary
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

$startSummary = $null
if ($Mode -eq 'Start' -or $Mode -eq 'Full') {
    $startSummary = Start-ManualGate
    Write-Host "Manual gate started. Evidence: $OutputRoot"
    Write-Host "Instructions: $(Join-Path $OutputRoot 'operator-instructions.md')"
}

if ($Mode -eq 'Start') {
    return
}

if ($Mode -eq 'Full') {
    if ($PauseForOperator) {
        Read-Host "Run the target scenario in-headset, then press Enter here to continue the orchestrator plan"
    }
    elseif ($AutoContinueAfterSeconds -ge 0) {
        Start-Sleep -Seconds $AutoContinueAfterSeconds
    }
}

$continueSummary = Continue-ManualGate
Write-Host "Manual gate continue evidence written to $OutputRoot"
Write-Host "Summary: $(Join-Path $OutputRoot 'quest-wrapper-manual-gate-validation-summary.json')"
if ($continueSummary.status -ne 'pass') {
    throw "Manual gate validation failed. See $(Join-Path $OutputRoot 'quest-wrapper-manual-gate-validation-summary.json')"
}
