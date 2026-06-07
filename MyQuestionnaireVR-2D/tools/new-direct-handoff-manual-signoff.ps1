param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$DirectHandoffSummaryPath = "",
    [string]$OperatorSignoffPath = "",
    [string]$QuestSerial = "",
    [switch]$RequirePass
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "direct-handoff-manual-signoff-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

function Read-JsonIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Read-JsonRequired {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Resolve-FullPath {
    param(
        [string]$Path,
        [string]$BasePath = (Get-Location).Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function ConvertTo-LongPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $IsWindows -and [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $fullPath
    }
    if ($fullPath.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
        return $fullPath
    }
    if ($fullPath.StartsWith('\\', [System.StringComparison]::Ordinal)) {
        return '\\?\UNC\' + $fullPath.TrimStart('\')
    }
    return '\\?\' + $fullPath
}

function Write-Utf8TextFile {
    param(
        [string]$Path,
        [string]$Text
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [System.IO.Directory]::CreateDirectory((ConvertTo-LongPath -Path $directory)) | Out-Null
    }
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText((ConvertTo-LongPath -Path $Path), $Text, $encoding)
}

function Write-Utf8JsonFile {
    param(
        [string]$Path,
        [object]$Object,
        [int]$Depth = 100
    )

    Write-Utf8TextFile -Path $Path -Text (($Object | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Get-FirstPropertyValue {
    param(
        [object]$Object,
        [string[]]$Names,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }
    return $Default
}

function Test-Truthy {
    param([object]$Value)

    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($null -eq $Value) {
        return $false
    }
    return ([string]$Value).Trim().ToLowerInvariant() -eq 'true'
}

function ConvertTo-BooleanMap {
    param(
        [object]$Object,
        [array]$RequiredFields
    )

    $result = [ordered]@{}
    foreach ($field in $RequiredFields) {
        $result[$field.name] = Test-Truthy -Value (Get-FirstPropertyValue -Object $Object -Names @($field.name) -Default $false)
    }
    return $result
}

function Resolve-LatestDirectHandoffSummary {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Filter 'quest-direct-handoff-validation-summary.json' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $json = Read-JsonIfExists -Path $_.FullName
                if ($json) {
                    $decisionGate = $json.decisionGate
                    $dryRun = [bool](Get-FirstPropertyValue -Object $decisionGate -Names @('dryRun') -Default $false)
                    $status = [string](Get-FirstPropertyValue -Object $json -Names @('status') -Default '')
                    $passCount = [int](Get-FirstPropertyValue -Object $json -Names @('passCount') -Default 0)
                    $blockedCount = [int](Get-FirstPropertyValue -Object $json -Names @('blockedCount') -Default 0)
                    $failCount = [int](Get-FirstPropertyValue -Object $json -Names @('failCount') -Default 0)
                    $attemptedTrialCount = [int](Get-FirstPropertyValue -Object $json -Names @('attemptedTrialCount') -Default 0)
                    [PSCustomObject]@{
                        path = $_.FullName
                        json = $json
                        lastWriteTime = $_.LastWriteTime
                        dryRun = $dryRun
                        status = $status
                        passCount = $passCount
                        blockedCount = $blockedCount
                        failCount = $failCount
                        attemptedTrialCount = $attemptedTrialCount
                        usableScore = if ((-not $dryRun) -and $status -eq 'pass' -and $passCount -ge 1 -and $blockedCount -eq 0 -and $failCount -eq 0) { 1 } else { 0 }
                    }
                }
            } |
            Where-Object { -not [bool]$_.dryRun } |
            Sort-Object @{ Expression = { $_.usableScore }; Descending = $true },
                        @{ Expression = { $_.passCount }; Descending = $true },
                        @{ Expression = { $_.attemptedTrialCount }; Descending = $true },
                        @{ Expression = { $_.lastWriteTime }; Descending = $true }
    )

    return @($candidates | Select-Object -First 1)
}

function Get-ShellSwitchCount {
    param([object]$Summary)

    $decisionGate = $Summary.decisionGate
    $decisionCount = [int](Get-FirstPropertyValue -Object $decisionGate -Names @('shellDrivenForegroundSwitchAfterInitialLaunchCount') -Default 0)
    $trialCount = 0
    if ($Summary.trials) {
        foreach ($trial in @($Summary.trials)) {
            if ($trial.productPath -and [bool]$trial.productPath.shellDrivenForegroundSwitchAfterInitialLaunch) {
                $trialCount += 1
            }
        }
    }
    return [Math]::Max($decisionCount, $trialCount)
}

$projectFull = Resolve-FullPath -Path $ProjectPath
$directRoot = Join-Path $projectFull 'artifacts\quest-direct-handoff'
$directSummaryPathWasExplicit = -not [string]::IsNullOrWhiteSpace($DirectHandoffSummaryPath)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectFull ("artifacts\direct-handoff-manual-signoff\" + $RunId)
}
$outputFull = Resolve-FullPath -Path $OutputRoot
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null

if (-not [string]::IsNullOrWhiteSpace($DirectHandoffSummaryPath)) {
    $DirectHandoffSummaryPath = Resolve-FullPath -Path $DirectHandoffSummaryPath
    $directSummary = Read-JsonRequired -Path $DirectHandoffSummaryPath
}
else {
    $latestDirect = Resolve-LatestDirectHandoffSummary -Root $directRoot
    if ($latestDirect) {
        $DirectHandoffSummaryPath = $latestDirect.path
        $directSummary = $latestDirect.json
    }
    else {
        $directSummary = $null
    }
}

$requiredObservationFields = @(
    [ordered]@{ name = 'observedNoControllerRequiredLaunchDialog'; label = 'No Horizon controller-required launch dialog blocked the Unity APK; if it appeared, the Unity build was not treated as a valid generic demo/stimulus build.' },
    [ordered]@{ name = 'observedUnityStartGate'; label = 'Unity displayed the Start experiment gate before the first panel launch.' },
    [ordered]@{ name = 'clickedStartExperimentInUnity'; label = 'The operator or participant clicked the Start experiment target inside Unity.' },
    [ordered]@{ name = 'observedQuestionnairePanelFocused'; label = 'The questionnaire 2D panel took focus from Unity.' },
    [ordered]@{ name = 'observedQuestionnaireCompletedAndSaved'; label = 'The questionnaire completed and saved/exported data.' },
    [ordered]@{ name = 'observedReturnToSameUnityAppAfterQuestionnaire'; label = 'Focus returned to the same Unity package/activity after the questionnaire.' },
    [ordered]@{ name = 'observedVideoResumedAfterQuestionnaire'; label = 'Unity video motion resumed after the questionnaire return.' },
    [ordered]@{ name = 'observedTracerPanelFocused'; label = 'The temporal tracer 2D panel took focus from Unity.' },
    [ordered]@{ name = 'observedTracerCompletedAndSaved'; label = 'The temporal tracer completed and saved/exported data.' },
    [ordered]@{ name = 'observedReturnToSameUnityAppAfterTracer'; label = 'Focus returned to the same Unity package/activity after the tracer.' },
    [ordered]@{ name = 'observedFinalUnityCompletion'; label = 'Unity reached the final completion state after the tracer return.' },
    [ordered]@{ name = 'observedNoMetaMenuNavigation'; label = 'No Meta menu navigation was used to move between apps.' },
    [ordered]@{ name = 'observedNoAdbForegroundSwitchAfterInitialLaunch'; label = 'No ADB foreground switch was used after the initial Unity launch.' }
)

$instructionsPath = Join-Path $outputFull 'operator-instructions.txt'
$templatePath = Join-Path $outputFull 'operator-signoff-template.json'
$resolvedDirectText = if ([string]::IsNullOrWhiteSpace($DirectHandoffSummaryPath)) { '<run a real direct handoff trial first>' } else { $DirectHandoffSummaryPath }

$instructions = @"
Direct handoff manual headset signoff
=====================================

This is the physical headset signoff for the Universal Quest Handoff strategy.
It is separate from dry-run preflight and from ADB log/export validation.

Use a real product-path run:

1. Launch the source Unity APK through the normal direct handoff validator or
   the builder's Run direct handoff button with Preflight only cleared.
2. If Horizon shows LaunchCheckControllerRequiredDialogActivity or any
   controller-required launch prompt for a generic demo/stimulus APK, stop the
   run and rebuild Unity with hand and controller support. Do not clear the
   prompt and count the run as valid handoff evidence.
3. Do not use ADB am start, force-stop, package killing, or Meta menu
   navigation after the initial Unity launch.
4. In the headset, confirm the source Unity app shows its Start experiment
   gate before trigger 1, then click that gate.
5. Confirm this sequence in the headset:
   Unity -> questionnaire panel -> same Unity app with video motion resumed ->
   temporal tracer panel -> same Unity app final completion.
6. If Unity video stays frozen after a panel return, mark the signoff false.
   Treat that as a Unity panel-focus/media-resume bug, not as something to fix
   with Meta menu navigation or ADB foreground switching.
7. Fill operator-signoff-template.json, save it as operator-signoff.json, and
   run this script again with -OperatorSignoffPath pointing at that file.

Suggested validation command after filling the signoff:

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-direct-handoff-manual-signoff.ps1 -OperatorSignoffPath .\artifacts\direct-handoff-manual-signoff\<run-id>\operator-signoff.json -RequirePass

Direct handoff summary linked by this template:
$resolvedDirectText
"@
Write-Utf8TextFile -Path $instructionsPath -Text ($instructions + [Environment]::NewLine)

$template = [ordered]@{
    schemaVersion = 'mq.direct_handoff_manual_signoff.operator.v1'
    status = 'pending-operator-signoff'
    operatorName = ''
    signedAtUtc = ''
    questSerial = $QuestSerial
    directHandoffSummaryPath = $resolvedDirectText
    observedNoControllerRequiredLaunchDialog = $false
    observedUnityStartGate = $false
    clickedStartExperimentInUnity = $false
    observedQuestionnairePanelFocused = $false
    observedQuestionnaireCompletedAndSaved = $false
    observedReturnToSameUnityAppAfterQuestionnaire = $false
    observedVideoResumedAfterQuestionnaire = $false
    observedTracerPanelFocused = $false
    observedTracerCompletedAndSaved = $false
    observedReturnToSameUnityAppAfterTracer = $false
    observedFinalUnityCompletion = $false
    observedNoMetaMenuNavigation = $false
    observedNoAdbForegroundSwitchAfterInitialLaunch = $false
    notes = ''
}
Write-Utf8JsonFile -Path $templatePath -Object $template -Depth 8

$operatorSignoff = $null
$operatorSignoffFull = ''
$issues = New-Object System.Collections.Generic.List[string]
$missing = New-Object System.Collections.Generic.List[string]
$observations = [ordered]@{}
$operatorName = ''
$signedAtUtc = ''
$operatorQuestSerial = ''
$operatorStatus = 'not-provided'

if (-not [string]::IsNullOrWhiteSpace($OperatorSignoffPath)) {
    $operatorSignoffFull = Resolve-FullPath -Path $OperatorSignoffPath
    $operatorSignoff = Read-JsonRequired -Path $operatorSignoffFull
    $operatorName = [string](Get-FirstPropertyValue -Object $operatorSignoff -Names @('operatorName', 'operator') -Default '')
    $signedAtUtc = [string](Get-FirstPropertyValue -Object $operatorSignoff -Names @('signedAtUtc') -Default '')
    $operatorQuestSerial = [string](Get-FirstPropertyValue -Object $operatorSignoff -Names @('questSerial') -Default '')
    $operatorStatus = [string](Get-FirstPropertyValue -Object $operatorSignoff -Names @('status') -Default '')

    $signoffSummaryPath = [string](Get-FirstPropertyValue -Object $operatorSignoff -Names @('directHandoffSummaryPath') -Default '')
    if (-not [string]::IsNullOrWhiteSpace($signoffSummaryPath) -and -not $signoffSummaryPath.StartsWith('<')) {
        $signoffSummaryPath = Resolve-FullPath -Path $signoffSummaryPath -BasePath (Split-Path -Parent $operatorSignoffFull)
        if ($directSummaryPathWasExplicit -and $signoffSummaryPath -ne $DirectHandoffSummaryPath) {
            $issues.Add('operator-signoff-direct-summary-mismatch') | Out-Null
        }
        $DirectHandoffSummaryPath = $signoffSummaryPath
        $directSummary = Read-JsonRequired -Path $DirectHandoffSummaryPath
    }

    if ([string]::IsNullOrWhiteSpace($operatorName)) {
        $missing.Add('operatorName') | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($signedAtUtc)) {
        $missing.Add('signedAtUtc') | Out-Null
    }
    else {
        try {
            [DateTimeOffset]::Parse($signedAtUtc) | Out-Null
        }
        catch {
            $issues.Add('signedAtUtc-not-parseable') | Out-Null
        }
    }

    $observations = ConvertTo-BooleanMap -Object $operatorSignoff -RequiredFields $requiredObservationFields
    foreach ($field in $requiredObservationFields) {
        if (-not [bool]$observations[$field.name]) {
            $missing.Add($field.name) | Out-Null
        }
    }
}
else {
    foreach ($field in $requiredObservationFields) {
        $observations[$field.name] = $false
    }
    $missing.Add('operator-signoff-json') | Out-Null
}

if ($null -eq $directSummary) {
    $missing.Add('real-direct-handoff-summary') | Out-Null
}

$directChecks = [ordered]@{
    directHandoffSummaryPath = $DirectHandoffSummaryPath
    exists = -not [string]::IsNullOrWhiteSpace($DirectHandoffSummaryPath) -and (Test-Path -LiteralPath $DirectHandoffSummaryPath)
    status = ''
    dryRun = $null
    passCount = 0
    attemptedTrialCount = 0
    blockedCount = 0
    failCount = 0
    shellDrivenForegroundSwitchAfterInitialLaunchCount = 0
    serial = ''
    passesProductPathEvidence = $false
}

if ($directSummary) {
    $decisionGate = $directSummary.decisionGate
    $directChecks.status = [string](Get-FirstPropertyValue -Object $directSummary -Names @('status') -Default '')
    $directChecks.dryRun = [bool](Get-FirstPropertyValue -Object $decisionGate -Names @('dryRun') -Default $false)
    $directChecks.passCount = [int](Get-FirstPropertyValue -Object $directSummary -Names @('passCount') -Default 0)
    $directChecks.attemptedTrialCount = [int](Get-FirstPropertyValue -Object $directSummary -Names @('attemptedTrialCount') -Default 0)
    $directChecks.blockedCount = [int](Get-FirstPropertyValue -Object $directSummary -Names @('blockedCount') -Default 0)
    $directChecks.failCount = [int](Get-FirstPropertyValue -Object $directSummary -Names @('failCount') -Default 0)
    $directChecks.shellDrivenForegroundSwitchAfterInitialLaunchCount = Get-ShellSwitchCount -Summary $directSummary
    $directChecks.serial = [string](Get-FirstPropertyValue -Object $directSummary -Names @('serial') -Default '')
    $directChecks.passesProductPathEvidence =
        [string]$directChecks.status -eq 'pass' -and
        -not [bool]$directChecks.dryRun -and
        [int]$directChecks.passCount -ge 1 -and
        [int]$directChecks.blockedCount -eq 0 -and
        [int]$directChecks.failCount -eq 0 -and
        [int]$directChecks.shellDrivenForegroundSwitchAfterInitialLaunchCount -eq 0

    if ([bool]$directChecks.dryRun) {
        $issues.Add('direct-handoff-summary-is-dry-run') | Out-Null
    }
    if ([string]$directChecks.status -ne 'pass') {
        $issues.Add('direct-handoff-summary-not-pass') | Out-Null
    }
    if ([int]$directChecks.passCount -lt 1) {
        $missing.Add('one-real-direct-handoff-pass') | Out-Null
    }
    if ([int]$directChecks.blockedCount -gt 0) {
        $issues.Add('direct-handoff-summary-has-blocked-trials') | Out-Null
    }
    if ([int]$directChecks.failCount -gt 0) {
        $issues.Add('direct-handoff-summary-has-failed-trials') | Out-Null
    }
    if ([int]$directChecks.shellDrivenForegroundSwitchAfterInitialLaunchCount -gt 0) {
        $issues.Add('shell-foreground-switch-after-initial-launch') | Out-Null
    }
}

if (-not [string]::IsNullOrWhiteSpace($QuestSerial) -and -not [string]::IsNullOrWhiteSpace($directChecks.serial) -and $QuestSerial -ne $directChecks.serial) {
    $issues.Add('requested-quest-serial-does-not-match-direct-summary') | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($operatorQuestSerial) -and -not [string]::IsNullOrWhiteSpace($directChecks.serial) -and $operatorQuestSerial -ne $directChecks.serial) {
    $issues.Add('operator-quest-serial-does-not-match-direct-summary') | Out-Null
}

$status = if ($operatorSignoff -eq $null) {
    'pending-operator-signoff'
}
elseif ($missing.Count -eq 0 -and $issues.Count -eq 0 -and [bool]$directChecks.passesProductPathEvidence) {
    'pass'
}
else {
    'fail'
}

$summary = [ordered]@{
    schemaVersion = 'mq.direct_handoff_manual_signoff.v1'
    status = $status
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    projectPath = $projectFull
    outputRoot = $outputFull
    evidence = [ordered]@{
        instructionsPath = $instructionsPath
        operatorSignoffTemplatePath = $templatePath
        operatorSignoffPath = $operatorSignoffFull
        directHandoffSummaryPath = $DirectHandoffSummaryPath
    }
    operator = [ordered]@{
        operatorName = $operatorName
        signedAtUtc = $signedAtUtc
        questSerial = $operatorQuestSerial
        signoffStatus = $operatorStatus
    }
    directHandoff = $directChecks
    observations = $observations
    requiredObservationLabels = $requiredObservationFields
    missing = @($missing | Select-Object -Unique)
    issues = @($issues | Select-Object -Unique)
}

$summaryPath = Join-Path $outputFull 'direct-handoff-manual-signoff-summary.json'
Write-Utf8JsonFile -Path $summaryPath -Object $summary -Depth 100

Write-Host "Direct handoff manual signoff status: $status"
Write-Host "Summary: $summaryPath"
Write-Host "Instructions: $instructionsPath"
Write-Host "Operator signoff template: $templatePath"

if ($RequirePass -and $status -ne 'pass') {
    throw "Direct handoff manual signoff did not pass: $status. See $summaryPath"
}
