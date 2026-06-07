param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$Aapt = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$RepoRoot = "",
    [string]$OutputRoot = "",
    [string]$QuestionnaireApk = "",
    [string]$TemporalTracerApk = "",
    [string]$UnityApk = "",
    [string]$UnityPackage = "org.questionnairebuilder.stimulusdemo",
    [string]$UnityActivity = "org.questionnairebuilder.stimulusdemo.StimulusUnityPlayerGameActivity",
    [string]$TriggerCatalogPath = "",
    [int]$TrialCount = 1,
    [int]$WaitSeconds = 0,
    [int]$FocusPollMilliseconds = 750,
    [int]$WaitForReadySeconds = 0,
    [int]$ReadinessPollSeconds = 2,
    [switch]$SkipInstall,
    [switch]$NoAutoReplay,
    [switch]$AutoTraceForValidation,
    [switch]$FastVideoForValidation,
    [int]$ValidationVideoEndAfterSeconds = 3,
    [switch]$AllowActivityMismatch,
    [switch]$AllowLaunchWhenNotReady,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.viscereality.questionnaires2d"
$questionnaireActivity = "org.viscereality.questionnaires2d.MainActivity"
$temporalTracerPackage = "org.viscereality.temporaltracer2d"
$temporalTracerActivity = "org.viscereality.temporaltracer2d.MainActivity"
$questionnaireFiles = "/sdcard/Android/data/$questionnairePackage/files"
$questionnaireExports = "$questionnaireFiles/QuestionnaireExports"
$temporalTracerFiles = "/sdcard/Android/data/$temporalTracerPackage/files"
$temporalTracerExports = "$temporalTracerFiles/TemporalTraceExports"

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $OutputRoot = Join-Path $ProjectPath "artifacts\quest-direct-handoff\$stamp"
}
if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $generated = Join-Path $ProjectPath 'Builds\viscereality-maia2-1.0.0.apk'
    $fallback = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
    $QuestionnaireApk = if (Test-Path -LiteralPath $generated) { $generated } else { $fallback }
}
if ([string]::IsNullOrWhiteSpace($TemporalTracerApk)) {
    $TemporalTracerApk = Join-Path $RepoRoot 'TemporalExperienceTracerVR-2D\Builds\TemporalExperienceTracerVR-2D.apk'
}
if ([string]::IsNullOrWhiteSpace($UnityApk)) {
    $UnityApk = Join-Path $RepoRoot 'AweGreatDictatorUnity\Builds\QuestionnaireStimulusBuilderDemo.apk'
}
if ([string]::IsNullOrWhiteSpace($TriggerCatalogPath)) {
    $TriggerCatalogPath = Join-Path $RepoRoot 'AweGreatDictatorUnity\Assets\StreamingAssets\mq\questionnaire-trigger-catalog.json'
}
if ($WaitSeconds -le 0) {
    $WaitSeconds = if ($FastVideoForValidation) { 95 } else { 330 }
}

function Resolve-Adb {
    param([string]$RequestedAdb)
    if (-not [string]::IsNullOrWhiteSpace($RequestedAdb)) {
        if (Test-Path -LiteralPath $RequestedAdb) { return $RequestedAdb }
        throw "ADB not found: $RequestedAdb"
    }
    $candidates = @(
        "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe",
        "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "ADB not found. Pass -Adb explicitly."
}

function Resolve-Aapt {
    param([string]$RequestedAapt)
    if (-not [string]::IsNullOrWhiteSpace($RequestedAapt)) {
        if (Test-Path -LiteralPath $RequestedAapt) { return $RequestedAapt }
        throw "aapt not found: $RequestedAapt"
    }
    $root = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\build-tools"
    $aaptExe = Get-ChildItem -LiteralPath $root -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($aaptExe) { return $aaptExe.FullName }
    throw "Could not find aapt.exe under $root. Pass -Aapt explicitly."
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
    if ($OutputPath) {
        $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = (@($output) -join "`n")
    }
}

function Invoke-NativeText {
    param([string]$Exe, [string[]]$Arguments, [string]$OutputPath)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($OutputPath) {
        $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Text = (@($output) -join "`n")
    }
}

function ConvertTo-CatalogDigest {
    param([object]$Catalog, [string]$Entry = "", [string]$ParseStatus = "pass", [string]$ParseError = "")

    $triggers = if ($Catalog -and $Catalog.PSObject.Properties.Name -contains 'triggers') { @($Catalog.triggers) } else { @() }
    $digest = [ordered]@{
        entry = $Entry
        parseStatus = $ParseStatus
        schemaVersion = if ($Catalog) { [string]$Catalog.schemaVersion } else { "" }
        catalogVersion = if ($Catalog) { [string]$Catalog.catalogVersion } else { "" }
        scenarioId = if ($Catalog) { [string]$Catalog.scenarioId } else { "" }
        package = if ($Catalog) { [string]$Catalog.package } else { "" }
        activity = if ($Catalog) { [string]$Catalog.activity } else { "" }
        label = if ($Catalog) { [string]$Catalog.label } else { "" }
        triggerCount = $triggers.Count
        triggers = @($triggers | ForEach-Object {
            [pscustomobject][ordered]@{
                triggerId = [string]$_.triggerId
                label = [string]$_.label
                recommendedMode = [string]$_.recommendedMode
            }
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($ParseError)) {
        $digest.parseError = $ParseError
    }
    return [pscustomobject]$digest
}

function Compare-TriggerCatalogs {
    param([object]$SourceCatalog, [object]$EmbeddedCatalog)

    $issues = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $SourceCatalog) {
        $issues.Add('Source trigger catalog is missing.') | Out-Null
        return @($issues)
    }
    if ($null -eq $EmbeddedCatalog) {
        $issues.Add('Embedded Unity APK trigger catalog is missing or could not be parsed.') | Out-Null
        return @($issues)
    }

    foreach ($field in @('schemaVersion', 'catalogVersion', 'scenarioId', 'package', 'activity')) {
        $sourceValue = if ($SourceCatalog.PSObject.Properties.Name -contains $field) { [string]$SourceCatalog.$field } else { "" }
        $embeddedValue = if ($EmbeddedCatalog.PSObject.Properties.Name -contains $field) { [string]$EmbeddedCatalog.$field } else { "" }
        if ($sourceValue -ne $embeddedValue) {
            $issues.Add("Embedded trigger catalog $field mismatch: embedded='$embeddedValue' source='$sourceValue'") | Out-Null
        }
    }

    $sourceTriggers = @($SourceCatalog.triggers)
    $embeddedTriggers = @($EmbeddedCatalog.triggers)
    if ($sourceTriggers.Count -ne $embeddedTriggers.Count) {
        $issues.Add("Embedded trigger catalog trigger count mismatch: embedded=$($embeddedTriggers.Count) source=$($sourceTriggers.Count)") | Out-Null
    }
    foreach ($sourceTrigger in $sourceTriggers) {
        $triggerId = [string]$sourceTrigger.triggerId
        $embeddedTrigger = @($embeddedTriggers | Where-Object { [string]$_.triggerId -eq $triggerId } | Select-Object -First 1)
        if ($embeddedTrigger.Count -lt 1) {
            $issues.Add("Embedded trigger catalog missing trigger: $triggerId") | Out-Null
            continue
        }
        $embeddedTrigger = $embeddedTrigger[0]
        if ([string]$sourceTrigger.recommendedMode -ne [string]$embeddedTrigger.recommendedMode) {
            $issues.Add("Embedded trigger $triggerId recommendedMode mismatch: embedded='$($embeddedTrigger.recommendedMode)' source='$($sourceTrigger.recommendedMode)'") | Out-Null
        }
    }

    return @($issues)
}

function Get-ApkInfo {
    param([string]$Apk, [string]$Name, [string]$OutDir)
    if (-not (Test-Path -LiteralPath $Apk)) {
        throw "Required APK not found: $Apk"
    }
    $badgingPath = Join-Path $OutDir "$Name-aapt-badging.txt"
    $manifestPath = Join-Path $OutDir "$Name-aapt-manifest.txt"
    $badging = Invoke-NativeText -Exe $Aapt -Arguments @('dump', 'badging', $Apk) -OutputPath $badgingPath
    if ($badging.ExitCode -ne 0) {
        throw "aapt dump badging failed for $Apk"
    }
    $manifest = Invoke-NativeText -Exe $Aapt -Arguments @('dump', 'xmltree', $Apk, 'AndroidManifest.xml') -OutputPath $manifestPath
    if ($manifest.ExitCode -ne 0) {
        throw "aapt dump xmltree failed for $Apk"
    }
    $packageLine = ($badging.Text -split "`r?`n" | Where-Object { $_ -like 'package:*' } | Select-Object -First 1)
    $activityLine = ($badging.Text -split "`r?`n" | Where-Object { $_ -like 'launchable-activity:*' } | Select-Object -First 1)
    $labelLine = ($badging.Text -split "`r?`n" | Where-Object { $_ -like 'application-label:*' } | Select-Object -First 1)
    $package = if ($packageLine -match "name='([^']+)'") { $Matches[1] } else { "" }
    $activity = if ($activityLine -match "name='([^']+)'") { $Matches[1] } else { "" }
    $label = if ($labelLine -match "application-label:'([^']*)'") { $Matches[1] } else { "" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $entries = @()
    $catalogEntryNames = @()
    $debugPayloadCount = 0
    $embeddedCatalogs = New-Object 'System.Collections.Generic.List[object]'
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk))
    try {
        $zipEntries = @($zip.Entries)
        $entries = @($zipEntries | Select-Object FullName, Length)
        $catalogEntries = @($zipEntries | Where-Object { $_.FullName -match 'questionnaire-trigger-catalog\.json$' })
        $debugEntries = @($zipEntries | Where-Object { $_.FullName -match '\.dbg($|\.so$)' })
        $catalogEntryNames = @($catalogEntries | ForEach-Object { $_.FullName })
        $debugPayloadCount = @($debugEntries).Count
        foreach ($catalogEntry in $catalogEntries) {
            $stream = $null
            $reader = $null
            try {
                $stream = $catalogEntry.Open()
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
                $catalogText = $reader.ReadToEnd()
                $catalog = $catalogText | ConvertFrom-Json
                $embeddedCatalogs.Add((ConvertTo-CatalogDigest -Catalog $catalog -Entry $catalogEntry.FullName)) | Out-Null
            } catch {
                $embeddedCatalogs.Add((ConvertTo-CatalogDigest -Catalog $null -Entry $catalogEntry.FullName -ParseStatus 'fail' -ParseError $_.Exception.Message)) | Out-Null
            } finally {
                if ($reader) {
                    $reader.Dispose()
                } elseif ($stream) {
                    $stream.Dispose()
                }
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    return [ordered]@{
        name = $Name
        apk = $Apk
        bytes = (Get-Item -LiteralPath $Apk).Length
        package = $package
        activity = $activity
        label = $label
        badging = $badgingPath
        manifest = $manifestPath
        triggerCatalogEntries = $catalogEntryNames
        embeddedTriggerCatalogs = @($embeddedCatalogs.ToArray())
        debugPayloadCount = $debugPayloadCount
    }
}

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 10)
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-DirectHandoffDecisionGate {
    param(
        [bool]$IsDryRun,
        [string]$PreflightStatus,
        [int]$RequestedTrialCount = 0,
        [int]$AttemptedTrialCount = 0,
        [int]$PassCount = 0,
        [int]$WarnCount = 0,
        [int]$BlockedCount = 0,
        [int]$FailCount = 0,
        [object[]]$Trials = @()
    )

    $requiredTrials = 10
    $trialArray = @($Trials)
    $shellSwitchCount = @($trialArray | Where-Object {
        $_.productPath -and [bool]$_.productPath.shellDrivenForegroundSwitchAfterInitialLaunch
    }).Count
    $blockedBeforeProductPathCount = @($trialArray | Where-Object {
        $_.productPath -and [bool]$_.productPath.blockedBeforeProductPath
    }).Count
    $blockedDuringProductPathCount = @($trialArray | Where-Object {
        $_.blockedReasons -and (@($_.blockedReasons) -contains 'headset-asleep-or-display-off-during-product-path')
    }).Count
    $automatedTrialGatePassed = (
        -not $IsDryRun -and
        [string]$PreflightStatus -eq 'pass' -and
        $AttemptedTrialCount -ge $requiredTrials -and
        $PassCount -ge $requiredTrials -and
        $WarnCount -eq 0 -and
        $BlockedCount -eq 0 -and
        $FailCount -eq 0 -and
        $shellSwitchCount -eq 0
    )

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if ($IsDryRun) {
        $reasons.Add('dry-run-preflight-only-no-headset-focus-or-export-proof') | Out-Null
    }
    if ([string]$PreflightStatus -ne 'pass') {
        $reasons.Add("preflight-status-$PreflightStatus") | Out-Null
    }
    if (-not $IsDryRun -and $AttemptedTrialCount -lt $requiredTrials) {
        $reasons.Add("needs-$requiredTrials-real-quest-trials-attempted-$AttemptedTrialCount") | Out-Null
    }
    if (-not $IsDryRun -and $PassCount -lt $requiredTrials) {
        $reasons.Add("needs-$requiredTrials-passing-quest-trials-pass-count-$PassCount") | Out-Null
    }
    if ($WarnCount -gt 0) {
        $reasons.Add("warning-trials-$WarnCount") | Out-Null
    }
    if ($BlockedCount -gt 0) {
        $reasons.Add("blocked-trials-$BlockedCount") | Out-Null
    }
    if ($FailCount -gt 0) {
        $reasons.Add("failed-trials-$FailCount") | Out-Null
    }
    if ($shellSwitchCount -gt 0) {
        $reasons.Add("shell-driven-foreground-switch-after-initial-launch-$shellSwitchCount") | Out-Null
    }
    if ($automatedTrialGatePassed) {
        $reasons.Add('manual-headset-pass-still-required-before-default-approval') | Out-Null
    }

    $candidateAStatus = 'not-approved'
    if ($automatedTrialGatePassed) {
        $candidateAStatus = 'automated-trials-passed-manual-pass-pending'
    } elseif ($IsDryRun) {
        $candidateAStatus = 'dry-run-only'
    } elseif ([string]$PreflightStatus -ne 'pass') {
        $candidateAStatus = 'preflight-failed'
    } elseif ($PassCount -eq 0 -and $FailCount -eq 0 -and ($blockedBeforeProductPathCount -gt 0 -or $blockedDuringProductPathCount -gt 0)) {
        $candidateAStatus = if ($blockedBeforeProductPathCount -gt 0) { 'blocked-before-product-path' } else { 'blocked-during-product-path' }
    } elseif ($PassCount -gt 0 -and $FailCount -eq 0) {
        $candidateAStatus = 'inconclusive-clean-10-required'
    }

    $recommendedStrategy = 'collect-clean-10-real-quest-trials'
    if ($automatedTrialGatePassed) {
        $recommendedStrategy = 'candidate-a-pending-manual-headset-pass'
    } elseif ([string]$PreflightStatus -ne 'pass') {
        $recommendedStrategy = 'fix-preflight-before-strategy-selection'
    } elseif ($IsDryRun) {
        $recommendedStrategy = 'collect-real-quest-product-path-trials'
    } elseif ($blockedBeforeProductPathCount -gt 0 -and $PassCount -eq 0) {
        $recommendedStrategy = 'wait-for-product-path-ready-headset'
    } elseif ($blockedDuringProductPathCount -gt 0 -and $PassCount -eq 0 -and $FailCount -eq 0) {
        $recommendedStrategy = 'keep-headset-awake-for-full-product-path'
    } elseif ($FailCount -gt 0) {
        $recommendedStrategy = 'investigate-candidate-a-and-compare-chainlink-fallback'
    }

    return [ordered]@{
        schemaVersion = 'mq.direct_handoff_strategy_decision.v1'
        candidateA = 'direct-pendingintent'
        candidateB = 'chainlink-trigger-router-fallback'
        candidateC = 'legacy-caller-package-activity-fallback'
        requiredTrialsForDefaultDirectPendingIntent = $requiredTrials
        requestedTrialCount = $RequestedTrialCount
        attemptedTrialCount = $AttemptedTrialCount
        passCount = $PassCount
        warnCount = $WarnCount
        blockedCount = $BlockedCount
        failCount = $FailCount
        dryRun = $IsDryRun
        preflightStatus = $PreflightStatus
        shellDrivenForegroundSwitchAfterInitialLaunchCount = $shellSwitchCount
        blockedBeforeProductPathCount = $blockedBeforeProductPathCount
        blockedDuringProductPathCount = $blockedDuringProductPathCount
        passedRequiredTrials = $automatedTrialGatePassed
        automatedQuestTrialGatePassed = $automatedTrialGatePassed
        manualHeadsetPassRequired = $true
        manualHeadsetPassStatus = 'pending'
        manualHeadsetPassStillRequired = $true
        defaultDirectPendingIntentApproved = $false
        candidateAStatus = $candidateAStatus
        recommendedProductionStrategy = $recommendedStrategy
        chainLinkRole = 'plan-compiler-trigger-mapping-validator-and-fallback-router-unless-candidate-a-fails-on-quest'
        reasons = $reasons.ToArray()
    }
}

function Count-Matches {
    param([string]$Text, [string]$Pattern)
    return @([regex]::Matches($Text, $Pattern)).Count
}

function Get-FocusPackage {
    param([string]$Text)
    $focusText = (Get-FocusLines -Text $Text) -join "`n"
    foreach ($package in @($UnityPackage, $questionnairePackage, $temporalTracerPackage, 'com.oculus.vrshell', 'com.oculus.shellenv')) {
        if ($focusText -match [regex]::Escape($package)) {
            return $package
        }
    }
    return ""
}

function Get-FocusLines {
    param([string]$Text)
    return @($Text -split "`r?`n" | Where-Object {
        $_ -match 'mCurrentFocus|mFocusedApp|mFocusedWindow|mResumedActivity|topResumedActivity|ResumedActivity'
    })
}

function New-EmptyMarkerCounts {
    return [ordered]@{
        fatalLogs = 0
        controllerRequiredDialogs = 0
        unityValidationAutoTrace = 0
        unityValidationFastVideo = 0
        unityVideoPause = 0
        unityVideoPrepare = 0
        unityVideoPlay = 0
        unityVideoResume = 0
        unityVideoLoopPoint = 0
        unityComplete = 0
        questionnaireReplayStart = 0
        questionnaireExportComplete = 0
        questionnairePendingIntentReturn = 0
        temporalTracerRunStart = 0
        temporalTracerExportComplete = 0
        temporalTracerPendingIntentReturn = 0
    }
}

function Get-QuestReadinessBlockedReasons {
    param([object]$Readiness)
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if (-not $Readiness.ready) {
        $reasons.Add('headset-not-ready-before-product-path') | Out-Null
    }
    if ($Readiness.powerExitCode -ne 0 -or $Readiness.windowExitCode -ne 0) {
        $reasons.Add('adb-readiness-probe-failed') | Out-Null
    }
    if ($Readiness.headsetAsleep -or $Readiness.displayOff) {
        $reasons.Add('headset-asleep-or-display-off-before-product-path') | Out-Null
    }
    if ($Readiness.launchCheckDialogFocused) {
        $reasons.Add('horizon-launch-check-dialog-focused-before-product-path') | Out-Null
    }
    return @($reasons)
}

function Get-QuestReadiness {
    param([string]$TrialDir, [string]$Prefix)
    $powerPath = Join-Path $TrialDir "$Prefix-power.txt"
    $windowPath = Join-Path $TrialDir "$Prefix-window.txt"
    $power = Invoke-AdbText -Arguments @('shell', 'dumpsys', 'power') -OutputPath $powerPath
    $window = Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath $windowPath
    $powerText = $power.Text
    $windowText = $window.Text
    $wakefulness = if ($powerText -match 'mWakefulness=([^\r\n]+)') { $Matches[1].Trim() } else { "" }
    $interactive = if ($powerText -match 'mInteractive=([^\r\n]+)') { $Matches[1].Trim() } else { "" }
    $displayState = if ($powerText -match 'Display Power: state=([^\r\n]+)') { $Matches[1].Trim() } else { "" }
    $focusLines = Get-FocusLines -Text $windowText
    $focusText = $focusLines -join "`n"
    $windowSleeping = $windowText -match 'isSleeping=true'
    $displayOff = $displayState -match '^OFF\b' -or $interactive -eq 'false'
    $headsetAsleep = $wakefulness -match 'Asleep|Dozing|Dreaming' -or $windowSleeping
    $launchCheckDialogFocused = $focusText -match 'LaunchCheckControllerRequiredDialogActivity' -or $windowText -match 'LaunchCheckControllerRequiredDialogActivity'
    $ready = $power.ExitCode -eq 0 -and
        $window.ExitCode -eq 0 -and
        -not $headsetAsleep -and
        -not $displayOff -and
        -not $launchCheckDialogFocused

    return [ordered]@{
        ready = $ready
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        powerExitCode = $power.ExitCode
        windowExitCode = $window.ExitCode
        wakefulness = $wakefulness
        interactive = $interactive
        displayState = $displayState
        headsetAsleep = $headsetAsleep
        displayOff = $displayOff
        windowSleeping = $windowSleeping
        launchCheckDialogFocused = $launchCheckDialogFocused
        focusedPackage = Get-FocusPackage -Text $windowText
        focusLines = $focusLines
        power = $powerPath
        window = $windowPath
    }
}

function Wait-QuestReadiness {
    param([string]$TrialDir)
    $samplesJsonl = Join-Path $TrialDir 'readiness-samples.jsonl'
    "" | Set-Content -LiteralPath $samplesJsonl -Encoding UTF8
    $sampleCount = 0
    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitForReadySeconds))
    $last = $null
    while ($true) {
        $sampleCount++
        $last = Get-QuestReadiness -TrialDir $TrialDir -Prefix ("readiness-{0:0000}" -f $sampleCount)
        ($last | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $samplesJsonl -Encoding UTF8
        if ($last.ready) {
            break
        }
        if ($WaitForReadySeconds -le 0 -or (Get-Date) -ge $deadline) {
            break
        }
        Start-Sleep -Seconds ([Math]::Max(1, $ReadinessPollSeconds))
    }

    return [ordered]@{
        ready = [bool]$last.ready
        sampleCount = $sampleCount
        waitForReadySeconds = $WaitForReadySeconds
        pollSeconds = [Math]::Max(1, $ReadinessPollSeconds)
        samplesJsonl = $samplesJsonl
        last = $last
    }
}

function Pull-DeviceTree {
    param(
        [string]$DevicePath,
        [string]$Destination,
        [string]$Label,
        [string]$TrialDir
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $listResult = Invoke-AdbText -Arguments @('shell', 'find', $DevicePath, '-type', 'f') -OutputPath (Join-Path $TrialDir "$Label-file-list.txt")
    $files = @()
    if ($listResult.ExitCode -eq 0) {
        foreach ($raw in @($listResult.Text -split "`r?`n")) {
            $deviceFile = $raw.Trim()
            if ([string]::IsNullOrWhiteSpace($deviceFile) -or -not $deviceFile.StartsWith($DevicePath)) {
                continue
            }
            $relative = $deviceFile.Substring($DevicePath.Length).TrimStart('/', '\')
            if ([string]::IsNullOrWhiteSpace($relative)) {
                continue
            }
            $localPath = Join-Path $Destination ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $localPath) | Out-Null
            $pullResult = Invoke-AdbText -Arguments @('pull', $deviceFile, $localPath) -OutputPath (Join-Path $TrialDir ("$Label-pull-" + ($files.Count + 1) + ".txt"))
            $files += [ordered]@{
                device = $deviceFile
                local = $localPath
                pullExitCode = $pullResult.ExitCode
                bytes = if (Test-Path -LiteralPath $localPath) { (Get-Item -LiteralPath $localPath).Length } else { 0 }
            }
        }
    }
    return [ordered]@{
        label = $Label
        devicePath = $DevicePath
        destination = $Destination
        findExitCode = $listResult.ExitCode
        fileCount = @($files).Count
        files = $files
    }
}

function New-ReplayMarker {
    param([string]$Path, [string]$ParticipantName)
    [ordered]@{
        ParticipantName = $ParticipantName
        ExpectedAge = 33
        GenderFocusId = 'gender.0'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$Adb = Resolve-Adb $Adb
$Aapt = Resolve-Aapt $Aapt

if ([string]::IsNullOrWhiteSpace($Serial) -and -not $DryRun) {
    $devicesOutput = & $Adb devices -l
    $devices = @($devicesOutput | Select-String -Pattern '\sdevice\s')
    if ($devices.Count -eq 1) {
        $Serial = ($devices[0].ToString() -split '\s+')[0]
    }
}
if ([string]::IsNullOrWhiteSpace($Serial) -and -not $DryRun) {
    throw "No unique Quest serial detected. Pass -Serial explicitly."
}

$preflightDir = Join-Path $OutputRoot 'preflight'
New-Item -ItemType Directory -Force -Path $preflightDir | Out-Null
$apkInfo = [ordered]@{
    questionnaire = Get-ApkInfo -Apk $QuestionnaireApk -Name 'questionnaire' -OutDir $preflightDir
    temporalTracer = Get-ApkInfo -Apk $TemporalTracerApk -Name 'temporal-tracer' -OutDir $preflightDir
    unity = Get-ApkInfo -Apk $UnityApk -Name 'unity-demo' -OutDir $preflightDir
}

$triggerCatalog = $null
if (Test-Path -LiteralPath $TriggerCatalogPath) {
    $triggerCatalog = Get-Content -LiteralPath $TriggerCatalogPath -Raw | ConvertFrom-Json
}
$triggerCatalogDigest = if ($triggerCatalog) { ConvertTo-CatalogDigest -Catalog $triggerCatalog -Entry $TriggerCatalogPath } else { $null }
$unityEmbeddedCatalogs = @($apkInfo.unity.embeddedTriggerCatalogs)
$parsedUnityEmbeddedCatalogs = @($unityEmbeddedCatalogs | Where-Object { [string]$_.parseStatus -eq 'pass' })
$primaryUnityEmbeddedCatalog = if ($parsedUnityEmbeddedCatalogs.Count -gt 0) { $parsedUnityEmbeddedCatalogs[0] } else { $null }

$preflightIssues = New-Object 'System.Collections.Generic.List[string]'
if ($apkInfo.questionnaire.package -ne $questionnairePackage) { $preflightIssues.Add("Questionnaire package mismatch: $($apkInfo.questionnaire.package)") | Out-Null }
if ($apkInfo.questionnaire.activity -ne $questionnaireActivity) { $preflightIssues.Add("Questionnaire activity mismatch: $($apkInfo.questionnaire.activity)") | Out-Null }
if ($apkInfo.temporalTracer.package -ne $temporalTracerPackage) { $preflightIssues.Add("Temporal tracer package mismatch: $($apkInfo.temporalTracer.package)") | Out-Null }
if ($apkInfo.temporalTracer.activity -ne $temporalTracerActivity) { $preflightIssues.Add("Temporal tracer activity mismatch: $($apkInfo.temporalTracer.activity)") | Out-Null }
if ($apkInfo.unity.package -ne $UnityPackage) { $preflightIssues.Add("Unity package mismatch: $($apkInfo.unity.package)") | Out-Null }
if ($apkInfo.unity.activity -ne $UnityActivity) { $preflightIssues.Add("Unity activity mismatch: $($apkInfo.unity.activity), expected $UnityActivity") | Out-Null }
if (@($apkInfo.unity.triggerCatalogEntries).Count -lt 1) { $preflightIssues.Add("Unity APK does not contain a questionnaire trigger catalog.") | Out-Null }
if ($unityEmbeddedCatalogs.Count -gt 1) { $preflightIssues.Add("Unity APK contains multiple questionnaire trigger catalogs; expected exactly one discoverable manifest.") | Out-Null }
foreach ($embeddedCatalog in $unityEmbeddedCatalogs) {
    if ([string]$embeddedCatalog.parseStatus -ne 'pass') {
        $preflightIssues.Add("Unity APK trigger catalog could not be parsed: $($embeddedCatalog.entry)") | Out-Null
    }
}
if ($triggerCatalog) {
    if ($triggerCatalog.package -ne $UnityPackage) { $preflightIssues.Add("Trigger catalog package mismatch: $($triggerCatalog.package)") | Out-Null }
    if ($triggerCatalog.activity -ne $UnityActivity) { $preflightIssues.Add("Trigger catalog activity mismatch: $($triggerCatalog.activity)") | Out-Null }
    $triggerIds = @($triggerCatalog.triggers | ForEach-Object { $_.triggerId })
    foreach ($requiredTrigger in @('trigger_1_launch_questionnaire', 'trigger_2_video_complete')) {
        if ($triggerIds -notcontains $requiredTrigger) {
            $preflightIssues.Add("Missing trigger in catalog: $requiredTrigger") | Out-Null
        }
    }
    foreach ($catalogIssue in (Compare-TriggerCatalogs -SourceCatalog $triggerCatalogDigest -EmbeddedCatalog $primaryUnityEmbeddedCatalog)) {
        $preflightIssues.Add($catalogIssue) | Out-Null
    }
} else {
    $preflightIssues.Add("Trigger catalog source file not found: $TriggerCatalogPath") | Out-Null
}

$preflightStatus = if ($preflightIssues.Count -eq 0 -or $AllowActivityMismatch) { 'pass' } else { 'fail' }
$preflightSummary = [ordered]@{
    status = $preflightStatus
    issues = @($preflightIssues)
    apkInfo = $apkInfo
    triggerCatalogPath = $TriggerCatalogPath
    triggerCatalog = $triggerCatalog
    triggerCatalogDigest = $triggerCatalogDigest
    unityEmbeddedTriggerCatalog = $primaryUnityEmbeddedCatalog
    allowActivityMismatch = [bool]$AllowActivityMismatch
}
Write-Json -Value $preflightSummary -Path (Join-Path $preflightDir 'preflight-summary.json') -Depth 12

if ($preflightStatus -eq 'fail') {
    $summary = [ordered]@{
        schemaVersion = 'mq.quest_direct_handoff_validation.v1'
        status = 'fail'
        reason = 'preflight-failed'
        outputRoot = $OutputRoot
        preflight = $preflightSummary
        decisionGate = (New-DirectHandoffDecisionGate `
            -IsDryRun ([bool]$DryRun) `
            -PreflightStatus $preflightStatus `
            -RequestedTrialCount $TrialCount)
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-Json -Value $summary -Path (Join-Path $OutputRoot 'quest-direct-handoff-validation-summary.json') -Depth 12
    throw "Direct handoff preflight failed. See $OutputRoot"
}

if ($DryRun) {
    $summary = [ordered]@{
        schemaVersion = 'mq.quest_direct_handoff_validation.v1'
        status = 'pass'
        dryRun = $true
        outputRoot = $OutputRoot
        trialCount = $TrialCount
        attemptedTrialCount = 0
        passCount = 0
        warnCount = 0
        blockedCount = 0
        failCount = 0
        preflight = $preflightSummary
        plannedProductPath = [ordered]@{
            initialLaunch = "adb shell am start -n $UnityPackage/$UnityActivity"
            shellDrivenForegroundSwitchAfterInitialLaunch = $false
            fastVideoForValidation = [bool]$FastVideoForValidation
            autoTraceForValidation = [bool]$AutoTraceForValidation
            noAutoReplay = [bool]$NoAutoReplay
            waitForReadySeconds = $WaitForReadySeconds
            readinessPollSeconds = [Math]::Max(1, $ReadinessPollSeconds)
            allowLaunchWhenNotReady = [bool]$AllowLaunchWhenNotReady
        }
        decisionGate = (New-DirectHandoffDecisionGate `
            -IsDryRun $true `
            -PreflightStatus $preflightStatus `
            -RequestedTrialCount $TrialCount)
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-Json -Value $summary -Path (Join-Path $OutputRoot 'quest-direct-handoff-validation-summary.json') -Depth 12
    [pscustomobject]@{ Status = 'pass'; DryRun = $true; Summary = (Join-Path $OutputRoot 'quest-direct-handoff-validation-summary.json') }
    return
}

Invoke-AdbText -Arguments @('devices', '-l') -OutputPath (Join-Path $OutputRoot 'adb-devices.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.product.model') -OutputPath (Join-Path $OutputRoot 'device-model.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.build.version.release') -OutputPath (Join-Path $OutputRoot 'android-version.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'wm', 'size') -OutputPath (Join-Path $OutputRoot 'wm-size.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'wm', 'density') -OutputPath (Join-Path $OutputRoot 'wm-density.txt') | Out-Null

if (-not $SkipInstall) {
    $installDir = Join-Path $OutputRoot 'install'
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    $installQuestionnaire = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $installDir 'install-questionnaire.txt')
    $installTracer = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $TemporalTracerApk) -OutputPath (Join-Path $installDir 'install-temporal-tracer.txt')
    $installUnity = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $UnityApk) -OutputPath (Join-Path $installDir 'install-unity-demo.txt')
    if ($installQuestionnaire.ExitCode -ne 0 -or $installTracer.ExitCode -ne 0 -or $installUnity.ExitCode -ne 0) {
        throw "APK install failed. See $installDir"
    }
}

$trialSummaries = New-Object 'System.Collections.Generic.List[object]'
for ($trial = 1; $trial -le $TrialCount; $trial++) {
    $trialId = "trial-{0:00}" -f $trial
    $trialDir = Join-Path $OutputRoot $trialId
    New-Item -ItemType Directory -Force -Path $trialDir | Out-Null
    $participantName = "QuestHandoffP{0:00}" -f $trial
    $readiness = Wait-QuestReadiness -TrialDir $trialDir
    $readinessBlockedReasons = Get-QuestReadinessBlockedReasons -Readiness $readiness.last
    if (-not $readiness.ready -and -not $AllowLaunchWhenNotReady) {
        $trialSummary = [ordered]@{
            trial = $trial
            status = 'blocked'
            trialDir = $trialDir
            participantName = $participantName
            launchExitCode = $null
            productPath = [ordered]@{
                blockedBeforeProductPath = $true
                initialUnityLaunchAttempted = $false
                initialUnityLaunchOnly = $false
                shellDrivenForegroundSwitchAfterInitialLaunch = $false
                noAdbForceStopAfterInitialLaunch = $true
                noAdbAmStartAfterInitialLaunch = $true
                autoReplayMarkerUsed = $false
                autoTraceForValidation = [bool]$AutoTraceForValidation
                fastVideoForValidation = [bool]$FastVideoForValidation
            }
            readiness = $readiness
            markerCounts = (New-EmptyMarkerCounts)
            blockedReasons = @($readinessBlockedReasons)
            power = [ordered]@{
                headsetAsleep = [bool]$readiness.last.headsetAsleep
                before = $readiness.last.power
                final = $readiness.last.power
                beforeWakefulness = $readiness.last.wakefulness
                finalWakefulness = $readiness.last.wakefulness
            }
            focus = [ordered]@{
                observedPackages = @()
                focusSequenceOk = $false
                finalUnityFocused = $false
                sampleCount = 0
                focusSamplesJsonl = $null
            }
            exports = [ordered]@{
                questionnaire = [ordered]@{
                    jsonCount = 0
                    csvCount = 0
                    pull = $null
                }
                temporalTracer = [ordered]@{
                    jsonCount = 0
                    csvCount = 0
                    svgCount = 0
                    pull = $null
                }
            }
            evidence = [ordered]@{
                readinessSamples = $readiness.samplesJsonl
                preProductPathPower = $readiness.last.power
                preProductPathWindow = $readiness.last.window
            }
        }
        Write-Json -Value $trialSummary -Path (Join-Path $trialDir 'trial-summary.json') -Depth 16
        $trialSummaries.Add($trialSummary) | Out-Null
        break
    }

    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $trialDir 'setup-force-stop-questionnaire.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $temporalTracerPackage) -OutputPath (Join-Path $trialDir 'setup-force-stop-temporal-tracer.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $UnityPackage) -OutputPath (Join-Path $trialDir 'setup-force-stop-unity.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', "rm -rf '$questionnaireExports' '$temporalTracerExports' && mkdir -p '$questionnaireFiles' '$temporalTracerFiles'") -OutputPath (Join-Path $trialDir 'setup-clear-state.txt') | Out-Null

    if (-not $NoAutoReplay) {
        $marker = Join-Path $trialDir 'command-replay-english.json'
        New-ReplayMarker -Path $marker -ParticipantName $participantName
        Invoke-AdbText -Arguments @('push', $marker, "$questionnaireFiles/command-replay-english.json") -OutputPath (Join-Path $trialDir 'setup-push-command-replay-marker.txt') | Out-Null
    }

    Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $trialDir 'setup-logcat-clear.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $trialDir 'focus-before-launch.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'power') -OutputPath (Join-Path $trialDir 'power-before-launch.txt') | Out-Null

    $launchArgs = @(
        'shell', 'am', 'start',
        '-n', "$UnityPackage/$UnityActivity",
        '--es', 'mq.validationRunId', $trialId
    )
    if ($AutoTraceForValidation) {
        $launchArgs += @('--es', 'mq.validationAutoTrace', 'true')
    }
    if ($FastVideoForValidation) {
        $launchArgs += @('--es', 'mq.validationFastVideo', 'true')
        $launchArgs += @('--es', 'mq.validationVideoEndAfterSeconds', "$ValidationVideoEndAfterSeconds")
    }
    $launch = Invoke-AdbText -Arguments $launchArgs -OutputPath (Join-Path $trialDir 'product-path-initial-launch-unity.txt')

    $focusJsonl = Join-Path $trialDir 'focus-samples.jsonl'
    "" | Set-Content -LiteralPath $focusJsonl -Encoding UTF8
    $focusSamples = New-Object 'System.Collections.Generic.List[object]'
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $sampleIndex = 0
    while ((Get-Date) -lt $deadline) {
        $sampleIndex++
        $focusPath = Join-Path $trialDir ("focus-sample-{0:0000}.txt" -f $sampleIndex)
        $focus = Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath $focusPath
        $focusText = $focus.Text
        $sample = [ordered]@{
            index = $sampleIndex
            timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
            package = Get-FocusPackage -Text $focusText
            lines = Get-FocusLines -Text $focusText
            path = $focusPath
        }
        $focusSamples.Add($sample) | Out-Null
        ($sample | ConvertTo-Json -Compress -Depth 5) | Add-Content -LiteralPath $focusJsonl -Encoding UTF8
        Start-Sleep -Milliseconds ([Math]::Max(250, $FocusPollMilliseconds))
    }

    Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $trialDir 'logcat.txt') | Out-Null
    Invoke-AdbText -Arguments @(
        'logcat', '-d', '-v', 'threadtime',
        'Unity:I',
        'MyQuestionnaire2D:I',
        'TemporalTracer2D:I',
        'TemporalTraceExporter:I',
        'ActivityTaskManager:I',
        'AndroidRuntime:E',
        '*:S'
    ) -OutputPath (Join-Path $trialDir 'logcat-handoff-filtered.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $trialDir 'focus-final.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'power') -OutputPath (Join-Path $trialDir 'power-final.txt') | Out-Null

    $pullRoot = Join-Path $trialDir 'device-files'
    $questionnairePull = Pull-DeviceTree -DevicePath $questionnaireExports -Destination (Join-Path $pullRoot 'questionnaire') -Label 'questionnaire-exports' -TrialDir $trialDir
    $tracerPull = Pull-DeviceTree -DevicePath $temporalTracerExports -Destination (Join-Path $pullRoot 'temporal-tracer') -Label 'temporal-tracer-exports' -TrialDir $trialDir

    $logText = Get-Content -LiteralPath (Join-Path $trialDir 'logcat.txt') -Raw
    $filteredLogText = Get-Content -LiteralPath (Join-Path $trialDir 'logcat-handoff-filtered.txt') -Raw
    $allLogText = $logText + "`n" + $filteredLogText
    $observedPackages = @($focusSamples | ForEach-Object { $_.package } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $focusSequenceOk = $observedPackages -contains $UnityPackage -and $observedPackages -contains $questionnairePackage -and $observedPackages -contains $temporalTracerPackage
    $finalFocus = Get-Content -LiteralPath (Join-Path $trialDir 'focus-final.txt') -Raw
    $finalFocusText = (Get-FocusLines -Text $finalFocus) -join "`n"
    $finalUnityFocused = $finalFocusText -match [regex]::Escape($UnityPackage)
    $powerBefore = Get-Content -LiteralPath (Join-Path $trialDir 'power-before-launch.txt') -Raw
    $powerFinal = Get-Content -LiteralPath (Join-Path $trialDir 'power-final.txt') -Raw
    $headsetAsleep = $powerFinal -match 'mWakefulness=Asleep' -or $finalFocus -match 'isSleeping=true'
    $displayOffFinal = $powerFinal -match 'mInteractive=false|Display Power:\s*state=OFF'

    $markerCounts = [ordered]@{
        fatalLogs = Count-Matches -Text $allLogText -Pattern 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b'
        controllerRequiredDialogs = Count-Matches -Text $allLogText -Pattern 'LaunchCheckControllerRequiredDialogActivity|controller required'
        unityValidationAutoTrace = Count-Matches -Text $allLogText -Pattern 'AWE_DEMO_VALIDATION_AUTO_TRACE'
        unityValidationFastVideo = Count-Matches -Text $allLogText -Pattern 'AWE_DEMO_VALIDATION_FAST_VIDEO'
        unityVideoPause = Count-Matches -Text $allLogText -Pattern 'VIDEO_PAUSE_FOR_PANEL'
        unityVideoPrepare = Count-Matches -Text $allLogText -Pattern 'VIDEO_PREPARE_START'
        unityVideoPlay = Count-Matches -Text $allLogText -Pattern 'VIDEO_PLAY'
        unityVideoResume = Count-Matches -Text $allLogText -Pattern 'VIDEO_RESUME_AFTER_PANEL'
        unityVideoLoopPoint = Count-Matches -Text $allLogText -Pattern 'VIDEO_LOOP_POINT|VIDEO_VALIDATION_LOOPPOINT_FALLBACK'
        unityComplete = Count-Matches -Text $allLogText -Pattern 'AWE_DEMO_COMPLETE'
        questionnaireReplayStart = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_COMMAND_REPLAY_START'
        questionnaireExportComplete = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_EXPORT_COMPLETE'
        questionnairePendingIntentReturn = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_CHAIN_RETURN_PENDING_INTENT'
        temporalTracerRunStart = Count-Matches -Text $allLogText -Pattern 'TEMPORAL_TRACER_RUN_START'
        temporalTracerExportComplete = Count-Matches -Text $allLogText -Pattern 'TEMPORAL_TRACER_EXPORT_COMPLETE'
        temporalTracerPendingIntentReturn = Count-Matches -Text $allLogText -Pattern 'TEMPORAL_TRACER_RETURN_PENDING_INTENT'
    }

    $qJsonCount = @($questionnairePull.files | Where-Object { $_.local -match '\.json$' -and $_.local -notmatch 'in_progress' }).Count
    $qCsvCount = @($questionnairePull.files | Where-Object { $_.local -match '\.csv$' -and $_.local -notmatch 'in_progress' }).Count
    $tJsonCount = @($tracerPull.files | Where-Object { $_.local -match '\.json$' -and $_.local -notmatch 'in_progress' }).Count
    $tCsvCount = @($tracerPull.files | Where-Object { $_.local -match '\.csv$' -and $_.local -notmatch 'in_progress' }).Count
    $tSvgCount = @($tracerPull.files | Where-Object { $_.local -match '\.svg$' }).Count

    $handoffOk =
        $launch.ExitCode -eq 0 -and
        $markerCounts.fatalLogs -eq 0 -and
        $markerCounts.questionnaireReplayStart -ge 1 -and
        $markerCounts.questionnaireExportComplete -ge 1 -and
        $markerCounts.questionnairePendingIntentReturn -ge 1 -and
        $markerCounts.unityVideoPrepare -ge 1 -and
        $markerCounts.unityVideoPlay -ge 1 -and
        $markerCounts.unityVideoLoopPoint -ge 1 -and
        $markerCounts.temporalTracerRunStart -ge 1 -and
        $markerCounts.temporalTracerExportComplete -ge 1 -and
        $markerCounts.temporalTracerPendingIntentReturn -ge 1 -and
        $markerCounts.unityComplete -ge 1 -and
        $qJsonCount -ge 1 -and
        $qCsvCount -ge 1 -and
        $tJsonCount -ge 1 -and
        $tCsvCount -ge 1 -and
        $tSvgCount -ge 1

    $blockedReasons = New-Object 'System.Collections.Generic.List[string]'
    if ($markerCounts.controllerRequiredDialogs -gt 0 -and $markerCounts.questionnaireReplayStart -lt 1) {
        $blockedReasons.Add('horizon-controller-required-launch-check-before-unity') | Out-Null
    }
    if ($headsetAsleep -and $markerCounts.questionnaireReplayStart -lt 1) {
        $blockedReasons.Add('headset-asleep-or-display-off-before-unity') | Out-Null
    }
    $productPathStarted = $markerCounts.questionnaireReplayStart -ge 1 -or
        $markerCounts.unityVideoPrepare -ge 1 -or
        $markerCounts.temporalTracerRunStart -ge 1
    if (($headsetAsleep -or $displayOffFinal) -and $productPathStarted -and -not $handoffOk -and $markerCounts.fatalLogs -eq 0) {
        $blockedReasons.Add('headset-asleep-or-display-off-during-product-path') | Out-Null
    }

    $trialStatus = 'fail'
    if ($blockedReasons.Count -gt 0) {
        $trialStatus = 'blocked'
    } elseif ($handoffOk -and $focusSequenceOk -and $finalUnityFocused) {
        $trialStatus = 'pass'
    } elseif ($handoffOk) {
        $trialStatus = 'warn'
    }

    $trialSummary = [ordered]@{
        trial = $trial
        status = $trialStatus
        trialDir = $trialDir
        participantName = $participantName
        launchExitCode = $launch.ExitCode
        productPath = [ordered]@{
            blockedBeforeProductPath = $false
            initialUnityLaunchAttempted = $true
            initialUnityLaunchOnly = $true
            shellDrivenForegroundSwitchAfterInitialLaunch = $false
            noAdbForceStopAfterInitialLaunch = $true
            noAdbAmStartAfterInitialLaunch = $true
            autoReplayMarkerUsed = -not [bool]$NoAutoReplay
            autoTraceForValidation = [bool]$AutoTraceForValidation
            fastVideoForValidation = [bool]$FastVideoForValidation
        }
        readiness = $readiness
        markerCounts = $markerCounts
        blockedReasons = @($blockedReasons)
        power = [ordered]@{
            headsetAsleep = $headsetAsleep
            displayOff = $displayOffFinal
            before = (Join-Path $trialDir 'power-before-launch.txt')
            final = (Join-Path $trialDir 'power-final.txt')
            beforeWakefulness = if ($powerBefore -match 'mWakefulness=([^\r\n]+)') { $Matches[1].Trim() } else { "" }
            finalWakefulness = if ($powerFinal -match 'mWakefulness=([^\r\n]+)') { $Matches[1].Trim() } else { "" }
        }
        focus = [ordered]@{
            observedPackages = $observedPackages
            focusSequenceOk = $focusSequenceOk
            finalUnityFocused = $finalUnityFocused
            sampleCount = $focusSamples.Count
            focusSamplesJsonl = $focusJsonl
        }
        exports = [ordered]@{
            questionnaire = [ordered]@{
                jsonCount = $qJsonCount
                csvCount = $qCsvCount
                pull = $questionnairePull
            }
            temporalTracer = [ordered]@{
                jsonCount = $tJsonCount
                csvCount = $tCsvCount
                svgCount = $tSvgCount
                pull = $tracerPull
            }
        }
        evidence = [ordered]@{
            logcat = (Join-Path $trialDir 'logcat.txt')
            filteredLogcat = (Join-Path $trialDir 'logcat-handoff-filtered.txt')
            focusFinal = (Join-Path $trialDir 'focus-final.txt')
        }
    }
    Write-Json -Value $trialSummary -Path (Join-Path $trialDir 'trial-summary.json') -Depth 16
    $trialSummaries.Add($trialSummary) | Out-Null
}

$trialArray = @($trialSummaries.ToArray())
$passCount = @($trialArray | Where-Object { $_.status -eq 'pass' }).Count
$warnCount = @($trialArray | Where-Object { $_.status -eq 'warn' }).Count
$blockedCount = @($trialArray | Where-Object { $_.status -eq 'blocked' }).Count
$failCount = @($trialArray | Where-Object { $_.status -eq 'fail' }).Count
$overallStatus = 'fail'
if ($failCount -eq 0 -and $blockedCount -eq 0 -and $warnCount -eq 0 -and $passCount -eq $TrialCount) {
    $overallStatus = 'pass'
} elseif ($passCount -gt 0 -and $failCount -eq 0) {
    $overallStatus = 'warn'
} elseif ($blockedCount -gt 0 -and $passCount -eq 0) {
    $overallStatus = 'blocked'
}

$summary = [ordered]@{
    schemaVersion = 'mq.quest_direct_handoff_validation.v1'
    status = $overallStatus
    serial = $Serial
    outputRoot = $OutputRoot
    trialCount = $TrialCount
    attemptedTrialCount = $trialArray.Count
    passCount = $passCount
    warnCount = $warnCount
    blockedCount = $blockedCount
    failCount = $failCount
    waitSeconds = $WaitSeconds
    focusPollMilliseconds = $FocusPollMilliseconds
    waitForReadySeconds = $WaitForReadySeconds
    readinessPollSeconds = [Math]::Max(1, $ReadinessPollSeconds)
    allowLaunchWhenNotReady = [bool]$AllowLaunchWhenNotReady
    preflight = $preflightSummary
    trials = $trialArray
    decisionGate = (New-DirectHandoffDecisionGate `
        -IsDryRun $false `
        -PreflightStatus $preflightStatus `
        -RequestedTrialCount $TrialCount `
        -AttemptedTrialCount $trialArray.Count `
        -PassCount $passCount `
        -WarnCount $warnCount `
        -BlockedCount $blockedCount `
        -FailCount $failCount `
        -Trials $trialArray)
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$summaryPath = Join-Path $OutputRoot 'quest-direct-handoff-validation-summary.json'
Write-Json -Value $summary -Path $summaryPath -Depth 18

[pscustomobject]@{
    Status = $overallStatus
    Pass = $passCount
    Warn = $warnCount
    Blocked = $blockedCount
    Fail = $failCount
    Summary = $summaryPath
}
