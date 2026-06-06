param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ConfigPath = "",
    [string]$OutputRoot = "",
    [string]$Apk = "",
    [int]$WaitSeconds = 24,
    [string]$ParticipantName = "ChainParticipant",
    [string]$SessionId = "",
    [string]$NextPackage = "",
    [string]$NextActivity = "",
    [switch]$SkipBuild,
    [switch]$StopLegacyUnityApp
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$package = "org.mesmerprism.viscereality.questionnaires2d"
$activity = "org.mesmerprism.viscereality.questionnaires2d.MainActivity"
$action = "org.mesmerprism.viscereality.questionnaires2d.RUN"
$legacyUnityPackage = "org.mesmerprism.viscereality.questionnaires"
$deviceExports = "/sdcard/Android/data/$package/files/QuestionnaireExports"
$filesDir = "/sdcard/Android/data/$package/files"

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = "chain-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-chain-validation\" + $SessionId)
}
if ([string]::IsNullOrWhiteSpace($Apk)) {
    $Apk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
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

function Get-FinalExportRecords {
    param([string]$ExportDir)
    $records = @()
    $jsonFiles = Get-ChildItem -LiteralPath $ExportDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]in_progress[\\/]' }
    foreach ($jsonFile in $jsonFiles) {
        try {
            $record = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
            if ($record.PSObject.Properties.Name -contains 'runId') {
                $records += [pscustomobject]@{ File = $jsonFile; Record = $record }
            }
        }
        catch {
            Write-Warning "Could not parse export JSON: $($jsonFile.FullName)"
        }
    }
    return $records
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
    $buildArgs = @('-File', (Join-Path $ProjectPath 'tools\build-apk.ps1'))
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $buildArgs += @('-ConfigPath', $ConfigPath)
    }
    powershell -NoProfile -ExecutionPolicy Bypass @buildArgs
}
if (-not (Test-Path -LiteralPath $Apk)) {
    throw "APK not found: $Apk"
}

Invoke-AdbText -Arguments @('devices', '-l') -OutputPath (Join-Path $OutputRoot 'adb-devices.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.product.model') -OutputPath (Join-Path $OutputRoot 'device-model.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.build.version.release') -OutputPath (Join-Path $OutputRoot 'android-version.txt') | Out-Null

$installExitCode = Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $Apk) -OutputPath (Join-Path $OutputRoot 'install.txt')
if ($installExitCode -ne 0) {
    throw "APK install failed. See $OutputRoot\install.txt"
}

if ($StopLegacyUnityApp) {
    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $legacyUnityPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-legacy-unity.txt') | Out-Null
}
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $package) -OutputPath (Join-Path $OutputRoot 'force-stop-before.txt') | Out-Null
Invoke-AdbText -Arguments @('shell', "rm -rf '$deviceExports' && mkdir -p '$filesDir'") -OutputPath (Join-Path $OutputRoot 'clear-exports.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$finishBehavior = if ([string]::IsNullOrWhiteSpace($NextPackage)) { 'staySaved' } else { 'openNext' }
$runSummaries = @()
for ($run = 1; $run -le 2; $run++) {
    $runDir = Join-Path $OutputRoot "run-$run"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $markerName = 'command-replay-english.json'
    $localMarker = Join-Path $runDir $markerName
    @{
        ParticipantName = $ParticipantName
        ExpectedAge = 33
        GenderFocusId = 'gender.0'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $localMarker -Encoding UTF8
    $pushStdout = Join-Path $runDir 'push-marker-stdout.txt'
    $pushStderr = Join-Path $runDir 'push-marker-stderr.txt'
    $push = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $localMarker, "$filesDir/$markerName") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $pushStdout -RedirectStandardError $pushStderr
    if ($push.ExitCode -ne 0) {
        throw "Could not push command replay marker for run $run"
    }

    $launchArgs = @(
        'shell', 'am', 'start',
        '-a', $action,
        '-n', "$package/$activity",
        '--es', 'mq.sessionId', $SessionId,
        '--es', 'mq.invocationId', "$SessionId-run-$run",
        '--es', 'mq.experimentId', 'chain-validation',
        '--es', 'mq.scenarioId', "scenario-$run",
        '--es', 'mq.trialId', "trial-$run",
        '--es', 'mq.participantId', $ParticipantName,
        '--es', 'mq.participantName', $ParticipantName,
        '--es', 'mq.language', 'English',
        '--es', 'mq.finishBehavior', $finishBehavior,
        '--el', 'mq.autoCloseDelayMs', '0'
    )
    if (-not [string]::IsNullOrWhiteSpace($NextPackage)) {
        $launchArgs += @('--es', 'mq.nextPackage', $NextPackage)
    }
    if (-not [string]::IsNullOrWhiteSpace($NextActivity)) {
        $launchArgs += @('--es', 'mq.nextActivity', $NextActivity)
    }

    $launchExitCode = Invoke-AdbText -Arguments $launchArgs -OutputPath (Join-Path $runDir 'launch-chain.txt')
    Start-Sleep -Seconds $WaitSeconds
    Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $runDir 'foreground-after.txt') | Out-Null
    Invoke-AdbText -Arguments @('shell', 'pidof', $package) -OutputPath (Join-Path $runDir 'pidof-after.txt') | Out-Null
    $runSummaries += [ordered]@{ run = $run; launchExitCode = $launchExitCode }
}

Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $OutputRoot 'logcat.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'MyQuestionnaire2D:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-myquestionnaire2d.txt') | Out-Null

$exportOut = Join-Path $OutputRoot 'QuestionnaireExports'
if (Test-Path -LiteralPath $exportOut) {
    Remove-Item -LiteralPath $exportOut -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $exportOut | Out-Null
$pullStdout = Join-Path $OutputRoot 'pull-exports-stdout.txt'
$pullStderr = Join-Path $OutputRoot 'pull-exports-stderr.txt'
$pull = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $deviceExports, $exportOut) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $pullStdout -RedirectStandardError $pullStderr

$records = @(Get-FinalExportRecords -ExportDir $exportOut)
$runIds = @($records | ForEach-Object { $_.Record.runId } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$indexFile = Get-ChildItem -LiteralPath $exportOut -Filter 'session-index.jsonl' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$draftFiles = @(Get-ChildItem -LiteralPath $exportOut -Filter '*_draft.json' -Recurse -ErrorAction SilentlyContinue)
$completeDraftCount = 0
foreach ($draft in $draftFiles) {
    try {
        $draftJson = Get-Content -LiteralPath $draft.FullName -Raw | ConvertFrom-Json
        if ($draftJson.draftStatus -eq 'complete') { $completeDraftCount++ }
    } catch {}
}
$logText = (Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat.txt') -Raw) + "`n" + (Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat-myquestionnaire2d.txt') -Raw)
$fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
$chainLaunchCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_CHAIN_LAUNCH')).Count
$exportCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_EXPORT_COMPLETE')).Count
$chainReturnCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_CHAIN_RETURN')).Count

$status = 'pass'
if ($fatalLogCount -ne 0 -or $pull.ExitCode -ne 0 -or $records.Count -lt 2 -or $runIds.Count -lt 2 -or $null -eq $indexFile -or $completeDraftCount -lt 2 -or $chainLaunchCount -lt 2 -or $exportCompleteCount -lt 2) {
    $status = 'fail'
}
if ($finishBehavior -eq 'openNext' -and $chainReturnCount -lt 2) {
    $status = 'fail'
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.chain-validation.v1'
    status = $status
    serial = $Serial
    package = $package
    activity = $activity
    apk = $Apk
    sessionId = $SessionId
    participantName = $ParticipantName
    finishBehavior = $finishBehavior
    nextPackage = $NextPackage
    nextActivity = $NextActivity
    evidenceDir = $OutputRoot
    installExitCode = $installExitCode
    pullExitCode = $pull.ExitCode
    runs = @($runSummaries)
    finalExportCount = $records.Count
    uniqueRunIds = $runIds.Count
    sessionIndex = if ($indexFile) { $indexFile.FullName } else { $null }
    draftCount = $draftFiles.Count
    completeDraftCount = $completeDraftCount
    fatalLogCount = $fatalLogCount
    chainLaunchCount = $chainLaunchCount
    exportCompleteCount = $exportCompleteCount
    chainReturnCount = $chainReturnCount
    completedAt = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $OutputRoot 'quest-chain-validation-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest chain validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest chain validation failed. See $summaryPath"
}
