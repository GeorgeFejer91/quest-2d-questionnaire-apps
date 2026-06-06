param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$Apk = "",
    [string[]]$AutoValidateLanguages = @("English", "Deutsch"),
    [int]$WaitSeconds = 20,
    [switch]$NoAutoValidate,
    [switch]$UseLegacyAutoValidation,
    [switch]$LeaveForeground,
    [switch]$StopLegacyUnityApp,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$package = "org.viscereality.questionnaires2d"
$activity = "org.viscereality.questionnaires2d.MainActivity"
$legacyUnityPackage = "org.viscereality.questionnaires"
if ([string]::IsNullOrWhiteSpace($Apk)) {
    $apk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
}
else {
    $apk = $Apk
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $outDir = Join-Path $ProjectPath 'artifacts\quest-validation'
}
else {
    $outDir = $OutputRoot
}

if ([string]::IsNullOrWhiteSpace($Adb)) {
    $mqdhAdb = "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe"
    $unityAdb = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
    if (Test-Path -LiteralPath $mqdhAdb) {
        $Adb = $mqdhAdb
    }
    elseif (Test-Path -LiteralPath $unityAdb) {
        $Adb = $unityAdb
    }
}

if (-not (Test-Path -LiteralPath $Adb)) {
    throw "ADB not found. Pass -Adb explicitly."
}

function Invoke-AdbText {
    param(
        [string[]]$Arguments,
        [string]$OutputPath
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Adb -s $Serial @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return $exitCode
}

function Save-AdbScreenshot {
    param([string]$Path)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Adb
    $psi.Arguments = "-s $Serial exec-out screencap -p"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $stream = [System.IO.File]::Create($Path)
    try {
        $process.StandardOutput.BaseStream.CopyTo($stream)
    }
    finally {
        $stream.Dispose()
    }

    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($stderr) {
        Set-Content -LiteralPath "$Path.stderr.txt" -Value $stderr -Encoding UTF8
    }

    if (Test-Path -LiteralPath $Path) {
        return (Get-Item -LiteralPath $Path).Length
    }

    return 0
}

function Get-MarkerName {
    param([string]$Language)

    if ($UseLegacyAutoValidation) {
        if ($Language -match '(?i)Deutsch|German') { return 'auto-validate-deutsch.txt' }
        return 'auto-validate-english.txt'
    }

    if ($Language -match '(?i)Deutsch|German') { return 'command-replay-deutsch.json' }
    return 'command-replay-english.json'
}

function Get-ExportRecords {
    param([string]$ExportDir)

    $records = @()
    $jsonFiles = Get-ChildItem -LiteralPath $ExportDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]in_progress[\\/]' }
    foreach ($jsonFile in $jsonFiles) {
        try {
            $record = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
            $timestamp = [DateTime]::MinValue
            if ($record.timestampUtc) {
                [DateTime]::TryParse($record.timestampUtc.ToString(), [ref]$timestamp) | Out-Null
            }

            $records += [pscustomobject]@{
                File = $jsonFile
                Record = $record
                Participant = $record.participant.name
                Language = $record.participant.language
                Timestamp = $timestamp
            }
        }
        catch {
            Write-Warning "Could not parse pulled questionnaire JSON: $($jsonFile.FullName)"
        }
    }

    return $records
}

function Get-ExpectedCounts {
    param([string]$ProjectPath)

    $runtimeConfigPath = Join-Path $ProjectPath 'app\src\main\assets\questionnaire\QuestionnaireConfig.json'
    if (-not (Test-Path -LiteralPath $runtimeConfigPath)) {
        return [ordered]@{ maia2Answers = 37; maia2Scores = 8; pictographicSelections = 3; questionnaireAnswers = 42 }
    }

    $runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json
    $maiaBlock = @($runtimeConfig.blocks | Where-Object { $_.id -eq 'maia2' } | Select-Object -First 1)[0]
    $pictographicBlock = @($runtimeConfig.blocks | Where-Object { $_.type -eq 'pictographic' } | Select-Object -First 1)[0]
    $sliderBlock = @($runtimeConfig.blocks | Where-Object { $_.type -eq 'slider' } | Select-Object -First 1)[0]

    return [ordered]@{
        maia2Answers = if ($maiaBlock) { [int]$maiaBlock.expectedItemCount } else { 0 }
        maia2Scores = if ($maiaBlock) { 8 } else { 0 }
        pictographicSelections = if ($pictographicBlock) { @($pictographicBlock.prompts).Count } else { 0 }
        questionnaireAnswers = if ($sliderBlock) { [int]$sliderBlock.expectedItemCount } else { 0 }
    }
}

if (-not $SkipBuild) {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-apk.ps1')
}

if (-not (Test-Path -LiteralPath $apk)) {
    throw "APK not found: $apk"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = & $Adb devices -l | Select-String -Pattern '\sdevice\s'
    if (@($devices).Count -eq 1) {
        $Serial = (@($devices)[0].ToString() -split '\s+')[0]
    }
}

if ([string]::IsNullOrWhiteSpace($Serial)) {
    throw "No unique Quest serial detected. Pass -Serial explicitly."
}

$runLanguages = if ($NoAutoValidate) { @("manual") } else { @($AutoValidateLanguages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
if ($runLanguages.Count -eq 0) {
    $runLanguages = @("English")
}

$expectedCounts = Get-ExpectedCounts -ProjectPath $ProjectPath
$deviceExports = "/sdcard/Android/data/$package/files/QuestionnaireExports"
$filesDir = "/sdcard/Android/data/$package/files"
$markerCleanup = "rm -f '$filesDir/auto-validate.txt' '$filesDir/auto-validate-english.txt' '$filesDir/auto-validate-deutsch.txt' '$filesDir/command-replay-english.json' '$filesDir/command-replay-deutsch.json'"
$runChecks = New-Object 'System.Collections.Generic.List[object]'

foreach ($language in $runLanguages) {
    $safeLanguage = ($language -replace '[^A-Za-z0-9_-]', '_')
    $runOutDir = Join-Path $outDir ("run-" + $safeLanguage)
    New-Item -ItemType Directory -Force -Path $runOutDir | Out-Null

    Invoke-AdbText -Arguments @("devices", "-l") -OutputPath (Join-Path $runOutDir 'adb-devices.txt') | Out-Null
    Invoke-AdbText -Arguments @("shell", "getprop", "ro.product.model") -OutputPath (Join-Path $runOutDir 'device-model.txt') | Out-Null
    Invoke-AdbText -Arguments @("shell", "getprop", "ro.build.version.release") -OutputPath (Join-Path $runOutDir 'android-version.txt') | Out-Null
    Invoke-AdbText -Arguments @("shell", "wm", "size") -OutputPath (Join-Path $runOutDir 'wm-size.txt') | Out-Null
    Invoke-AdbText -Arguments @("shell", "wm", "density") -OutputPath (Join-Path $runOutDir 'wm-density.txt') | Out-Null
    Invoke-AdbText -Arguments @("shell", "dumpsys", "window") -OutputPath (Join-Path $runOutDir 'foreground-before.txt') | Out-Null

    $installExitCode = Invoke-AdbText -Arguments @("install", "-r", "-d", "-g", $apk) -OutputPath (Join-Path $runOutDir 'install.txt')
    if ($installExitCode -ne 0) {
        throw "APK install failed for $language. See $runOutDir\install.txt"
    }

    if ($StopLegacyUnityApp) {
        $legacyFilesDir = "/sdcard/Android/data/$legacyUnityPackage/files"
        $legacyMarkerCleanup = "rm -f '$legacyFilesDir/auto-validate.txt' '$legacyFilesDir/auto-validate-english.txt' '$legacyFilesDir/auto-validate-deutsch.txt' '$legacyFilesDir/command-replay-english.json' '$legacyFilesDir/command-replay-deutsch.json'"
        Invoke-AdbText -Arguments @("shell", "am", "force-stop", $legacyUnityPackage) -OutputPath (Join-Path $runOutDir 'force-stop-legacy-unity.txt') | Out-Null
        Invoke-AdbText -Arguments @("shell", $legacyMarkerCleanup) -OutputPath (Join-Path $runOutDir 'remove-legacy-validation-markers.txt') | Out-Null
    }

    Invoke-AdbText -Arguments @("shell", "am", "force-stop", $package) -OutputPath (Join-Path $runOutDir 'force-stop-before.txt') | Out-Null

    if (-not $NoAutoValidate) {
        $markerName = Get-MarkerName -Language $language
        $marker = "$filesDir/$markerName"
        $markerCommand = "mkdir -p '$filesDir' && $markerCleanup && rm -rf '$deviceExports' && touch '$marker'"
        $markerExitCode = Invoke-AdbText -Arguments @("shell", $markerCommand) -OutputPath (Join-Path $runOutDir 'prepare-validation-marker.txt')
        if ($markerExitCode -ne 0) {
            throw "Could not create validation marker at $marker for $language"
        }

        "requestedLanguage=$language`nmarker=$marker`nmode=$(if ($UseLegacyAutoValidation) { 'auto-validation' } else { 'command-replay' })" |
            Set-Content -LiteralPath (Join-Path $runOutDir 'validation-marker.txt') -Encoding UTF8
    }
    else {
        Invoke-AdbText -Arguments @("shell", "mkdir -p '$filesDir' && $markerCleanup") -OutputPath (Join-Path $runOutDir 'clear-validation-markers.txt') | Out-Null
    }

    Invoke-AdbText -Arguments @("logcat", "-c") -OutputPath (Join-Path $runOutDir 'logcat-clear.txt') | Out-Null
    $launchExitCode = Invoke-AdbText -Arguments @("shell", "am", "start", "-n", "$package/$activity") -OutputPath (Join-Path $runOutDir 'launch.txt')
    if ($launchExitCode -ne 0) {
        Write-Warning "Quest launch exited with code $launchExitCode for $language. Continuing with evidence/export collection."
    }

    Start-Sleep -Seconds $WaitSeconds

    $screenshotBytes = Save-AdbScreenshot -Path (Join-Path $runOutDir 'screenshot-after-wait.png')
    Invoke-AdbText -Arguments @("shell", "pidof", $package) -OutputPath (Join-Path $runOutDir 'pidof-after.txt') | Out-Null
    Invoke-AdbText -Arguments @("shell", "dumpsys", "window") -OutputPath (Join-Path $runOutDir 'foreground-after.txt') | Out-Null
    Invoke-AdbText -Arguments @("logcat", "-d", "-v", "threadtime") -OutputPath (Join-Path $runOutDir 'logcat.txt') | Out-Null
    Invoke-AdbText -Arguments @("logcat", "-d", "-v", "threadtime", "MyQuestionnaire2D:I", "AndroidRuntime:E", "*:S") -OutputPath (Join-Path $runOutDir 'logcat-myquestionnaire2d.txt') | Out-Null
    Invoke-AdbText -Arguments @("shell", $markerCleanup) -OutputPath (Join-Path $runOutDir 'remove-validation-markers.txt') | Out-Null

    $exportOut = Join-Path $runOutDir 'QuestionnaireExports'
    $resolvedRunOutDir = [System.IO.Path]::GetFullPath($runOutDir)
    $resolvedExportOut = [System.IO.Path]::GetFullPath($exportOut)
    if (-not $resolvedExportOut.StartsWith($resolvedRunOutDir, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean export pull directory outside run evidence directory: $resolvedExportOut"
    }

    if (Test-Path -LiteralPath $exportOut) {
        Remove-Item -LiteralPath $exportOut -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $exportOut | Out-Null
    $pullStdout = Join-Path $runOutDir 'pull-questionnaire-exports-stdout.txt'
    $pullStderr = Join-Path $runOutDir 'pull-questionnaire-exports-stderr.txt'
    $pullProcess = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $deviceExports, $exportOut) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $pullStdout -RedirectStandardError $pullStderr
    $pullExitCode = $pullProcess.ExitCode
    $pullOutput = @()
    if (Test-Path -LiteralPath $pullStdout) { $pullOutput += Get-Content -LiteralPath $pullStdout -Encoding UTF8 }
    if (Test-Path -LiteralPath $pullStderr) { $pullOutput += Get-Content -LiteralPath $pullStderr -Encoding UTF8 }
    $pullOutput | Set-Content -LiteralPath (Join-Path $runOutDir 'pull-questionnaire-exports.txt') -Encoding UTF8

    $records = @(Get-ExportRecords -ExportDir $exportOut | Sort-Object -Property Timestamp -Descending)
    $selectedRecord = if ($records.Count -gt 0) { $records[0] } else { $null }
    $pulledJson = if ($selectedRecord) { $selectedRecord.File } else { $null }
    $pulledCsv = $null
    if ($pulledJson) {
        $candidateCsvPath = [System.IO.Path]::ChangeExtension($pulledJson.FullName, '.csv')
        if (Test-Path -LiteralPath $candidateCsvPath) {
            $pulledCsv = Get-Item -LiteralPath $candidateCsvPath
        }
    }

    $logPath = Join-Path $runOutDir 'logcat.txt'
    $taggedLogPath = Join-Path $runOutDir 'logcat-myquestionnaire2d.txt'
    $logText = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { "" }
    if (Test-Path -LiteralPath $taggedLogPath) {
        $logText += "`n" + (Get-Content -LiteralPath $taggedLogPath -Raw)
    }
    $visualStages = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_VISUAL_STAGE stage=([a-z0-9-]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $commandEventCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_COMMAND command=')).Count
    $requiredVisualStages = @('language', 'demographics')
    if ($expectedCounts.maia2Answers -gt 0) { $requiredVisualStages += 'maia2' }
    if ($expectedCounts.pictographicSelections -gt 0) { $requiredVisualStages += 'pictographic' }
    if ($expectedCounts.questionnaireAnswers -gt 0) { $requiredVisualStages += 'slider' }
    $requiredVisualStages += @('saved-confirmation', 'finished-black')
    $visualStageReplayPassed = $true
    foreach ($requiredStage in $requiredVisualStages) {
        if (-not ($visualStages -contains $requiredStage)) {
            $visualStageReplayPassed = $false
        }
    }
    $check = [ordered]@{
        languageRequested = if ($NoAutoValidate) { $null } else { $language }
        validationMode = if ($NoAutoValidate) { "manual" } elseif ($UseLegacyAutoValidation) { "auto-validation" } else { "command-replay" }
        installExitCode = $installExitCode
        launchExitCode = $launchExitCode
        pullExitCode = $pullExitCode
        evidenceDir = $runOutDir
        screenshotBytes = $screenshotBytes
        foundJson = $null -ne $pulledJson
        foundCsv = $null -ne $pulledCsv
        json = if ($pulledJson) { $pulledJson.FullName } else { $null }
        csv = if ($pulledCsv) { $pulledCsv.FullName } else { $null }
        participant = $null
        recordLanguage = $null
        maia2Answers = $null
        maia2Scores = $null
        pictographicSelections = $null
        questionnaireAnswers = $null
        questionnaireConfigId = $null
        expectedCounts = $expectedCounts
        commandReplayStarted = [bool]($logText -match 'MYQUESTIONNAIRE_COMMAND_REPLAY_START')
        commandReplayPassed = [bool]($logText -match 'MYQUESTIONNAIRE_NAVIGATION_SUMMARY status=pass mode=command-replay')
        commandReplayExportMatched = [bool]($logText -match 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH')
        exportCompleteLogged = [bool]($logText -match 'MYQUESTIONNAIRE_EXPORT_COMPLETE')
        commandEventCount = $commandEventCount
        visualStages = $visualStages
        visualStageReplayPassed = $visualStageReplayPassed
        fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
    }

    if ($selectedRecord) {
        $record = $selectedRecord.Record
        $check.participant = $record.participant.name
        $check.recordLanguage = $record.participant.language
        $check.maia2Answers = @($record.maia2Answers).Count
        $check.maia2Scores = @($record.maia2Scores).Count
        $check.pictographicSelections = @($record.pictographicSelections).Count
        $check.questionnaireAnswers = @($record.questionnaireAnswers).Count
        $check.questionnaireConfigId = $record.questionnaireConfigId
    }

    $runChecks.Add($check) | Out-Null
    $isLastRun = $language -eq $runLanguages[$runLanguages.Count - 1]
    if ($LeaveForeground -and $isLastRun) {
        "LeaveForeground requested; final validation run was not force-stopped." |
            Set-Content -LiteralPath (Join-Path $runOutDir 'leave-foreground.txt') -Encoding UTF8
    }
    else {
        Invoke-AdbText -Arguments @("shell", "am", "force-stop", $package) -OutputPath (Join-Path $runOutDir 'force-stop-after-run.txt') | Out-Null
    }
}

$summary = [ordered]@{
    schemaVersion = "my-questionnaire-2d.validation.v1"
    serial = $Serial
    package = $package
    activity = $activity
    apk = $apk
    evidenceDir = $outDir
    deviceExports = $deviceExports
    validationMode = if ($NoAutoValidate) { "manual" } elseif ($UseLegacyAutoValidation) { "auto-validation" } else { "command-replay" }
    leaveForeground = [bool]$LeaveForeground
    stopLegacyUnityApp = [bool]$StopLegacyUnityApp
    expectedCounts = $expectedCounts
    requestedLanguages = if ($NoAutoValidate) { @() } else { @($runLanguages) }
    exportChecks = @($runChecks.ToArray())
    completedAt = (Get-Date).ToString("o")
}

$summaryPath = Join-Path $outDir 'my-questionnaire-2d-validation-summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest validation evidence written to $outDir"

if (-not $NoAutoValidate) {
    $failed = @($runChecks.ToArray() | Where-Object {
        -not $_.exportCompleteLogged -or
        -not $_.foundJson -or
        -not $_.foundCsv -or
        $_.fatalLogCount -ne 0 -or
        $_.maia2Answers -ne $expectedCounts.maia2Answers -or
        $_.maia2Scores -ne $expectedCounts.maia2Scores -or
        $_.pictographicSelections -ne $expectedCounts.pictographicSelections -or
        $_.questionnaireAnswers -ne $expectedCounts.questionnaireAnswers -or
        (-not $UseLegacyAutoValidation -and (-not $_.commandReplayStarted -or -not $_.commandReplayPassed -or -not $_.commandReplayExportMatched -or -not $_.visualStageReplayPassed -or $_.commandEventCount -lt 8 -or $_.participant -ne "George"))
    })

    if ($failed.Count -gt 0) {
        throw "Quest validation failed for $($failed.Count) run(s). See $summaryPath"
    }
}
