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
    [switch]$SkipInstall,
    [switch]$NoAutoReplay,
    [switch]$AutoTraceForValidation,
    [switch]$FastVideoForValidation,
    [int]$ValidationVideoEndAfterSeconds = 3,
    [switch]$AllowActivityMismatch,
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
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk))
    try {
        $entries = @($zip.Entries | Select-Object FullName, Length)
    }
    finally {
        $zip.Dispose()
    }
    $catalogEntries = @($entries | Where-Object { $_.FullName -match 'questionnaire-trigger-catalog\.json$' })
    $debugEntries = @($entries | Where-Object { $_.FullName -match '\.dbg($|\.so$)' })

    return [ordered]@{
        name = $Name
        apk = $Apk
        bytes = (Get-Item -LiteralPath $Apk).Length
        package = $package
        activity = $activity
        label = $label
        badging = $badgingPath
        manifest = $manifestPath
        triggerCatalogEntries = @($catalogEntries | ForEach-Object { $_.FullName })
        debugPayloadCount = @($debugEntries).Count
    }
}

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 10)
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
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

$preflightIssues = New-Object 'System.Collections.Generic.List[string]'
if ($apkInfo.questionnaire.package -ne $questionnairePackage) { $preflightIssues.Add("Questionnaire package mismatch: $($apkInfo.questionnaire.package)") | Out-Null }
if ($apkInfo.questionnaire.activity -ne $questionnaireActivity) { $preflightIssues.Add("Questionnaire activity mismatch: $($apkInfo.questionnaire.activity)") | Out-Null }
if ($apkInfo.temporalTracer.package -ne $temporalTracerPackage) { $preflightIssues.Add("Temporal tracer package mismatch: $($apkInfo.temporalTracer.package)") | Out-Null }
if ($apkInfo.temporalTracer.activity -ne $temporalTracerActivity) { $preflightIssues.Add("Temporal tracer activity mismatch: $($apkInfo.temporalTracer.activity)") | Out-Null }
if ($apkInfo.unity.package -ne $UnityPackage) { $preflightIssues.Add("Unity package mismatch: $($apkInfo.unity.package)") | Out-Null }
if ($apkInfo.unity.activity -ne $UnityActivity) { $preflightIssues.Add("Unity activity mismatch: $($apkInfo.unity.activity), expected $UnityActivity") | Out-Null }
if (@($apkInfo.unity.triggerCatalogEntries).Count -lt 1) { $preflightIssues.Add("Unity APK does not contain a questionnaire trigger catalog.") | Out-Null }
if ($triggerCatalog) {
    if ($triggerCatalog.package -ne $UnityPackage) { $preflightIssues.Add("Trigger catalog package mismatch: $($triggerCatalog.package)") | Out-Null }
    if ($triggerCatalog.activity -ne $UnityActivity) { $preflightIssues.Add("Trigger catalog activity mismatch: $($triggerCatalog.activity)") | Out-Null }
    $triggerIds = @($triggerCatalog.triggers | ForEach-Object { $_.triggerId })
    foreach ($requiredTrigger in @('trigger_1_launch_questionnaire', 'trigger_2_video_complete')) {
        if ($triggerIds -notcontains $requiredTrigger) {
            $preflightIssues.Add("Missing trigger in catalog: $requiredTrigger") | Out-Null
        }
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
        preflight = $preflightSummary
        plannedProductPath = [ordered]@{
            initialLaunch = "adb shell am start -n $UnityPackage/$UnityActivity"
            shellDrivenForegroundSwitchAfterInitialLaunch = $false
            fastVideoForValidation = [bool]$FastVideoForValidation
            autoTraceForValidation = [bool]$AutoTraceForValidation
            noAutoReplay = [bool]$NoAutoReplay
        }
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
            initialUnityLaunchOnly = $true
            shellDrivenForegroundSwitchAfterInitialLaunch = $false
            noAdbForceStopAfterInitialLaunch = $true
            noAdbAmStartAfterInitialLaunch = $true
            autoReplayMarkerUsed = -not [bool]$NoAutoReplay
            autoTraceForValidation = [bool]$AutoTraceForValidation
            fastVideoForValidation = [bool]$FastVideoForValidation
        }
        markerCounts = $markerCounts
        blockedReasons = @($blockedReasons)
        power = [ordered]@{
            headsetAsleep = $headsetAsleep
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
    passCount = $passCount
    warnCount = $warnCount
    blockedCount = $blockedCount
    failCount = $failCount
    waitSeconds = $WaitSeconds
    focusPollMilliseconds = $FocusPollMilliseconds
    preflight = $preflightSummary
    trials = $trialArray
    decisionGate = [ordered]@{
        requiredTrialsForDefaultDirectPendingIntent = 10
        passedRequiredTrials = ($passCount -ge 10 -and $failCount -eq 0 -and $blockedCount -eq 0 -and $warnCount -eq 0)
        defaultDirectPendingIntentApproved = ($passCount -ge 10 -and $failCount -eq 0 -and $blockedCount -eq 0 -and $warnCount -eq 0)
        manualHeadsetPassStillRequired = $true
    }
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
