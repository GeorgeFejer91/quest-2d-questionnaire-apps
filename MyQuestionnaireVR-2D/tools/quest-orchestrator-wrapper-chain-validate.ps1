param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$QuestionnaireApk = "",
    [string]$WrapperApk = "",
    [string]$OrchestratorApk = "",
    [string]$TargetPackage = "com.Viscereality.ViscerealityPeriPersonalSpaceRight",
    [string]$TargetActivity = "com.unity3d.player.UnityPlayerGameActivity",
    [string]$ChainPlanPath = "",
    [string]$OutputRoot = "",
    [int]$WaitSeconds = 52,
    [int]$WrapperAutoContinueDelayMs = 10000,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.viscereality.questionnaires2d"
$wrapperPackage = "org.viscereality.chainhookwrapper"
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
if ([string]::IsNullOrWhiteSpace($WrapperApk)) {
    $WrapperApk = Join-Path $ProjectPath 'Builds\ViscerealityChainHookWrapper.apk'
}
if ([string]::IsNullOrWhiteSpace($OrchestratorApk)) {
    $OrchestratorApk = Join-Path $ProjectPath 'Builds\ViscerealityExperimentOrchestrator.apk'
}
if ([string]::IsNullOrWhiteSpace($ChainPlanPath)) {
    $ChainPlanPath = Join-Path $ProjectPath 'QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-orchestrator-wrapper-chain-validation\" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
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

function Prepare-Plan {
    param($Plan)
    foreach ($step in @($Plan.steps)) {
        if ($step.package -eq $wrapperPackage) {
            $extras = Ensure-StepExtras -Step $step
            if (-not [string]::IsNullOrWhiteSpace($TargetPackage)) {
                Ensure-ObjectProperty -Object $extras -Name 'targetPackage' -Value $TargetPackage
            }
            if (-not [string]::IsNullOrWhiteSpace($TargetActivity)) {
                Ensure-ObjectProperty -Object $extras -Name 'targetActivity' -Value $TargetActivity
            }
            if ($WrapperAutoContinueDelayMs -ge 0 -and -not ($extras.PSObject.Properties.Name -contains 'mq.autoContinueDelayMs')) {
                Ensure-ObjectProperty -Object $extras -Name 'mq.autoContinueDelayMs' -Value $WrapperAutoContinueDelayMs
            }
        }
    }
    return $Plan
}

function Count-Regex {
    param([string]$Text, [string]$Pattern)
    return @([regex]::Matches($Text, $Pattern)).Count
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
foreach ($apk in @($QuestionnaireApk, $WrapperApk, $OrchestratorApk)) {
    if (-not (Test-Path -LiteralPath $apk)) {
        throw "Required APK not found: $apk"
    }
}
if (-not (Test-Path -LiteralPath $ChainPlanPath)) {
    throw "Chain plan not found: $ChainPlanPath"
}

$installQuestionnaire = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $OutputRoot 'install-questionnaire.txt')
$installWrapper = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $WrapperApk) -OutputPath (Join-Path $OutputRoot 'install-wrapper.txt')
$installOrchestrator = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $OrchestratorApk) -OutputPath (Join-Path $OutputRoot 'install-orchestrator.txt')
if ($installQuestionnaire -ne 0 -or $installWrapper -ne 0 -or $installOrchestrator -ne 0) {
    throw "APK install failed. See $OutputRoot"
}

Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $OutputRoot 'force-stop-questionnaire.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $wrapperPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-wrapper.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $orchestratorPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-orchestrator.txt') | Out-Null
if (-not [string]::IsNullOrWhiteSpace($TargetPackage)) {
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $TargetPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-target.txt') | Out-Null
}
Invoke-AdbText -Arguments @('shell', "rm -rf '$questionnaireExports' '$orchestratorState' && mkdir -p '$questionnaireFiles' '$orchestratorFiles'") -OutputPath (Join-Path $OutputRoot 'clear-state.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$plan = Get-Content -LiteralPath $ChainPlanPath -Raw | ConvertFrom-Json
$plan = Prepare-Plan -Plan $plan
$preparedPlan = Join-Path $OutputRoot 'prepared-chain-plan.json'
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $preparedPlan -Encoding UTF8
$chainId = [string]$plan.chainId
$wrapperStepIds = @($plan.steps | Where-Object { $_.package -eq $wrapperPackage } | ForEach-Object { [string]$_.id })
$questionnaireStepIds = @($plan.steps | Where-Object { $_.type -eq 'questionnaire' } | ForEach-Object { [string]$_.id })
$lastStepIndex = @($plan.steps).Count - 1

$marker = Join-Path $OutputRoot 'command-replay-english.json'
@{ ParticipantName = 'OrchestratorWrapperP001'; ExpectedAge = 33; GenderFocusId = 'gender.0' } |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $marker -Encoding UTF8

$pushMarker = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $marker, "$questionnaireFiles/command-replay-english.json") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-marker-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-marker-stderr.txt')
if ($pushMarker.ExitCode -ne 0) {
    throw "Could not push orchestrator wrapper chain input marker."
}

$planJsonExtra = Get-Content -LiteralPath $preparedPlan -Raw
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
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'ViscerealityOrchestrator:I', 'ViscerealityChainHook:I', 'MyQuestionnaire2D:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-chain.txt') | Out-Null
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
$foregroundText = Get-Content -LiteralPath (Join-Path $OutputRoot 'foreground-after.txt') -Raw
$fatalLogCount = Count-Regex -Text $logText -Pattern 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b'
$orchestratorCompleteCount = Count-Regex -Text $logText -Pattern 'ORCHESTRATOR status=plan-complete'
$hookReceivedCount = Count-Regex -Text $logText -Pattern 'CHAIN_HOOK_RECEIVED'
$hookTargetStartedCount = Count-Regex -Text $logText -Pattern 'CHAIN_HOOK_TARGET_STARTED'
$hookTargetFailedCount = Count-Regex -Text $logText -Pattern 'CHAIN_HOOK_TARGET_START_FAILED'
$hookBrokerContinueCount = Count-Regex -Text $logText -Pattern 'CHAIN_HOOK_BROKER_CONTINUE'
$exportCompleteCount = Count-Regex -Text $logText -Pattern 'MYQUESTIONNAIRE_EXPORT_COMPLETE'
$exportMatchCount = Count-Regex -Text $logText -Pattern 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH'
$launchCheckControllerRequiredCount = (Count-Regex -Text $logText -Pattern 'REQUIRES_CONTROLLERS_LAUNCH_CHECK|LaunchCheckControllerRequiredDialogActivity|common_system_dialog_app_launch_blocked_controller_required') + (Count-Regex -Text $foregroundText -Pattern 'LaunchCheckControllerRequiredDialogActivity')
$foregroundFocusLines = @($foregroundText -split "`r?`n" | Where-Object { $_ -match 'mCurrentFocus|mFocusedApp|mResumedActivity|mFocusedWindow' })

$orchestratorAppStepCounts = [ordered]@{}
foreach ($stepId in $wrapperStepIds) {
    $orchestratorAppStepCounts[$stepId] = Count-Regex -Text $logText -Pattern ([regex]::Escape("ORCHESTRATOR status=app:$stepId"))
}
$orchestratorQuestionnaireStepCounts = [ordered]@{}
foreach ($stepId in $questionnaireStepIds) {
    $orchestratorQuestionnaireStepCounts[$stepId] = Count-Regex -Text $logText -Pattern ([regex]::Escape("ORCHESTRATOR status=questionnaire:$stepId"))
}

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
$allAppStepsSeen = $true
foreach ($key in $orchestratorAppStepCounts.Keys) {
    if ($orchestratorAppStepCounts[$key] -lt 1) { $allAppStepsSeen = $false }
}
$allQuestionnaireStepsSeen = $true
foreach ($key in $orchestratorQuestionnaireStepCounts.Keys) {
    if ($orchestratorQuestionnaireStepCounts[$key] -lt 1) { $allQuestionnaireStepsSeen = $false }
}
$warnings = @()
if ($launchCheckControllerRequiredCount -gt 0) {
    $warnings += 'Horizon OS showed a controller-required launch check for the target APK; this proves launch routing but still needs a human/controller gate to prove target scenario progress past that system dialog.'
}

$status = 'pass'
if ($installQuestionnaire -ne 0 -or $installWrapper -ne 0 -or $installOrchestrator -ne 0 -or $launchExitCode -ne 0 -or $pullQuestionnaire.ExitCode -ne 0 -or $pullOrchestrator.ExitCode -ne 0 -or $fatalLogCount -ne 0) {
    $status = 'fail'
}
if (-not $allAppStepsSeen -or -not $allQuestionnaireStepsSeen -or $orchestratorCompleteCount -lt 1) {
    $status = 'fail'
}
if ($hookReceivedCount -lt @($wrapperStepIds).Count -or $hookTargetStartedCount -lt @($wrapperStepIds).Count -or $hookTargetFailedCount -gt 0) {
    $status = 'fail'
}
if (@($wrapperStepIds).Count -gt 0 -and $WrapperAutoContinueDelayMs -ge 0 -and $hookBrokerContinueCount -lt @($wrapperStepIds).Count) {
    $status = 'fail'
}
if (@($questionnaireStepIds).Count -gt 0 -and ($exportCompleteCount -lt 1 -or $exportMatchCount -lt 1 -or -not $questionnaireExpectedCountsOk -or $exportChainId -ne $chainId -or ($questionnaireStepIds -notcontains $exportChainStepId))) {
    $status = 'fail'
}
if ($stateStatus -ne 'complete' -or $stateStepIndex -ne $lastStepIndex) {
    $status = 'fail'
}

$summary = [ordered]@{
    schemaVersion = 'viscereality.orchestrator-wrapper-chain-validation.v1'
    status = $status
    serial = $Serial
    questionnaireApk = $QuestionnaireApk
    wrapperApk = $WrapperApk
    orchestratorApk = $OrchestratorApk
    targetPackage = $TargetPackage
    targetActivity = $TargetActivity
    orchestratorPackage = $orchestratorPackage
    orchestratorActivity = $orchestratorActivity
    chainPlan = $preparedPlan
    evidenceDir = $OutputRoot
    launchExitCode = $launchExitCode
    pullQuestionnaireExitCode = $pullQuestionnaire.ExitCode
    pullOrchestratorExitCode = $pullOrchestrator.ExitCode
    fatalLogCount = $fatalLogCount
    orchestratorAppStepCounts = $orchestratorAppStepCounts
    orchestratorQuestionnaireStepCounts = $orchestratorQuestionnaireStepCounts
    orchestratorCompleteCount = $orchestratorCompleteCount
    hookReceivedCount = $hookReceivedCount
    hookTargetStartedCount = $hookTargetStartedCount
    hookTargetFailedCount = $hookTargetFailedCount
    hookBrokerContinueCount = $hookBrokerContinueCount
    exportCompleteCount = $exportCompleteCount
    exportMatchCount = $exportMatchCount
    launchCheckControllerRequiredCount = $launchCheckControllerRequiredCount
    foregroundFocusLines = $foregroundFocusLines
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
    warnings = $warnings
    completedAt = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $OutputRoot 'quest-orchestrator-wrapper-chain-validation-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest orchestrator wrapper chain validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest orchestrator wrapper chain validation failed. See $summaryPath"
}
