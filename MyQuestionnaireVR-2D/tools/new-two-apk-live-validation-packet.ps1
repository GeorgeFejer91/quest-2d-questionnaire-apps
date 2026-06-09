param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$RepoRoot = "",
    [string]$QuestionnaireConfig = "",
    [string]$QuestionnaireApk = "",
    [string]$UnityProjectPath = "",
    [string]$UnityApk = "",
    [string]$QuestSerial = "",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [switch]$SkipDryRunPreflight,
    [string]$OperatorSignoffPath = "",
    [switch]$RequirePass
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-SafeFullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 20)
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-Prop {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-FileEvidence {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ path = $Path; exists = $false; bytes = 0; sha256 = "" }
    }
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path = $item.FullName
        exists = $true
        bytes = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Get-ConfigApkPath {
    param([string]$ConfigPath, [string]$ProjectPath)
    $config = Read-JsonFile -Path $ConfigPath
    if (-not $config) { return "" }
    $safeId = (([string](Get-Prop -Object $config -Name 'questionnaireId' -Default 'questionnaire')) -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    $safeVersion = (([string](Get-Prop -Object $config -Name 'questionnaireVersion' -Default '1.0.0')) -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeId)) { $safeId = 'questionnaire' }
    if ([string]::IsNullOrWhiteSpace($safeVersion)) { $safeVersion = '1.0.0' }
    return Join-Path $ProjectPath "Builds\$safeId-$safeVersion.apk"
}

function Invoke-LoggedPowerShell {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$OutputRoot
    )
    $safeName = ($Name -replace '[^A-Za-z0-9_.-]+', '-').Trim('-')
    $logPath = Join-Path $OutputRoot "$safeName.log"
    Push-Location -LiteralPath $WorkingDirectory
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell @Arguments 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    }
    catch {
        $output = $_
        $exitCode = 1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }
    (@($output) | Out-String) | Set-Content -LiteralPath $logPath -Encoding UTF8
    return [ordered]@{
        name = $Name
        exitCode = $exitCode
        status = if ($exitCode -eq 0) { 'pass' } else { 'fail' }
        logPath = $logPath
    }
}

function New-PendingSignoffTemplate {
    param(
        [string]$QuestSerial,
        [string]$QuestionnaireApk,
        [string]$UnityApk,
        [object]$PairAudit
    )

    $catalog = Get-Prop -Object $PairAudit -Name 'catalog'
    return [ordered]@{
        schemaVersion = 'mq.two_apk_live_operator_signoff.v1'
        status = 'pending-operator-signoff'
        completedAt = ''
        operatorName = ''
        questSerial = $(if ([string]::IsNullOrWhiteSpace($QuestSerial)) { '<quest-serial>' } else { $QuestSerial })
        evidence = [ordered]@{
            questionnaireApk = $QuestionnaireApk
            unityApk = $UnityApk
            twoApkPairSummary = '<path-to-two-apk-pair-summary.json>'
            liveQuestSummary = '<path-to-quest-minimal-apk-trigger-protocol-summary.json-or-quest-2d-first-summary.json>'
            exportPullSummary = '<path-to-export-pull-summary-if-separate>'
        }
        observed = [ordered]@{
            installedBothApksOnExplicitSerial = $false
            startedGeneratedQuestionnaireFromMetaHome = $false
            didNotStartUnityFromMetaHome = $false
            block1DisplayedAndSaved = $false
            questionnaireLaunchedUnityImmersiveApk = $false
            unityDisplayedAsImmersiveForegroundApp = $false
            noControllerRequiredLaunchDialog = $false
            noMetaMenuOrAdbForegroundRecoveryAfterStart = $false
            triggerFiredInsideUnityForegroundApp = $false
            questionnaireResumedAfterUnityTrigger = $false
            resumedBlockMatchedQuestionnaireProtocol = $false
            repeatedTriggerDidNotReplayCompletedBlockUnlessConfigured = $false
            exportsOwnedByQuestionnaireApk = $false
            noUnitySideQuestionnaireDecisionObserved = $false
        }
        expected = [ordered]@{
            questionnaireFrontDoor = 'generated 2D questionnaire APK'
            unityRole = 'immersive stimulus APK; passive trigger emitter only'
            questionnaireRole = 'study logic, trigger mapping, block progression, participant state, and exports'
            unityPackage = [string](Get-Prop -Object $catalog -Name 'package' -Default '')
            unityActivity = [string](Get-Prop -Object $catalog -Name 'activity' -Default '')
            unityTriggerCount = [int](Get-Prop -Object $catalog -Name 'triggerCount' -Default 0)
        }
        stopConditions = @(
            'Horizon controller-required launch dialog appears for a generic demo/stimulus APK',
            'Unity is started manually from Meta Home instead of by the generated questionnaire APK',
            'ADB, Meta menu navigation, force-stop, or package killing is used after the participant-facing start',
            'Unity emits questionnaire mode, block id, scoring, export, finish behavior, next package, or next activity decisions',
            'Questionnaire does not resume after the Unity trigger',
            'Unity remains frozen after a questionnaire return'
        )
        notes = ''
    }
}

function Test-SignoffPass {
    param([object]$Signoff)
    if ($null -eq $Signoff) {
        return [ordered]@{ pass = $false; missing = @('operator-signoff-json') }
    }
    $observed = Get-Prop -Object $Signoff -Name 'observed'
    $required = @(
        'installedBothApksOnExplicitSerial',
        'startedGeneratedQuestionnaireFromMetaHome',
        'didNotStartUnityFromMetaHome',
        'block1DisplayedAndSaved',
        'questionnaireLaunchedUnityImmersiveApk',
        'unityDisplayedAsImmersiveForegroundApp',
        'noControllerRequiredLaunchDialog',
        'noMetaMenuOrAdbForegroundRecoveryAfterStart',
        'triggerFiredInsideUnityForegroundApp',
        'questionnaireResumedAfterUnityTrigger',
        'resumedBlockMatchedQuestionnaireProtocol',
        'exportsOwnedByQuestionnaireApk',
        'noUnitySideQuestionnaireDecisionObserved'
    )
    $missing = @($required | Where-Object { -not [bool](Get-Prop -Object $observed -Name $_ -Default $false) })
    $status = [string](Get-Prop -Object $Signoff -Name 'status' -Default '')
    if ($status -notin @('pass', 'passed', 'complete')) {
        $missing += 'status=pass'
    }
    return [ordered]@{
        pass = ($missing.Count -eq 0)
        missing = $missing
    }
}

$projectFull = Get-SafeFullPath $ProjectPath
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $projectFull
}
$repoRootFull = Get-SafeFullPath $RepoRoot
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = 'two-apk-live-validation-packet-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectFull "artifacts\two-apk-live-validation-packet\$RunId"
}
$outputFull = Get-SafeFullPath $OutputRoot
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null

if ([string]::IsNullOrWhiteSpace($QuestionnaireConfig)) {
    $QuestionnaireConfig = Join-Path $projectFull 'QuestionnaireConfigs\examples\quest-questionnaire-three-circle-protocol-demo.config.json'
}
if ([string]::IsNullOrWhiteSpace($UnityProjectPath)) {
    $UnityProjectPath = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo'
}
if ([string]::IsNullOrWhiteSpace($UnityApk)) {
    $UnityApk = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo\Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk'
}
$QuestionnaireConfig = Get-SafeFullPath $QuestionnaireConfig
$UnityProjectPath = Get-SafeFullPath $UnityProjectPath
$UnityApk = Get-SafeFullPath $UnityApk
if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $QuestionnaireApk = Get-ConfigApkPath -ConfigPath $QuestionnaireConfig -ProjectPath $projectFull
}
$QuestionnaireApk = Get-SafeFullPath $QuestionnaireApk

$steps = New-Object 'System.Collections.Generic.List[object]'
$pairSummaryPath = Join-Path $outputFull 'two-apk-pair-summary.json'
$pairStep = Invoke-LoggedPowerShell -Name 'two-apk-pair-audit' -WorkingDirectory $projectFull -OutputRoot $outputFull -Arguments @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $projectFull 'tools\validate-two-apk-pair.ps1'),
    '-ProjectPath', $projectFull,
    '-QuestionnaireConfig', $QuestionnaireConfig,
    '-UnityApk', $UnityApk,
    '-OutputPath', $pairSummaryPath
)
$steps.Add($pairStep) | Out-Null
$pairAudit = Read-JsonFile -Path $pairSummaryPath

$dryRunSummaryPath = ''
if (-not $SkipDryRunPreflight) {
    $dryRunOutput = Join-Path $outputFull 'quest-dry-run-preflight'
    $dryRunStep = Invoke-LoggedPowerShell -Name 'quest-minimal-dry-run-preflight' -WorkingDirectory $projectFull -OutputRoot $outputFull -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $projectFull 'tools\quest-minimal-apk-trigger-protocol-validate.ps1'),
        '-ProjectPath', $projectFull,
        '-QuestionnaireConfig', $QuestionnaireConfig,
        '-QuestionnaireApk', $QuestionnaireApk,
        '-UnityProjectPath', $UnityProjectPath,
        '-UnityApk', $UnityApk,
        '-OutputRoot', $dryRunOutput,
        '-SkipQuestionnaireBuild'
    )
    $steps.Add($dryRunStep) | Out-Null
    $dryRunSummaryPath = Join-Path $dryRunOutput 'quest-minimal-apk-trigger-protocol-summary.json'
}

$operatorTemplatePath = Join-Path $outputFull 'operator-signoff-template.json'
$operatorInstructionsPath = Join-Path $outputFull 'operator-runbook.md'
$packetSummaryPath = Join-Path $outputFull 'two-apk-live-validation-packet-summary.json'
$template = New-PendingSignoffTemplate -QuestSerial $QuestSerial -QuestionnaireApk $QuestionnaireApk -UnityApk $UnityApk -PairAudit $pairAudit
$template.evidence.twoApkPairSummary = $pairSummaryPath
if (-not [string]::IsNullOrWhiteSpace($dryRunSummaryPath)) {
    $template.evidence.liveQuestSummary = $dryRunSummaryPath
}
Write-Json -Value $template -Path $operatorTemplatePath -Depth 12

$serial = if ([string]::IsNullOrWhiteSpace($QuestSerial)) { '<quest-serial>' } else { $QuestSerial }
$instructions = @"
# Two-APK Live Validation Packet

This packet is for the minimal product protocol:

1. The participant starts the generated 2D questionnaire APK from Meta Home.
2. The questionnaire APK runs its configured first block and saves state.
3. The questionnaire APK launches the immersive Unity/stimulus APK.
4. Unity emits passive trigger IDs only.
5. The questionnaire APK resumes the mapped block from its own protocol state.
6. All questionnaire exports are owned by the generated questionnaire APK.

## Evidence Already Prepared

- Questionnaire config: `$QuestionnaireConfig`
- Questionnaire APK: `$QuestionnaireApk`
- Unity APK: `$UnityApk`
- Pair audit summary: `$pairSummaryPath`
- Dry-run preflight summary: `$dryRunSummaryPath`

## Live Command Gate

Use an explicit Quest serial:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\quest-minimal-apk-trigger-protocol-validate.ps1 `
  -ProjectPath . `
  -QuestionnaireConfig "$QuestionnaireConfig" `
  -QuestionnaireApk "$QuestionnaireApk" `
  -UnityProjectPath "$UnityProjectPath" `
  -UnityApk "$UnityApk" `
  -RunLive -Serial $serial -SkipQuestionnaireBuild
```

If the operator is validating the participant-facing Meta Home path manually,
install both APKs first, then launch the generated questionnaire APK from Meta
Home. Do not launch Unity from Meta Home. Do not use ADB, force-stop, package
killing, or Meta menu navigation after the participant-facing start to repair
the chain.

## Stop Conditions

- A Horizon controller-required launch dialog appears for the generic Unity
  demo/stimulus APK.
- Unity is started directly instead of by the generated questionnaire APK.
- Unity emits questionnaire mode, block id, scoring, export, finish behavior,
  next package, or next activity decisions.
- The questionnaire does not resume after the Unity trigger.
- Unity remains frozen after a questionnaire return.

## Operator Signoff

Fill `operator-signoff-template.json`, save it as `operator-signoff.json`, and
validate it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\new-two-apk-live-validation-packet.ps1 `
  -OperatorSignoffPath "$outputFull\operator-signoff.json" -RequirePass
```

This packet is not itself a live Quest pass. It prepares the live gate and
records exactly what evidence must be collected.
"@
$instructions | Set-Content -LiteralPath $operatorInstructionsPath -Encoding UTF8

$operatorSignoff = if ([string]::IsNullOrWhiteSpace($OperatorSignoffPath)) { $null } else { Read-JsonFile -Path (Get-SafeFullPath $OperatorSignoffPath) }
$signoffResult = Test-SignoffPass -Signoff $operatorSignoff
$stepArray = @($steps.ToArray())
$failedSteps = @($stepArray | Where-Object { [string]$_.status -ne 'pass' })
$dryRunSummary = if ([string]::IsNullOrWhiteSpace($dryRunSummaryPath)) { $null } else { Read-JsonFile -Path $dryRunSummaryPath }
$status = if ($failedSteps.Count -gt 0) {
    'needs-offline-attention'
} elseif ($operatorSignoff -and [bool]$signoffResult.pass) {
    'operator-signoff-pass'
} else {
    'ready-for-operator'
}

$summary = [ordered]@{
    schemaVersion = 'mq.two_apk_live_validation_packet.v1'
    status = $status
    runId = $RunId
    projectPath = $projectFull
    repoRoot = $repoRootFull
    questSerial = $QuestSerial
    proofBoundary = 'This packet is no-headset preparation unless a filled operator signoff and live Quest summaries are supplied. It does not install, launch, wake, or change the Quest by itself.'
    productContract = [ordered]@{
        participantFrontDoor = 'generated 2D questionnaire APK'
        unityRole = 'immersive stimulus APK that emits passive trigger IDs only'
        questionnaireRole = 'study logic owner: trigger mapping, block progression, repeat rules, state, and exports'
        lslRole = 'optional passive marker adapter into the same questionnaire-owned trigger path'
    }
    inputs = [ordered]@{
        questionnaireConfig = $QuestionnaireConfig
        questionnaireApk = Get-FileEvidence -Path $QuestionnaireApk
        unityProjectPath = $UnityProjectPath
        unityApk = Get-FileEvidence -Path $UnityApk
    }
    evidence = [ordered]@{
        twoApkPairSummary = $pairSummaryPath
        dryRunPreflightSummary = $dryRunSummaryPath
        operatorRunbook = $operatorInstructionsPath
        operatorSignoffTemplate = $operatorTemplatePath
        operatorSignoffPath = $OperatorSignoffPath
    }
    statuses = [ordered]@{
        twoApkPairAudit = if ($pairAudit) { [string](Get-Prop -Object $pairAudit -Name 'status' -Default 'missing') } else { 'missing' }
        dryRunPreflight = if ($SkipDryRunPreflight) { 'skipped' } elseif ($dryRunSummary) { [string](Get-Prop -Object $dryRunSummary -Name 'status' -Default 'missing') } else { 'missing' }
        operatorSignoff = if ($operatorSignoff) { if ([bool]$signoffResult.pass) { 'pass' } else { 'fail' } } else { 'pending' }
    }
    operatorSignoffValidation = $signoffResult
    steps = $stepArray
    remainingLiveGates = @(
        'install generated questionnaire APK and immersive Unity APK on an explicit Quest serial',
        'participant starts the generated questionnaire APK from Meta Home',
        'questionnaire block 1 saves and launches Unity',
        'operator/participant fires a Unity trigger inside the immersive foreground app',
        'questionnaire resumes the mapped return block from its own protocol state',
        'exports are pulled from the generated questionnaire APK directory',
        'operator-signoff.json validates as pass'
    )
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
Write-Json -Value $summary -Path $packetSummaryPath -Depth 20

[pscustomobject]@{
    Status = $summary.status
    Summary = $packetSummaryPath
    OperatorRunbook = $operatorInstructionsPath
    OperatorSignoffTemplate = $operatorTemplatePath
    ProofBoundary = $summary.proofBoundary
}

if ($failedSteps.Count -gt 0) {
    throw "Two-APK live validation packet has failed offline steps. See $packetSummaryPath"
}
if ($RequirePass -and -not [bool]$signoffResult.pass) {
    throw "Two-APK operator signoff is not passing. Missing: $($signoffResult.missing -join ', ')"
}
