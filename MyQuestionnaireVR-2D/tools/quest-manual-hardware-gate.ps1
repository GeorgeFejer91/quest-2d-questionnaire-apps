param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$Apk = "",
    [string]$OutputRoot = "",
    [int]$WaitSeconds = 90,
    [string]$OperatorSignoffPath = "",
    [switch]$SkipInstall,
    [switch]$StopLegacyUnityApp,
    [switch]$RequirePass,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$package = "org.viscereality.questionnaires2d"
$activity = "org.viscereality.questionnaires2d.MainActivity"
$legacyUnityPackage = "org.viscereality.questionnaires"
$manualMarkerName = "manual-hardware-gate.txt"
$deviceFilesDir = "/sdcard/Android/data/$package/files"
$deviceManualMarker = "$deviceFilesDir/$manualMarkerName"

if ([string]::IsNullOrWhiteSpace($Apk)) {
    $Apk = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\manual-hardware-gate\manual-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'"))
}

function Resolve-Adb {
    param([string]$RequestedAdb)

    if (-not [string]::IsNullOrWhiteSpace($RequestedAdb)) {
        if (Test-Path -LiteralPath $RequestedAdb) {
            return $RequestedAdb
        }
        throw "ADB not found: $RequestedAdb"
    }

    $mqdhAdb = "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe"
    $unityAdb = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
    foreach ($candidate in @($mqdhAdb, $unityAdb)) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
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

function Read-OperatorSignoff {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Operator signoff file not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$instructionsPath = Join-Path $OutputRoot 'operator-instructions.txt'
$signoffTemplatePath = Join-Path $OutputRoot 'operator-signoff-template.json'

$instructions = @"
Manual hardware gate for the Quest 2D panel questionnaire
========================================================

Target package: $package
Activity: $activity

Perform only these boundary actions; do not complete the full questionnaire by hand.

1. With the controller ray, pull trigger on Target 1.
2. With hand tracking, pinch Target 2.
3. Point at the visible Back button and pull trigger.
4. Press the controller B/Y back action while the validation panel is visible.
5. Hover the controller ray over the panel and move the joystick for at least two seconds.
6. Tap the Keyboard field and confirm the system panel keyboard appears.
7. Pull trigger on Done.

After the run, fill operator-signoff-template.json and save it beside the evidence if you want the script to produce a full Level 6 pass.
"@
$instructions | Set-Content -LiteralPath $instructionsPath -Encoding UTF8

$signoffTemplate = [ordered]@{
    operator = ""
    controllerRayTrigger = $false
    handPinch = $false
    hardwareBackBY = $false
    joystickHoverScrollOrAdjust = $false
    panelKeyboardAppeared = $false
    notes = ""
}
$signoffTemplate | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $signoffTemplatePath -Encoding UTF8

if ($DryRun) {
    $summary = [ordered]@{
        schemaVersion = 'my-questionnaire-2d.manual-hardware-gate.v1'
        status = 'dry-run'
        package = $package
        activity = $activity
        apk = $Apk
        markerName = $manualMarkerName
        evidenceDir = $OutputRoot
        instructions = $instructionsPath
        operatorSignoffTemplate = $signoffTemplatePath
        completedAt = (Get-Date).ToString('o')
    }
    $summaryPath = Join-Path $OutputRoot 'manual-hardware-gate-summary.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-Host "Manual hardware gate dry run written to $OutputRoot"
    Write-Host "Summary: $summaryPath"
    return
}

$Adb = Resolve-Adb -RequestedAdb $Adb
if (-not (Test-Path -LiteralPath $Apk)) {
    throw "APK not found: $Apk"
}

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = & $Adb devices -l | Select-String -Pattern '\sdevice\s'
    if (@($devices).Count -eq 1) {
        $Serial = (@($devices)[0].ToString() -split '\s+')[0]
    }
}
if ([string]::IsNullOrWhiteSpace($Serial)) {
    throw "No unique Quest serial detected. Pass -Serial explicitly."
}

Invoke-AdbText -Arguments @("devices", "-l") -OutputPath (Join-Path $OutputRoot 'adb-devices.txt') | Out-Null
Invoke-AdbText -Arguments @("shell", "getprop", "ro.product.model") -OutputPath (Join-Path $OutputRoot 'device-model.txt') | Out-Null
Invoke-AdbText -Arguments @("shell", "getprop", "ro.build.version.release") -OutputPath (Join-Path $OutputRoot 'android-version.txt') | Out-Null
Invoke-AdbText -Arguments @("shell", "wm", "size") -OutputPath (Join-Path $OutputRoot 'wm-size.txt') | Out-Null
Invoke-AdbText -Arguments @("shell", "wm", "density") -OutputPath (Join-Path $OutputRoot 'wm-density.txt') | Out-Null

if (-not $SkipInstall) {
    $installExitCode = Invoke-AdbText -Arguments @("install", "-r", "-d", "-g", $Apk) -OutputPath (Join-Path $OutputRoot 'install.txt')
    if ($installExitCode -ne 0) {
        throw "APK install failed. See $OutputRoot\install.txt"
    }
}
else {
    $installExitCode = $null
}

if ($StopLegacyUnityApp) {
    Invoke-AdbText -Arguments @("shell", "am", "force-stop", $legacyUnityPackage) -OutputPath (Join-Path $OutputRoot 'force-stop-legacy-unity.txt') | Out-Null
}
Invoke-AdbText -Arguments @("shell", "am", "force-stop", $package) -OutputPath (Join-Path $OutputRoot 'force-stop-before.txt') | Out-Null
Invoke-AdbText -Arguments @("logcat", "-c") -OutputPath (Join-Path $OutputRoot 'logcat-clear.txt') | Out-Null

$localMarkerPath = Join-Path $OutputRoot $manualMarkerName
"manual-hardware-gate" | Set-Content -LiteralPath $localMarkerPath -Encoding UTF8
Invoke-AdbText -Arguments @("shell", "mkdir", "-p", $deviceFilesDir) -OutputPath (Join-Path $OutputRoot 'mkdir-device-files.txt') | Out-Null
$pushStdout = Join-Path $OutputRoot 'push-manual-marker-stdout.txt'
$pushStderr = Join-Path $OutputRoot 'push-manual-marker-stderr.txt'
$pushProcess = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'push', $localMarkerPath, $deviceManualMarker) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $pushStdout -RedirectStandardError $pushStderr
$markerPushExitCode = $pushProcess.ExitCode
if ($markerPushExitCode -ne 0) {
    throw "Manual hardware marker push failed. See $pushStdout and $pushStderr"
}

$launchExitCode = Invoke-AdbText -Arguments @("shell", "am", "start", "-n", "$package/$activity") -OutputPath (Join-Path $OutputRoot 'launch.txt')

Write-Host ""
Write-Host "Manual hardware gate launched. Follow instructions in:"
Write-Host $instructionsPath
Write-Host ""
Write-Host "Waiting $WaitSeconds seconds for operator input..."
Start-Sleep -Seconds $WaitSeconds

$screenshotBytes = Save-AdbScreenshot -Path (Join-Path $OutputRoot 'screenshot-after-manual-window.png')
Invoke-AdbText -Arguments @("shell", "pidof", $package) -OutputPath (Join-Path $OutputRoot 'pidof-after.txt') | Out-Null
Invoke-AdbText -Arguments @("shell", "dumpsys", "window") -OutputPath (Join-Path $OutputRoot 'foreground-after.txt') | Out-Null
Invoke-AdbText -Arguments @("shell", "dumpsys", "activity", "activities") -OutputPath (Join-Path $OutputRoot 'activity-activities.txt') | Out-Null
Invoke-AdbText -Arguments @("logcat", "-d", "-v", "threadtime") -OutputPath (Join-Path $OutputRoot 'logcat.txt') | Out-Null
Invoke-AdbText -Arguments @("logcat", "-d", "-v", "threadtime", "MyQuestionnaire2D:I", "AndroidRuntime:E", "*:S") -OutputPath (Join-Path $OutputRoot 'logcat-myquestionnaire2d.txt') | Out-Null

$taggedLogPath = Join-Path $OutputRoot 'logcat-myquestionnaire2d.txt'
$logText = if (Test-Path -LiteralPath $taggedLogPath) { Get-Content -LiteralPath $taggedLogPath -Raw } else { "" }
$fullLogPath = Join-Path $OutputRoot 'logcat.txt'
if (Test-Path -LiteralPath $fullLogPath) {
    $logText += "`n" + (Get-Content -LiteralPath $fullLogPath -Raw)
}
$foregroundText = Get-Content -LiteralPath (Join-Path $OutputRoot 'foreground-after.txt') -Raw
$activityText = Get-Content -LiteralPath (Join-Path $OutputRoot 'activity-activities.txt') -Raw

$inputEvents = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_INPUT action=([A-Za-z]+) source=([^ ]+) screen=([^ \r\n]+)'))
$touchEvents = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_INPUT_TOUCH'))
$keyEvents = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_INPUT_KEY'))
$joystickEvents = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_INPUT_JOYSTICK'))
$manualGateStarted = [bool]($logText -match 'MYQUESTIONNAIRE_MANUAL_GATE_START')
$manualGateVisualStageLogged = [bool]($logText -match 'MYQUESTIONNAIRE_VISUAL_STAGE stage=manual-hardware-gate')
$manualGateReadyLogged = [bool]($logText -match 'MYQUESTIONNAIRE_MANUAL_GATE_READY')
$controllerTargetLogged = [bool]($logText -match 'MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=controller-target')
$handTargetLogged = [bool]($logText -match 'MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=hand-target')
$keyboardFocusLogged = [bool]($logText -match 'MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=keyboard-focus')
$sliderAdjustLogged = [bool]($logText -match 'MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=slider-adjust')
$activationLogged = [bool]($logText -match 'MYQUESTIONNAIRE_INPUT action=Activate')
$visibleBackLogged = [bool]($logText -match 'MYQUESTIONNAIRE_INPUT action=Back source=.*visible-back')
$hardwareBackLogged =
    [bool]($logText -match 'MYQUESTIONNAIRE_INPUT_KEY action=down .*(keyName=(KEYCODE_BACK|KEYCODE_BUTTON_B|KEYCODE_BUTTON_Y)|keyCode=(4|97|100))') -or
    [bool]($logText -match 'MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=hardware-back')
$joystickLogged = $joystickEvents.Count -gt 0
$fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
$foregroundHasPackage = $foregroundText.Contains($package) -or $activityText.Contains($package)
$targetActivityResumed = $activityText.Contains("ResumedActivity") -and $activityText.Contains($package)
$operatorSignoff = Read-OperatorSignoff -Path $OperatorSignoffPath

$operatorPass = $false
if ($operatorSignoff -ne $null) {
    $operatorPass =
        [bool]$operatorSignoff.controllerRayTrigger -and
        [bool]$operatorSignoff.handPinch -and
        [bool]$operatorSignoff.hardwareBackBY -and
        [bool]$operatorSignoff.joystickHoverScrollOrAdjust
}

$logPass =
    $manualGateStarted -and
    $manualGateVisualStageLogged -and
    $manualGateReadyLogged -and
    $controllerTargetLogged -and
    $handTargetLogged -and
    $keyboardFocusLogged -and
    $visibleBackLogged -and
    $hardwareBackLogged -and
    $joystickLogged -and
    $foregroundHasPackage -and
    $fatalLogCount -eq 0
$status = if ($logPass -and $operatorPass) { 'pass' } elseif ($logPass) { 'pending-operator-signoff' } else { 'needs-manual-evidence' }

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.manual-hardware-gate.v1'
    status = $status
    serial = $Serial
    package = $package
    activity = $activity
    apk = $Apk
    markerName = $manualMarkerName
    deviceManualMarker = $deviceManualMarker
    evidenceDir = $OutputRoot
    instructions = $instructionsPath
    operatorSignoffTemplate = $signoffTemplatePath
    operatorSignoff = if ([string]::IsNullOrWhiteSpace($OperatorSignoffPath)) { $null } else { $OperatorSignoffPath }
    checks = [ordered]@{
        installExitCode = $installExitCode
        markerPushExitCode = $markerPushExitCode
        launchExitCode = $launchExitCode
        foregroundHasPackage = $foregroundHasPackage
        targetActivityResumed = $targetActivityResumed
        pidAlive = (Get-Content -LiteralPath (Join-Path $OutputRoot 'pidof-after.txt') -Raw).Trim().Length -gt 0
        fatalLogCount = $fatalLogCount
        screenshotBytes = $screenshotBytes
        inputEventCount = $inputEvents.Count
        touchEventCount = $touchEvents.Count
        keyEventCount = $keyEvents.Count
        joystickEventCount = $joystickEvents.Count
        manualGateStarted = $manualGateStarted
        manualGateVisualStageLogged = $manualGateVisualStageLogged
        manualGateReadyLogged = $manualGateReadyLogged
        controllerTargetLogged = $controllerTargetLogged
        handTargetLogged = $handTargetLogged
        keyboardFocusLogged = $keyboardFocusLogged
        sliderAdjustLogged = $sliderAdjustLogged
        activationLogged = $activationLogged
        visibleBackLogged = $visibleBackLogged
        hardwareBackLogged = $hardwareBackLogged
        joystickLogged = $joystickLogged
        operatorSignoffPass = $operatorPass
    }
    completedAt = (Get-Date).ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'manual-hardware-gate-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Manual hardware gate evidence written to $OutputRoot"
Write-Host "Summary: $summaryPath"

if ($RequirePass -and $status -ne 'pass') {
    throw "Manual hardware gate did not pass: $status. See $summaryPath"
}
