param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$Aapt = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$RepoRoot = "",
    [string]$OutputRoot = "",
    [string]$QuestionnaireApk = "",
    [string]$UnityApk = "",
    [string]$UnityPackage = "org.questquestionnaire.stimulusdemo",
    [string]$UnityActivity = "org.questquestionnaire.stimulusdemo.StimulusUnityPlayerGameActivity",
    [int]$TrialCount = 1,
    [int]$WaitSeconds = 45,
    [int]$FocusPollMilliseconds = 750,
    [int]$WaitForReadySeconds = 0,
    [int]$ReadinessPollSeconds = 2,
    [switch]$SkipInstall,
    [switch]$NoAutoReplay,
    [switch]$WakeBeforeReadiness,
    [switch]$AllowLaunchWhenNotReady,
    [switch]$DryRun,
    [switch]$RequirePass
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$questionnairePackage = "org.questquestionnaire.questionnaires2d"
$questionnaireActivity = "org.questquestionnaire.questionnaires2d.MainActivity"
$questionnaireFiles = "/sdcard/Android/data/$questionnairePackage/files"
$questionnaireExports = "$questionnaireFiles/QuestionnaireExports"

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $OutputRoot = Join-Path $ProjectPath "artifacts\quest-2d-first-launcher\$stamp"
}
if ([string]::IsNullOrWhiteSpace($UnityApk)) {
    $UnityApk = Join-Path $RepoRoot 'QuestionnaireStimulusUnity\Builds\QuestionnaireStimulusBuilderDemo.apk'
}

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 10)
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-Adb {
    param([string]$RequestedAdb)
    if (-not [string]::IsNullOrWhiteSpace($RequestedAdb)) {
        if (Test-Path -LiteralPath $RequestedAdb) { return (Resolve-Path -LiteralPath $RequestedAdb).Path }
        throw "ADB not found: $RequestedAdb"
    }
    foreach ($candidate in @(
        "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe",
        "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "ADB not found. Pass -Adb explicitly."
}

function Resolve-Aapt {
    param([string]$RequestedAapt)
    if (-not [string]::IsNullOrWhiteSpace($RequestedAapt)) {
        if (Test-Path -LiteralPath $RequestedAapt) { return (Resolve-Path -LiteralPath $RequestedAapt).Path }
        throw "aapt not found: $RequestedAapt"
    }
    $root = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\build-tools"
    $aaptExe = Get-ChildItem -LiteralPath $root -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($aaptExe) { return $aaptExe.FullName }
    throw "Could not find aapt.exe under $root. Pass -Aapt explicitly."
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
    return [pscustomobject]@{
        exitCode = $exitCode
        text = (@($output) -join "`n")
    }
}

function Invoke-AdbText {
    param([string[]]$Arguments, [string]$OutputPath)
    return Invoke-NativeText -Exe $script:AdbPath -Arguments (@('-s', $script:Serial) + $Arguments) -OutputPath $OutputPath
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
        bytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash
    }
}

function Read-ZipEntryText {
    param([string]$ZipPath, [string]$Pattern)
    if (-not (Test-Path -LiteralPath $ZipPath)) {
        return $null
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath))
    try {
        $entry = @($zip.Entries | Where-Object { $_.FullName -match $Pattern } | Select-Object -First 1)[0]
        if (-not $entry) { return $null }
        $stream = $entry.Open()
        try {
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                return [ordered]@{
                    entry = $entry.FullName
                    text = $reader.ReadToEnd()
                }
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            if ($stream) { $stream.Dispose() }
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Get-ZipEntryNames {
    param([string]$ZipPath, [string]$Pattern)
    if (-not (Test-Path -LiteralPath $ZipPath)) {
        return @()
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath))
    try {
        return @($zip.Entries | Where-Object { $_.FullName -match $Pattern } | ForEach-Object { $_.FullName })
    }
    finally {
        $zip.Dispose()
    }
}

function Resolve-LatestTwoDFirstQuestionnaireApk {
    $root = Join-Path $ProjectPath 'artifacts\builder-to-quest-workflow'
    if (Test-Path -LiteralPath $root) {
        $summaries = @(
            Get-ChildItem -LiteralPath $root -Recurse -Filter 'builder-to-quest-workflow-summary.json' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending
        )
        foreach ($summaryFile in $summaries) {
            try {
                $summary = Get-Content -LiteralPath $summaryFile.FullName -Encoding UTF8 -Raw | ConvertFrom-Json
                $configPath = [string]$summary.configPath
                if (-not (Test-Path -LiteralPath $configPath)) { continue }
                $config = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw | ConvertFrom-Json
                if ($config.chainDefaults -and [string]$config.chainDefaults.startMode -eq 'questionnaireFirst') {
                    $apkPath = [string]$summary.evidence.questionnaireApk.path
                    if (Test-Path -LiteralPath $apkPath) {
                        return (Resolve-Path -LiteralPath $apkPath).Path
                    }
                }
            }
            catch {
                continue
            }
        }
    }

    foreach ($candidate in @(
        (Join-Path $ProjectPath 'Builds\demo-slider-1.0.0.apk'),
        (Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk')
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return Join-Path $ProjectPath 'Builds\demo-slider-1.0.0.apk'
}

function Get-ApkInfo {
    param([string]$Apk, [string]$Name, [string]$OutDir)

    $evidence = Get-FileEvidence -Path $Apk
    $badgingPath = Join-Path $OutDir "$Name-aapt-badging.txt"
    $manifestPath = Join-Path $OutDir "$Name-aapt-manifest.txt"
    if (-not [bool]$evidence.exists) {
        return [ordered]@{
            name = $Name
            apk = $Apk
            exists = $false
            evidence = $evidence
            package = ""
            activity = ""
            label = ""
            badging = ""
            manifest = ""
            inputModality = [ordered]@{}
            triggerCatalogEntries = @()
        }
    }

    $badging = Invoke-NativeText -Exe $script:AaptPath -Arguments @('dump', 'badging', $Apk) -OutputPath $badgingPath
    $manifest = Invoke-NativeText -Exe $script:AaptPath -Arguments @('dump', 'xmltree', $Apk, 'AndroidManifest.xml') -OutputPath $manifestPath
    $packageLine = ($badging.text -split "`r?`n" | Where-Object { $_ -like 'package:*' } | Select-Object -First 1)
    $activityLine = ($badging.text -split "`r?`n" | Where-Object { $_ -like 'launchable-activity:*' } | Select-Object -First 1)
    $labelLine = ($badging.text -split "`r?`n" | Where-Object { $_ -like 'application-label:*' } | Select-Object -First 1)
    $package = if ($packageLine -match "name='([^']+)'") { $Matches[1] } else { "" }
    $activity = if ($activityLine -match "name='([^']+)'") { $Matches[1] } else { "" }
    $label = if ($labelLine -match "application-label:'([^']*)'") { $Matches[1] } else { "" }
    $manifestText = [string]$manifest.text

    return [ordered]@{
        name = $Name
        apk = $Apk
        exists = $true
        evidence = $evidence
        package = $package
        activity = $activity
        label = $label
        badging = $badgingPath
        manifest = $manifestPath
        badgingExitCode = $badging.exitCode
        manifestExitCode = $manifest.exitCode
        inputModality = [ordered]@{
            handTrackingFeature = ($manifestText -match 'oculus\.software\.handtracking')
            handTrackingRequiredFalse = ($manifestText -match 'oculus\.software\.handtracking[\s\S]{0,600}android:required[^\r\n]*(false|\(type 0x12\)0x0)')
            handTrackingPermission = ($manifestText -match 'com\.oculus\.permission\.HAND_TRACKING|oculus\.permission\.handtracking')
        }
        triggerCatalogEntries = @(Get-ZipEntryNames -ZipPath $Apk -Pattern 'questionnaire-trigger-catalog\.json$')
    }
}

function Get-FocusLines {
    param([string]$Text)
    return @($Text -split "`r?`n" | Where-Object {
        $_ -match 'mCurrentFocus|mFocusedApp|mFocusedWindow|mResumedActivity|topResumedActivity|ResumedActivity'
    })
}

function Get-FocusPackage {
    param([string]$Text)
    $focusText = (Get-FocusLines -Text $Text) -join "`n"
    foreach ($package in @($questionnairePackage, $UnityPackage, 'com.oculus.vrshell', 'com.oculus.shellenv')) {
        if ($focusText -match [regex]::Escape($package)) {
            return $package
        }
    }
    return ""
}

function Count-Matches {
    param([string]$Text, [string]$Pattern)
    return @([regex]::Matches($Text, $Pattern)).Count
}

function New-ReplayMarker {
    param([string]$Path, [string]$ParticipantName)
    [ordered]@{
        ParticipantName = $ParticipantName
        ExpectedAge = 33
        GenderFocusId = 'gender.0'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Pull-DeviceTree {
    param([string]$DevicePath, [string]$Destination, [string]$Label, [string]$TrialDir)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $listResult = Invoke-AdbText -Arguments @('shell', 'find', $DevicePath, '-type', 'f') -OutputPath (Join-Path $TrialDir "$Label-file-list.txt")
    $files = @()
    if ($listResult.exitCode -eq 0) {
        foreach ($raw in @($listResult.text -split "`r?`n")) {
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
                pullExitCode = $pullResult.exitCode
                bytes = if (Test-Path -LiteralPath $localPath) { (Get-Item -LiteralPath $localPath).Length } else { 0 }
            }
        }
    }
    return [ordered]@{
        label = $Label
        devicePath = $DevicePath
        destination = $Destination
        findExitCode = $listResult.exitCode
        fileCount = @($files).Count
        files = $files
    }
}

function Invoke-QuestReadiness {
    param([string]$TrialDir)
    $readinessDir = Join-Path $TrialDir 'readiness'
    $readinessScript = Join-Path $ProjectPath 'tools\quest-adb-readiness.ps1'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $readinessScript,
        '-ExpectedSerial', $script:Serial,
        '-WaitSeconds', "$WaitForReadySeconds",
        '-PollSeconds', "$([Math]::Max(1, $ReadinessPollSeconds))",
        '-OutputRoot', $readinessDir
    )
    if (-not [string]::IsNullOrWhiteSpace($script:AdbPath)) {
        $args += @('-Adb', $script:AdbPath)
    }
    Invoke-NativeText -Exe 'powershell' -Arguments $args -OutputPath (Join-Path $TrialDir 'readiness-stdout.txt') | Out-Null
    $summaryPath = Join-Path $readinessDir 'quest-adb-readiness-summary.json'
    if (Test-Path -LiteralPath $summaryPath) {
        return Get-Content -LiteralPath $summaryPath -Encoding UTF8 -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{
        status = 'fail'
        readiness = 'summary-missing'
        productPathReady = $false
        productPathStatus = 'unknown'
        outputRoot = $readinessDir
    }
}

function New-DecisionGate {
    param(
        [bool]$IsDryRun,
        [string]$PreflightStatus,
        [int]$RequestedTrialCount,
        [int]$AttemptedTrialCount,
        [int]$PassCount,
        [int]$BlockedCount,
        [int]$FailCount
    )
    $passed = (-not $IsDryRun -and [string]$PreflightStatus -eq 'pass' -and $PassCount -ge 1 -and $BlockedCount -eq 0 -and $FailCount -eq 0)
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if ($IsDryRun) { $reasons.Add('dry-run-preflight-only-no-quest-focus-proof') | Out-Null }
    if ([string]$PreflightStatus -ne 'pass') { $reasons.Add("preflight-status-$PreflightStatus") | Out-Null }
    if (-not $IsDryRun -and $AttemptedTrialCount -lt $RequestedTrialCount) { $reasons.Add("requested-trials-not-attempted-$AttemptedTrialCount-of-$RequestedTrialCount") | Out-Null }
    if (-not $IsDryRun -and $PassCount -lt 1) { $reasons.Add('needs-one-2d-first-real-product-path-pass') | Out-Null }
    if ($BlockedCount -gt 0) { $reasons.Add("blocked-trials-$BlockedCount") | Out-Null }
    if ($FailCount -gt 0) { $reasons.Add("failed-trials-$FailCount") | Out-Null }
    if ($passed) { $reasons.Add('manual-headset-observation-still-required-for-final-study-signoff') | Out-Null }

    return [ordered]@{
        schemaVersion = 'mq.quest_2d_first_launcher_decision.v1'
        requiredPhysicalLauncherTrials = 1
        requestedTrialCount = $RequestedTrialCount
        attemptedTrialCount = $AttemptedTrialCount
        passCount = $PassCount
        blockedCount = $BlockedCount
        failCount = $FailCount
        dryRun = $IsDryRun
        preflightStatus = $PreflightStatus
        twoDFirstLauncherGatePassed = $passed
        participantFrontDoor = 'questionnaire-apk'
        expectedChain = 'questionnaire-launcher-demographics-openNext-unity'
        shellDrivenForegroundSwitchAfterInitialLaunchAllowed = $false
        reasons = @($reasons.ToArray())
    }
}

if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $QuestionnaireApk = Resolve-LatestTwoDFirstQuestionnaireApk
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$script:AaptPath = Resolve-Aapt $Aapt
$script:AdbPath = Resolve-Adb $Adb

if ([string]::IsNullOrWhiteSpace($Serial) -and -not $DryRun) {
    $devicesOutput = & $script:AdbPath devices -l
    $devices = @($devicesOutput | Select-String -Pattern '\sdevice\s')
    if ($devices.Count -eq 1) {
        $Serial = ($devices[0].ToString() -split '\s+')[0]
    }
}
if ([string]::IsNullOrWhiteSpace($Serial) -and -not $DryRun) {
    throw "No unique Quest serial detected. Pass -Serial explicitly."
}
$script:Serial = $Serial

$preflightDir = Join-Path $OutputRoot 'preflight'
New-Item -ItemType Directory -Force -Path $preflightDir | Out-Null
$questionnaireConfigEntry = Read-ZipEntryText -ZipPath $QuestionnaireApk -Pattern '(^|/)assets/questionnaire/QuestionnaireConfig\.json$|(^|/)questionnaire/QuestionnaireConfig\.json$'
$questionnaireConfig = $null
$questionnaireConfigParseStatus = 'missing'
if ($questionnaireConfigEntry) {
    try {
        $questionnaireConfig = $questionnaireConfigEntry.text | ConvertFrom-Json
        $questionnaireConfigParseStatus = 'pass'
    }
    catch {
        $questionnaireConfigParseStatus = 'fail'
    }
}

$unityCatalogEntry = Read-ZipEntryText -ZipPath $UnityApk -Pattern 'questionnaire-trigger-catalog\.json$'
$unityCatalog = $null
$unityCatalogParseStatus = 'missing'
if ($unityCatalogEntry) {
    try {
        $unityCatalog = $unityCatalogEntry.text | ConvertFrom-Json
        $unityCatalogParseStatus = 'pass'
    }
    catch {
        $unityCatalogParseStatus = 'fail'
    }
}

$apkInfo = [ordered]@{
    questionnaire = Get-ApkInfo -Apk $QuestionnaireApk -Name 'questionnaire-2d-first' -OutDir $preflightDir
    unity = Get-ApkInfo -Apk $UnityApk -Name 'unity-demo' -OutDir $preflightDir
}

$chainDefaults = if ($questionnaireConfig -and $questionnaireConfig.chainDefaults) { $questionnaireConfig.chainDefaults } else { $null }
$preflightIssues = New-Object 'System.Collections.Generic.List[string]'
if (-not [bool]$apkInfo.questionnaire.exists) { $preflightIssues.Add("Questionnaire APK not found: $QuestionnaireApk") | Out-Null }
if (-not [bool]$apkInfo.unity.exists) { $preflightIssues.Add("Unity APK not found: $UnityApk") | Out-Null }
if ($apkInfo.questionnaire.package -ne $questionnairePackage) { $preflightIssues.Add("Questionnaire package mismatch: $($apkInfo.questionnaire.package)") | Out-Null }
if ($apkInfo.questionnaire.activity -ne $questionnaireActivity) { $preflightIssues.Add("Questionnaire launch activity mismatch: $($apkInfo.questionnaire.activity)") | Out-Null }
if ($apkInfo.unity.package -ne $UnityPackage) { $preflightIssues.Add("Unity package mismatch: $($apkInfo.unity.package)") | Out-Null }
if ($apkInfo.unity.activity -ne $UnityActivity) { $preflightIssues.Add("Unity launch activity mismatch: $($apkInfo.unity.activity), expected $UnityActivity") | Out-Null }
if ([string]$questionnaireConfigParseStatus -ne 'pass') { $preflightIssues.Add("Packaged questionnaire config parse status: $questionnaireConfigParseStatus") | Out-Null }
if (-not $chainDefaults) {
    $preflightIssues.Add('Packaged questionnaire config does not include chainDefaults.') | Out-Null
} else {
    if ([string]$chainDefaults.startMode -ne 'questionnaireFirst') { $preflightIssues.Add("chainDefaults.startMode is '$($chainDefaults.startMode)', expected questionnaireFirst") | Out-Null }
    if ([string]$chainDefaults.finishBehavior -ne 'openNext') { $preflightIssues.Add("chainDefaults.finishBehavior is '$($chainDefaults.finishBehavior)', expected openNext") | Out-Null }
    if ([string]$chainDefaults.questionnaireMode -ne 'demographics') { $preflightIssues.Add("chainDefaults.questionnaireMode is '$($chainDefaults.questionnaireMode)', expected demographics") | Out-Null }
    if ([string]$chainDefaults.triggerId -ne 'trigger_1_launch_questionnaire') { $preflightIssues.Add("chainDefaults.triggerId is '$($chainDefaults.triggerId)', expected trigger_1_launch_questionnaire") | Out-Null }
    if ([string]$chainDefaults.nextPackage -ne $UnityPackage) { $preflightIssues.Add("chainDefaults.nextPackage is '$($chainDefaults.nextPackage)', expected $UnityPackage") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace([string]$chainDefaults.nextActivity) -and [string]$chainDefaults.nextActivity -ne $UnityActivity) {
        $preflightIssues.Add("chainDefaults.nextActivity is '$($chainDefaults.nextActivity)', expected $UnityActivity") | Out-Null
    }
}
if ([string]$unityCatalogParseStatus -ne 'pass') { $preflightIssues.Add("Unity APK trigger catalog parse status: $unityCatalogParseStatus") | Out-Null }
if ($unityCatalog -and [string]$unityCatalog.package -ne $UnityPackage) { $preflightIssues.Add("Unity trigger catalog package mismatch: $($unityCatalog.package)") | Out-Null }
if ($unityCatalog -and [string]$unityCatalog.activity -ne $UnityActivity) { $preflightIssues.Add("Unity trigger catalog activity mismatch: $($unityCatalog.activity)") | Out-Null }
if (-not [bool]$apkInfo.unity.inputModality.handTrackingFeature) { $preflightIssues.Add('Unity APK does not advertise optional hand tracking; generic stimulus APKs should support hands and controllers.') | Out-Null }
if (-not [bool]$apkInfo.unity.inputModality.handTrackingRequiredFalse) { $preflightIssues.Add('Unity APK hand tracking feature is missing android:required=false.') | Out-Null }
if (-not [bool]$apkInfo.unity.inputModality.handTrackingPermission) { $preflightIssues.Add('Unity APK does not declare the Quest hand tracking permission.') | Out-Null }

$preflightStatus = if ($preflightIssues.Count -eq 0) { 'pass' } else { 'fail' }
$preflightSummary = [ordered]@{
    status = $preflightStatus
    issues = @($preflightIssues.ToArray())
    questionnaireApk = $QuestionnaireApk
    unityApk = $UnityApk
    apkInfo = $apkInfo
    questionnaireConfig = [ordered]@{
        entry = if ($questionnaireConfigEntry) { $questionnaireConfigEntry.entry } else { "" }
        parseStatus = $questionnaireConfigParseStatus
        questionnaireId = if ($questionnaireConfig) { [string]$questionnaireConfig.questionnaireId } else { "" }
        questionnaireVersion = if ($questionnaireConfig) { [string]$questionnaireConfig.questionnaireVersion } else { "" }
        chainDefaults = $chainDefaults
    }
    unityTriggerCatalog = [ordered]@{
        entry = if ($unityCatalogEntry) { $unityCatalogEntry.entry } else { "" }
        parseStatus = $unityCatalogParseStatus
        triggerCount = if ($unityCatalog -and $unityCatalog.triggers) { @($unityCatalog.triggers).Count } else { 0 }
        package = if ($unityCatalog) { [string]$unityCatalog.package } else { "" }
        activity = if ($unityCatalog) { [string]$unityCatalog.activity } else { "" }
    }
}
Write-Json -Value $preflightSummary -Path (Join-Path $preflightDir 'preflight-summary.json') -Depth 14

if ($DryRun -or $preflightStatus -eq 'fail') {
    $status = if ($preflightStatus -eq 'pass') { 'pass' } else { 'fail' }
    $summary = [ordered]@{
        schemaVersion = 'mq.quest_2d_first_launcher_validation.v1'
        status = $status
        dryRun = [bool]$DryRun
        serial = $Serial
        outputRoot = $OutputRoot
        preflight = $preflightSummary
        trialCount = 0
        attemptedTrialCount = 0
        passCount = 0
        blockedCount = 0
        failCount = if ($preflightStatus -eq 'pass') { 0 } else { 1 }
        decisionGate = (New-DecisionGate `
            -IsDryRun ([bool]$DryRun) `
            -PreflightStatus $preflightStatus `
            -RequestedTrialCount $TrialCount `
            -AttemptedTrialCount 0 `
            -PassCount 0 `
            -BlockedCount 0 `
            -FailCount $(if ($preflightStatus -eq 'pass') { 0 } else { 1 }))
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $summaryPath = Join-Path $OutputRoot 'quest-2d-first-launcher-validation-summary.json'
    Write-Json -Value $summary -Path $summaryPath -Depth 16
    Write-Host "2D-first launcher validation status: $status"
    Write-Host "Summary: $summaryPath"
    if ($RequirePass -and $status -ne 'pass') {
        throw "2D-first launcher validation did not pass: $status. See $summaryPath"
    }
    exit $(if ($status -eq 'pass') { 0 } else { 1 })
}

$installDir = Join-Path $OutputRoot 'install'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
if (-not $SkipInstall) {
    Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $QuestionnaireApk) -OutputPath (Join-Path $installDir 'install-questionnaire.txt') | Out-Null
    Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $UnityApk) -OutputPath (Join-Path $installDir 'install-unity.txt') | Out-Null
}

$trialSummaries = New-Object 'System.Collections.Generic.List[object]'
for ($trial = 1; $trial -le $TrialCount; $trial++) {
    $trialId = "2d-first-launcher-trial-$trial-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $trialDir = Join-Path $OutputRoot ("trial-{0:000}" -f $trial)
    New-Item -ItemType Directory -Force -Path $trialDir | Out-Null
    $participantName = "P2DFirst{0:000}" -f $trial

    if ($WakeBeforeReadiness) {
        Invoke-AdbText -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') -OutputPath (Join-Path $trialDir 'wake-before-readiness.txt') | Out-Null
    }
    $readiness = Invoke-QuestReadiness -TrialDir $trialDir
    if (-not [bool]$readiness.productPathReady -and -not $AllowLaunchWhenNotReady) {
        $trialSummary = [ordered]@{
            trial = $trial
            status = 'blocked'
            trialDir = $trialDir
            participantName = $participantName
            productPath = [ordered]@{
                blockedBeforeProductPath = $true
                initialQuestionnaireLaunchAttempted = $false
                initialQuestionnaireLaunchOnly = $false
                shellDrivenForegroundSwitchAfterInitialLaunch = $false
                noAdbAmStartAfterInitialLaunch = $true
                autoReplayMarkerUsed = -not [bool]$NoAutoReplay
                wakeBeforeReadiness = [bool]$WakeBeforeReadiness
            }
            readiness = $readiness
            blockedReasons = @("product-path-not-ready-$($readiness.productPathStatus)")
            failureReasons = @()
        }
        Write-Json -Value $trialSummary -Path (Join-Path $trialDir 'trial-summary.json') -Depth 14
        $trialSummaries.Add($trialSummary) | Out-Null
        break
    }

    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $questionnairePackage) -OutputPath (Join-Path $trialDir 'setup-force-stop-questionnaire.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $UnityPackage) -OutputPath (Join-Path $trialDir 'setup-force-stop-unity.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', "rm -rf '$questionnaireExports' && mkdir -p '$questionnaireFiles'") -OutputPath (Join-Path $trialDir 'setup-clear-questionnaire-state.txt') | Out-Null

    if (-not $NoAutoReplay) {
        $marker = Join-Path $trialDir 'command-replay-english.json'
        New-ReplayMarker -Path $marker -ParticipantName $participantName
        Invoke-AdbText -Arguments @('push', $marker, "$questionnaireFiles/command-replay-english.json") -OutputPath (Join-Path $trialDir 'setup-push-command-replay-marker.txt') | Out-Null
    }

    Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $trialDir 'setup-logcat-clear.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $trialDir 'focus-before-launch.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'power') -OutputPath (Join-Path $trialDir 'power-before-launch.txt') | Out-Null

    $launch = Invoke-AdbText -Arguments @(
        'shell', 'am', 'start',
        '-a', 'android.intent.action.MAIN',
        '-c', 'android.intent.category.LAUNCHER',
        '-n', "$questionnairePackage/$questionnaireActivity"
    ) -OutputPath (Join-Path $trialDir 'product-path-initial-launch-questionnaire.txt')

    $focusJsonl = Join-Path $trialDir 'focus-samples.jsonl'
    "" | Set-Content -LiteralPath $focusJsonl -Encoding UTF8
    $focusSamples = New-Object 'System.Collections.Generic.List[object]'
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $sampleIndex = 0
    while ((Get-Date) -lt $deadline) {
        $sampleIndex++
        $focusPath = Join-Path $trialDir ("focus-sample-{0:0000}.txt" -f $sampleIndex)
        $focus = Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath $focusPath
        $sample = [ordered]@{
            index = $sampleIndex
            timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
            package = Get-FocusPackage -Text $focus.text
            lines = Get-FocusLines -Text $focus.text
            path = $focusPath
        }
        $focusSamples.Add($sample) | Out-Null
        ($sample | ConvertTo-Json -Compress -Depth 5) | Add-Content -LiteralPath $focusJsonl -Encoding UTF8
        Start-Sleep -Milliseconds ([Math]::Max(250, $FocusPollMilliseconds))
    }

    Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $trialDir 'logcat.txt') | Out-Null
    Invoke-AdbText -Arguments @(
        'logcat', '-d', '-v', 'threadtime',
        'MyQuestionnaire2D:I',
        'Unity:I',
        'ActivityTaskManager:I',
        'AndroidRuntime:E',
        '*:S'
    ) -OutputPath (Join-Path $trialDir 'logcat-filtered.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $trialDir 'focus-final.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'power') -OutputPath (Join-Path $trialDir 'power-final.txt') | Out-Null

    $pullRoot = Join-Path $trialDir 'device-files'
    $questionnairePull = Pull-DeviceTree -DevicePath $questionnaireExports -Destination (Join-Path $pullRoot 'questionnaire') -Label 'questionnaire-exports' -TrialDir $trialDir

    $logText = Get-Content -LiteralPath (Join-Path $trialDir 'logcat.txt') -Raw
    $filteredLogText = Get-Content -LiteralPath (Join-Path $trialDir 'logcat-filtered.txt') -Raw
    $allLogText = $logText + "`n" + $filteredLogText
    $finalFocus = Get-Content -LiteralPath (Join-Path $trialDir 'focus-final.txt') -Raw
    $powerFinal = Get-Content -LiteralPath (Join-Path $trialDir 'power-final.txt') -Raw
    $observedPackages = @($focusSamples | ForEach-Object { $_.package } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $finalUnityFocused = ((Get-FocusLines -Text $finalFocus) -join "`n") -match [regex]::Escape($UnityPackage)
    $headsetAsleep = $powerFinal -match 'mWakefulness=Asleep' -or $finalFocus -match 'isSleeping=true'
    $displayOffFinal = $powerFinal -match 'mInteractive=false|Display Power:\s*state=OFF'
    $qJsonCount = @($questionnairePull.files | Where-Object { $_.local -match '\.json$' -and $_.local -notmatch 'in_progress' }).Count
    $qCsvCount = @($questionnairePull.files | Where-Object { $_.local -match '\.csv$' -and $_.local -notmatch 'in_progress' }).Count

    $markerCounts = [ordered]@{
        fatalLogs = Count-Matches -Text $allLogText -Pattern 'FATAL EXCEPTION|AndroidRuntime'
        controllerRequiredDialogs = Count-Matches -Text ($allLogText + "`n" + $finalFocus) -Pattern 'LaunchCheckControllerRequiredDialogActivity'
        questionnaireReplayStart = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_COMMAND_REPLAY_START'
        questionnaireExportComplete = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_EXPORT_COMPLETE'
        questionnaireOpenNextReturn = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_CHAIN_RETURN finishBehavior=openNext'
        questionnaireTargetMissing = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_CHAIN_TARGET_MISSING'
        questionnaireReturnFailed = Count-Matches -Text $allLogText -Pattern 'MYQUESTIONNAIRE_CHAIN_RETURN_FAILED'
        unityStartGateReady = Count-Matches -Text $allLogText -Pattern 'QQ_STIMULUS_START_GATE_READY|START_GATE_READY'
        unityExperimentStart = Count-Matches -Text $allLogText -Pattern 'QQ_STIMULUS_EXPERIMENT_START|VIDEO_PREPARE_START|VIDEO_PLAY'
    }

    $handoffOk = (
        $launch.exitCode -eq 0 -and
        $markerCounts.fatalLogs -eq 0 -and
        ($NoAutoReplay -or $markerCounts.questionnaireReplayStart -ge 1) -and
        $markerCounts.questionnaireExportComplete -ge 1 -and
        $markerCounts.questionnaireOpenNextReturn -ge 1 -and
        $markerCounts.questionnaireTargetMissing -eq 0 -and
        $markerCounts.questionnaireReturnFailed -eq 0 -and
        ($observedPackages -contains $questionnairePackage) -and
        ($observedPackages -contains $UnityPackage) -and
        $qJsonCount -ge 1 -and
        $qCsvCount -ge 1
    )

    $blockedReasons = New-Object 'System.Collections.Generic.List[string]'
    $failureReasons = New-Object 'System.Collections.Generic.List[string]'
    if ($markerCounts.controllerRequiredDialogs -gt 0 -and -not ($observedPackages -contains $UnityPackage)) {
        $blockedReasons.Add('horizon-controller-required-launch-check-before-unity') | Out-Null
    }
    if (($headsetAsleep -or $displayOffFinal) -and -not $handoffOk -and $markerCounts.fatalLogs -eq 0) {
        $blockedReasons.Add('headset-asleep-or-display-off-during-2d-first-product-path') | Out-Null
    }
    if ($markerCounts.questionnaireTargetMissing -gt 0) { $failureReasons.Add('questionnaire-openNext-target-missing') | Out-Null }
    if ($markerCounts.questionnaireReturnFailed -gt 0) { $failureReasons.Add('questionnaire-openNext-launch-failed') | Out-Null }
    if ($markerCounts.questionnaireOpenNextReturn -lt 1) { $failureReasons.Add('questionnaire-openNext-return-not-observed') | Out-Null }
    if (-not ($observedPackages -contains $UnityPackage)) { $failureReasons.Add('unity-foreground-not-observed-after-questionnaire') | Out-Null }
    if ($qJsonCount -lt 1 -or $qCsvCount -lt 1) { $failureReasons.Add('questionnaire-export-files-missing') | Out-Null }

    $trialStatus = 'fail'
    if ($blockedReasons.Count -gt 0) {
        $trialStatus = 'blocked'
    } elseif ($handoffOk -and $finalUnityFocused) {
        $trialStatus = 'pass'
    } elseif ($handoffOk) {
        $trialStatus = 'warn'
    }

    $trialSummary = [ordered]@{
        trial = $trial
        status = $trialStatus
        trialDir = $trialDir
        participantName = $participantName
        launchExitCode = $launch.exitCode
        productPath = [ordered]@{
            blockedBeforeProductPath = $false
            initialQuestionnaireLaunchAttempted = $true
            initialQuestionnaireLaunchOnly = $true
            shellDrivenForegroundSwitchAfterInitialLaunch = $false
            noAdbForceStopAfterInitialLaunch = $true
            noAdbAmStartAfterInitialLaunch = $true
            autoReplayMarkerUsed = -not [bool]$NoAutoReplay
            wakeBeforeReadiness = [bool]$WakeBeforeReadiness
        }
        readiness = $readiness
        markerCounts = $markerCounts
        blockedReasons = @($blockedReasons.ToArray())
        failureReasons = @($failureReasons.ToArray())
        focus = [ordered]@{
            observedPackages = $observedPackages
            finalUnityFocused = $finalUnityFocused
            sampleCount = $focusSamples.Count
            focusSamplesJsonl = $focusJsonl
        }
        power = [ordered]@{
            headsetAsleep = $headsetAsleep
            displayOff = $displayOffFinal
            final = (Join-Path $trialDir 'power-final.txt')
        }
        exports = [ordered]@{
            questionnaire = [ordered]@{
                jsonCount = $qJsonCount
                csvCount = $qCsvCount
                pull = $questionnairePull
            }
        }
        evidence = [ordered]@{
            logcat = (Join-Path $trialDir 'logcat.txt')
            filteredLogcat = (Join-Path $trialDir 'logcat-filtered.txt')
            focusFinal = (Join-Path $trialDir 'focus-final.txt')
        }
    }
    Write-Json -Value $trialSummary -Path (Join-Path $trialDir 'trial-summary.json') -Depth 16
    $trialSummaries.Add($trialSummary) | Out-Null
}

$trialArray = @($trialSummaries.ToArray())
$passCount = @($trialArray | Where-Object { $_.status -eq 'pass' }).Count
$blockedCount = @($trialArray | Where-Object { $_.status -eq 'blocked' }).Count
$failCount = @($trialArray | Where-Object { $_.status -eq 'fail' }).Count
$warnCount = @($trialArray | Where-Object { $_.status -eq 'warn' }).Count
$overallStatus = 'fail'
if ($failCount -eq 0 -and $blockedCount -eq 0 -and $warnCount -eq 0 -and $passCount -eq $TrialCount) {
    $overallStatus = 'pass'
} elseif ($passCount -gt 0 -and $failCount -eq 0) {
    $overallStatus = 'warn'
} elseif ($blockedCount -gt 0 -and $passCount -eq 0 -and $failCount -eq 0) {
    $overallStatus = 'blocked'
}

$summary = [ordered]@{
    schemaVersion = 'mq.quest_2d_first_launcher_validation.v1'
    status = $overallStatus
    dryRun = $false
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
    wakeBeforeReadiness = [bool]$WakeBeforeReadiness
    allowLaunchWhenNotReady = [bool]$AllowLaunchWhenNotReady
    preflight = $preflightSummary
    trials = $trialArray
    decisionGate = (New-DecisionGate `
        -IsDryRun $false `
        -PreflightStatus $preflightStatus `
        -RequestedTrialCount $TrialCount `
        -AttemptedTrialCount $trialArray.Count `
        -PassCount $passCount `
        -BlockedCount $blockedCount `
        -FailCount $failCount)
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$summaryPath = Join-Path $OutputRoot 'quest-2d-first-launcher-validation-summary.json'
Write-Json -Value $summary -Path $summaryPath -Depth 18

Write-Host "2D-first launcher validation status: $overallStatus"
Write-Host "Summary: $summaryPath"
Write-Host "Pass: $passCount; Warn: $warnCount; Blocked: $blockedCount; Fail: $failCount"

if ($RequirePass -and $overallStatus -ne 'pass') {
    throw "2D-first launcher validation did not pass: $overallStatus. See $summaryPath"
}
