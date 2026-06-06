param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ConfigPath = "",
    [string]$OutputRoot = "",
    [string]$Apk = "",
    [int]$WaitSeconds = 24,
    [string]$ParticipantName = "BrokerChainParticipant",
    [string]$SessionId = "",
    [switch]$SkipBuild,
    [switch]$StopLegacyUnityApp
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$package = "org.viscereality.questionnaires2d"
$brokerActivity = "org.viscereality.questionnaires2d.QuestChainBrokerActivity"
$brokerAction = "org.viscereality.questionnaires2d.BROKER"
$legacyUnityPackage = "org.viscereality.questionnaires"
$deviceFiles = "/sdcard/Android/data/$package/files"
$deviceExports = "$deviceFiles/QuestionnaireExports"
$deviceBroker = "$deviceFiles/ChainBroker"

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = "broker-chain-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-broker-chain-validation\" + $SessionId)
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
Invoke-AdbText -Arguments @('shell', "rm -rf '$deviceExports' '$deviceBroker' && mkdir -p '$deviceFiles'") -OutputPath (Join-Path $OutputRoot 'clear-state.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$chainId = "$SessionId-chain"
$planPath = Join-Path $OutputRoot 'broker-chain-plan.json'
$plan = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.chain-plan.v1'
    chainId = $chainId
    steps = @(
        [ordered]@{
            id = 'questionnaire-validation'
            type = 'questionnaire'
            package = $package
            activity = '.MainActivity'
            extras = [ordered]@{
                'mq.sessionId' = $SessionId
                'mq.experimentId' = 'broker-chain-validation'
                'mq.scenarioId' = 'broker-validation'
                'mq.trialId' = 'trial-01'
                'mq.participantId' = $ParticipantName
                'mq.participantName' = $ParticipantName
                'mq.language' = 'English'
                'mq.autoCloseDelayMs' = 0
            }
        }
    )
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8

$markerPath = Join-Path $OutputRoot 'command-replay-english.json'
@{
    ParticipantName = $ParticipantName
    ExpectedAge = 33
    GenderFocusId = 'gender.0'
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerPath -Encoding UTF8

$pushMarker = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $markerPath, "$deviceFiles/command-replay-english.json") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'push-marker-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'push-marker-stderr.txt')
if ($pushMarker.ExitCode -ne 0) {
    throw "Could not push command replay marker."
}

$planJsonExtra = Get-Content -LiteralPath $planPath -Raw
$planBase64Extra = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($planJsonExtra))
$launchExitCode = Invoke-AdbText -Arguments @(
    'shell', 'am', 'start',
    '-a', $brokerAction,
    '-n', "$package/$brokerActivity",
    '--es', 'mq.brokerCommand', 'startPlan',
    '--es', 'mq.chainId', $chainId,
    '--es', 'mq.chainPlanBase64', $planBase64Extra
) -OutputPath (Join-Path $OutputRoot 'launch-broker.txt')

Start-Sleep -Seconds $WaitSeconds
Invoke-AdbText -Arguments @('shell', 'dumpsys', 'window') -OutputPath (Join-Path $OutputRoot 'foreground-after.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath (Join-Path $OutputRoot 'logcat.txt') | Out-Null
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'threadtime', 'MyQuestionnaire2D:I', 'AndroidRuntime:E', '*:S') -OutputPath (Join-Path $OutputRoot 'logcat-myquestionnaire2d.txt') | Out-Null

$pullRoot = Join-Path $OutputRoot 'device-files'
if (Test-Path -LiteralPath $pullRoot) {
    Remove-Item -LiteralPath $pullRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $pullRoot | Out-Null
$pull = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'pull', $deviceFiles, $pullRoot) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputRoot 'pull-files-stdout.txt') -RedirectStandardError (Join-Path $OutputRoot 'pull-files-stderr.txt')

$records = @(Get-FinalExportRecords -ExportDir $pullRoot)
$record = $records | Select-Object -First 1
$stateFile = Get-ChildItem -LiteralPath $pullRoot -Filter 'chain-state.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$state = $null
if ($stateFile) {
    $state = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
}
$logText = (Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat.txt') -Raw) + "`n" + (Get-Content -LiteralPath (Join-Path $OutputRoot 'logcat-myquestionnaire2d.txt') -Raw)
$fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
$brokerLaunchCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_BROKER status=questionnaire:questionnaire-validation')).Count
$brokerCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_BROKER status=plan-complete')).Count
$exportCompleteCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_EXPORT_COMPLETE')).Count

$status = 'pass'
if ($fatalLogCount -ne 0 -or $launchExitCode -ne 0 -or $pull.ExitCode -ne 0 -or $records.Count -lt 1 -or $null -eq $state -or $state.status -ne 'complete' -or $brokerLaunchCount -lt 1 -or $brokerCompleteCount -lt 1 -or $exportCompleteCount -lt 1) {
    $status = 'fail'
}
if ($record -and ($record.Record.chainId -ne $chainId -or $record.Record.chainStepId -ne 'questionnaire-validation')) {
    $status = 'fail'
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.broker-chain-validation.v1'
    status = $status
    serial = $Serial
    package = $package
    brokerActivity = $brokerActivity
    apk = $Apk
    sessionId = $SessionId
    chainId = $chainId
    participantName = $ParticipantName
    evidenceDir = $OutputRoot
    installExitCode = $installExitCode
    launchExitCode = $launchExitCode
    pullExitCode = $pull.ExitCode
    finalExportCount = $records.Count
    stateStatus = if ($state) { $state.status } else { $null }
    stateFile = if ($stateFile) { $stateFile.FullName } else { $null }
    fatalLogCount = $fatalLogCount
    brokerLaunchCount = $brokerLaunchCount
    brokerCompleteCount = $brokerCompleteCount
    exportCompleteCount = $exportCompleteCount
    completedAt = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $OutputRoot 'quest-broker-chain-validation-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest broker chain validation evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest broker chain validation failed. See $summaryPath"
}
