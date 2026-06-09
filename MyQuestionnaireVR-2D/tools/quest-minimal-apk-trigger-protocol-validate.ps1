param(
    [string]$Serial = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$RepoRoot = "",
    [string]$QuestionnaireConfig = "",
    [string]$QuestionnaireApk = "",
    [string]$UnityProjectPath = "",
    [string]$UnityApk = "",
    [string]$UnityPackage = "org.questquestionnaire.circletriggerdemo",
    [string]$UnityActivity = "org.questquestionnaire.circletriggerdemo.QuestQuestionnaireUnityActivity",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [int]$TrialCount = 1,
    [int]$WaitForReadySeconds = 30,
    [int]$ReadinessPollSeconds = 2,
    [int]$WaitSeconds = 45,
    [int]$FocusPollMilliseconds = 750,
    [switch]$RunLive,
    [switch]$SkipQuestionnaireBuild,
    [switch]$SkipInstall,
    [switch]$NoAutoReplay,
    [switch]$WakeBeforeReadiness,
    [switch]$AllowLaunchWhenNotReady,
    [switch]$RunGradleTests,
    [switch]$RunFullLocalProtocol
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-SafeFullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function ConvertTo-SafeFileName {
    param([string]$Name)
    return (($Name -replace '[^A-Za-z0-9_.-]+', '-').Trim('-'))
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [System.Collections.Generic.List[object]]$Steps
    )

    $safeName = ConvertTo-SafeFileName -Name $Name
    $logPath = Join-Path $script:OutputRootFull "$safeName.log"
    $startedAt = (Get-Date).ToUniversalTime().ToString('o')
    $exitCode = 0
    $output = $null
    Push-Location -LiteralPath $WorkingDirectory
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Executable @Arguments 2>&1
        if ($null -ne $LASTEXITCODE) {
            $exitCode = [int]$LASTEXITCODE
        }
    }
    catch {
        $exitCode = 1
        $output = $_
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }

    ($output | Out-String) | Set-Content -LiteralPath $logPath -Encoding UTF8
    $step = [ordered]@{
        name = $Name
        status = if ($exitCode -eq 0) { 'pass' } else { 'fail' }
        exitCode = $exitCode
        executable = $Executable
        arguments = $Arguments
        workingDirectory = $WorkingDirectory
        logPath = $logPath
        startedAt = $startedAt
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $Steps.Add($step) | Out-Null
    return $step
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 12)
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-ConfigApkPath {
    param([string]$ConfigPath)
    $config = Read-JsonFile -Path $ConfigPath
    if (-not $config) {
        return ""
    }
    $safeId = (([string]$config.questionnaireId) -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    $safeVersion = (([string]$config.questionnaireVersion) -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeId)) { $safeId = 'questionnaire' }
    if ([string]::IsNullOrWhiteSpace($safeVersion)) { $safeVersion = '1.0.0' }
    return Join-Path $script:ProjectFull "Builds\$safeId-$safeVersion.apk"
}

$script:ProjectFull = Get-SafeFullPath $ProjectPath
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $script:ProjectFull
}
$repoRootFull = Get-SafeFullPath $RepoRoot
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "quest-minimal-apk-trigger-protocol-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $script:ProjectFull "artifacts\quest-minimal-apk-trigger-protocol\$RunId"
}
$script:OutputRootFull = Get-SafeFullPath $OutputRoot
New-Item -ItemType Directory -Force -Path $script:OutputRootFull | Out-Null

if ([string]::IsNullOrWhiteSpace($QuestionnaireConfig)) {
    $QuestionnaireConfig = Join-Path $script:ProjectFull 'QuestionnaireConfigs\examples\quest-questionnaire-three-circle-protocol-demo.config.json'
}
if ([string]::IsNullOrWhiteSpace($UnityApk)) {
    $UnityApk = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo\Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk'
}
if ([string]::IsNullOrWhiteSpace($UnityProjectPath)) {
    $UnityProjectPath = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo'
}
$QuestionnaireConfig = Get-SafeFullPath $QuestionnaireConfig
$UnityProjectPath = Get-SafeFullPath $UnityProjectPath
$UnityApk = Get-SafeFullPath $UnityApk
if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $QuestionnaireApk = Get-ConfigApkPath -ConfigPath $QuestionnaireConfig
}
$QuestionnaireApk = Get-SafeFullPath $QuestionnaireApk

if ($RunLive -and [string]::IsNullOrWhiteSpace($Serial)) {
    throw "Live Quest validation requires -Serial. Run without -RunLive for dry-run preflight only."
}

$steps = New-Object 'System.Collections.Generic.List[object]'
$buildSummary = $null

$passiveSummaryPath = Join-Path $script:OutputRootFull 'passive-trigger-protocol-summary.json'
Invoke-Step `
    -Name 'passive-trigger-protocol' `
    -Executable 'powershell' `
    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:ProjectFull 'tools\validate-passive-trigger-protocol.ps1'), '-ProjectPath', $script:ProjectFull, '-ApkPath', $UnityApk, '-OutputPath', $passiveSummaryPath) `
    -WorkingDirectory $script:ProjectFull `
    -Steps $steps | Out-Null

Invoke-Step `
    -Name 'questionnaire-config-validation' `
    -Executable 'powershell' `
    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:ProjectFull 'tools\validate-questionnaire-config.ps1'), '-ConfigPath', $QuestionnaireConfig) `
    -WorkingDirectory $script:ProjectFull `
    -Steps $steps | Out-Null

if ($RunGradleTests) {
    Invoke-Step `
        -Name 'android-trigger-contract-tests' `
        -Executable (Join-Path $script:ProjectFull 'gradlew.bat') `
        -Arguments @(':app:testDebugUnitTest', '--tests', 'org.questquestionnaire.questionnaires2d.ChainLaunchContractTest', '--tests', 'org.questquestionnaire.questionnaires2d.QuestChainBrokerTest') `
        -WorkingDirectory $script:ProjectFull `
        -Steps $steps | Out-Null
}

$minimalSummaryPath = ''
if ($RunFullLocalProtocol) {
    $minimalOutput = Join-Path $script:OutputRootFull 'local-minimal-protocol'
    Invoke-Step `
        -Name 'local-minimal-protocol' `
        -Executable 'powershell' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:ProjectFull 'tools\validate-minimal-apk-trigger-protocol.ps1'), '-ProjectPath', $script:ProjectFull, '-RepoRoot', $repoRootFull, '-UnityApk', $UnityApk, '-OutputRoot', $minimalOutput, '-SkipQuestionnaireApkBuild', '-SkipUnityInputModality', '-SkipGradleTests') `
        -WorkingDirectory $script:ProjectFull `
        -Steps $steps | Out-Null
    $minimalSummaryPath = Join-Path $minimalOutput 'minimal-apk-trigger-protocol-summary.json'
}

$unityInputOutput = Join-Path $script:ProjectFull "artifacts\qmin\$RunId\unity-input"
Invoke-Step `
    -Name 'unity-input-modality' `
    -Executable 'powershell' `
    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:ProjectFull 'tools\validate-unity-input-modality.ps1'), '-UnityProjectPath', $UnityProjectPath, '-UnityApk', $UnityApk, '-OutputRoot', $unityInputOutput) `
    -WorkingDirectory $script:ProjectFull `
    -Steps $steps | Out-Null

if ((-not $SkipQuestionnaireBuild) -or (-not (Test-Path -LiteralPath $QuestionnaireApk))) {
    $generatorOutput = Join-Path $script:OutputRootFull 'questionnaire-apk-generator'
    Invoke-Step `
        -Name 'generate-three-circle-questionnaire-apk' `
        -Executable 'powershell' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:ProjectFull 'tools\generate-questionnaire-apk.ps1'), '-ConfigPath', $QuestionnaireConfig, '-RunId', 'quest-minimal-three-circle', '-SkipTests') `
        -WorkingDirectory $script:ProjectFull `
        -Steps $steps | Out-Null
    $buildSummary = Read-JsonFile -Path (Join-Path $script:ProjectFull 'artifacts\apk-generator\quest-minimal-three-circle\generator-summary.json')
    if ($buildSummary -and $buildSummary.apk) {
        $QuestionnaireApk = Get-SafeFullPath ([string]$buildSummary.apk)
    }
} else {
    $buildSummary = [pscustomobject]@{
        status = 'skipped'
        apk = $QuestionnaireApk
        sourceConfig = $QuestionnaireConfig
    }
}

$frontDoorOutput = Join-Path $script:ProjectFull "artifacts\qmin\$RunId\front-door"
$frontDoorArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $script:ProjectFull 'tools\quest-2d-first-launcher-validate.ps1'),
    '-ProjectPath', $script:ProjectFull,
    '-RepoRoot', $repoRootFull,
    '-QuestionnaireApk', $QuestionnaireApk,
    '-UnityApk', $UnityApk,
    '-UnityPackage', $UnityPackage,
    '-UnityActivity', $UnityActivity,
    '-OutputRoot', $frontDoorOutput,
    '-TrialCount', "$TrialCount",
    '-WaitForReadySeconds', "$WaitForReadySeconds",
    '-ReadinessPollSeconds', "$ReadinessPollSeconds",
    '-WaitSeconds', "$WaitSeconds",
    '-FocusPollMilliseconds', "$FocusPollMilliseconds"
)
if (-not $RunLive) {
    $frontDoorArgs += '-DryRun'
} else {
    $frontDoorArgs += @('-Serial', $Serial)
}
if ($SkipInstall) { $frontDoorArgs += '-SkipInstall' }
if ($NoAutoReplay) { $frontDoorArgs += '-NoAutoReplay' }
if ($WakeBeforeReadiness) { $frontDoorArgs += '-WakeBeforeReadiness' }
if ($AllowLaunchWhenNotReady) { $frontDoorArgs += '-AllowLaunchWhenNotReady' }

Invoke-Step `
    -Name 'quest-2d-first-front-door' `
    -Executable 'powershell' `
    -Arguments $frontDoorArgs `
    -WorkingDirectory $script:ProjectFull `
    -Steps $steps | Out-Null

$unityInputSummaryPath = Join-Path $unityInputOutput 'unity-input-modality-summary.json'
$frontDoorSummaryPath = Join-Path $frontDoorOutput 'quest-2d-first-launcher-validation-summary.json'
$passiveSummary = Read-JsonFile -Path $passiveSummaryPath
$minimalSummary = if ([string]::IsNullOrWhiteSpace($minimalSummaryPath)) { $null } else { Read-JsonFile -Path $minimalSummaryPath }
$unityInputSummary = Read-JsonFile -Path $unityInputSummaryPath
$frontDoorSummary = Read-JsonFile -Path $frontDoorSummaryPath

$stepArray = @($steps.ToArray())
$stepFailures = @($stepArray | Where-Object { [string]$_.status -ne 'pass' })
$passiveOk = $passiveSummary -and [string]$passiveSummary.status -eq 'pass'
$minimalOk = (-not $RunFullLocalProtocol) -or ($minimalSummary -and [string]$minimalSummary.status -eq 'pass')
$unityInputOk = $unityInputSummary -and [string]$unityInputSummary.status -eq 'pass'
$frontDoorOk = $frontDoorSummary -and [string]$frontDoorSummary.status -eq 'pass'
$overallStatus = if ($stepFailures.Count -eq 0 -and $passiveOk -and $minimalOk -and $unityInputOk -and $frontDoorOk) { 'pass' } else { 'fail' }

$remainingLiveGates = @()
if (-not $RunLive) {
    $remainingLiveGates = @(
        'install generated questionnaire APK and immersive Unity APK on an explicit Quest serial',
        'participant starts the generated questionnaire APK from Meta Home',
        'Block 1 saves and launches Unity without shell foreground switching',
        'operator/participant fires a Unity trigger inside the immersive app',
        'questionnaire APK resumes the mapped return block from its own protocol state',
        'exports are pulled from the generated questionnaire APK directory'
    )
} else {
    $remainingLiveGates = @(
        'manual operator signoff that Unity trigger input occurred inside the foreground immersive app',
        'optional export audit after each trigger-return block when the live trial covers more than block 1'
    )
}

$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.quest-minimal-apk-trigger-protocol.validation.v1'
    status = $overallStatus
    runId = $RunId
    runLive = [bool]$RunLive
    serial = $Serial
    projectPath = $script:ProjectFull
    repoRoot = $repoRootFull
    outputRoot = $script:OutputRootFull
    proofBoundary = if ($RunLive) {
        'Live Quest front-door gate attempted. Full trigger-return evidence still requires an observed Unity trigger and export audit.'
    } else {
        'Dry-run preflight only. Local software and packaged APK contracts passed, but no physical Quest install, launch, Unity trigger, or export pull was attempted.'
    }
    productContract = [ordered]@{
        participantFrontDoor = 'generated 2D questionnaire APK'
        unityRole = 'immersive stimulus APK that displays content and emits passive trigger ids'
        questionnaireRole = 'study logic owner: block order, trigger interpretation, participant/session state, repeat rules, and exports'
        unityLaunchDependency = 'Unity receives mq.triggerReceiver* extras from the questionnaire APK; public demos do not hard-code questionnaire fallback'
    }
    inputs = [ordered]@{
        questionnaireConfig = $QuestionnaireConfig
        questionnaireApk = $QuestionnaireApk
        unityProjectPath = $UnityProjectPath
        unityApk = $UnityApk
        unityPackage = $UnityPackage
        unityActivity = $UnityActivity
    }
    evidence = [ordered]@{
        passiveTriggerProtocolSummary = $passiveSummaryPath
        localMinimalProtocolSummary = $minimalSummaryPath
        unityInputModalitySummary = $unityInputSummaryPath
        questionnaireGeneratorSummary = if ($buildSummary -and $buildSummary.sourceConfig) { [string](Join-Path $script:ProjectFull 'artifacts\apk-generator\quest-minimal-three-circle\generator-summary.json') } else { '' }
        twoDFirstFrontDoorSummary = $frontDoorSummaryPath
    }
    statuses = [ordered]@{
        passiveTriggerProtocol = if ($passiveSummary) { [string]$passiveSummary.status } else { 'missing' }
        localMinimalProtocol = if ($RunFullLocalProtocol) { if ($minimalSummary) { [string]$minimalSummary.status } else { 'missing' } } else { 'skipped' }
        gradleTriggerContractTests = if ($RunGradleTests) { if (@($stepArray | Where-Object { $_.name -eq 'android-trigger-contract-tests' -and $_.status -eq 'pass' }).Count -gt 0) { 'pass' } else { 'fail' } } else { 'skipped' }
        unityInputModality = if ($unityInputSummary) { [string]$unityInputSummary.status } else { 'missing' }
        twoDFirstFrontDoor = if ($frontDoorSummary) { [string]$frontDoorSummary.status } else { 'missing' }
        questionnaireApkGenerated = if (Test-Path -LiteralPath $QuestionnaireApk) { 'present' } else { 'missing' }
        unityApk = if (Test-Path -LiteralPath $UnityApk) { 'present' } else { 'missing' }
    }
    steps = $stepArray
    failedStepCount = $stepFailures.Count
    remainingLiveGates = $remainingLiveGates
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $script:OutputRootFull 'quest-minimal-apk-trigger-protocol-summary.json'
Write-Json -Value $summary -Path $summaryPath -Depth 16

[pscustomobject]@{
    Status = $summary.status
    RunLive = $summary.runLive
    Summary = $summaryPath
    ProofBoundary = $summary.proofBoundary
}

if ($overallStatus -ne 'pass') {
    throw "Quest minimal APK trigger protocol validation failed. See $summaryPath"
}

exit 0
