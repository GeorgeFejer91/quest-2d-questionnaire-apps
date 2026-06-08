param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$Adb = "",
    [string]$ExpectedSerial = "",
    [string]$ConnectAddress = "",
    [int]$WaitSeconds = 0,
    [int]$PollSeconds = 5,
    [switch]$RestartServer,
    [switch]$RequireOnline
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "quest-adb-readiness-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath "artifacts\quest-adb-readiness\$RunId"
}

function Resolve-Adb {
    param([string]$RequestedAdb)
    if (-not [string]::IsNullOrWhiteSpace($RequestedAdb)) {
        if (Test-Path -LiteralPath $RequestedAdb) { return (Resolve-Path -LiteralPath $RequestedAdb).Path }
        throw "ADB not found: $RequestedAdb"
    }

    $mqdhAdb = "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe"
    $unityAdb = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
    foreach ($candidate in @($mqdhAdb, $unityAdb)) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "ADB not found. Pass -Adb explicitly."
}

function Invoke-AdbCapture {
    param(
        [string[]]$Arguments,
        [string]$OutputPath
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:AdbPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return [pscustomobject]@{
        exitCode = $exitCode
        output = @($output)
        outputPath = $OutputPath
    }
}

function Invoke-SerialAdbCapture {
    param(
        [string]$Serial,
        [string[]]$Arguments,
        [string]$OutputPath
    )

    return Invoke-AdbCapture -Arguments (@('-s', $Serial) + $Arguments) -OutputPath $OutputPath
}

function Parse-AdbDevices {
    param([string[]]$Lines)

    $records = @()
    foreach ($line in $Lines) {
        $text = $line.ToString()
        if ($text -match '^\s*$' -or $text -match '^List of devices attached') {
            continue
        }
        if ($text -match '^(\S+)\s+(device|unauthorized|offline|recovery|sideload|no permissions)(?:\s+(.*))?$') {
            $records += [ordered]@{
                serial = $Matches[1]
                state = $Matches[2]
                detail = if ($Matches.Count -gt 3) { $Matches[3] } else { "" }
                raw = $text
            }
        }
    }
    return $records
}

function Get-QuestUsbInventory {
    $records = @()
    try {
        $devices = Get-PnpDevice -PresentOnly -ErrorAction Stop |
            Where-Object {
                $_.FriendlyName -match 'Quest|Oculus|Meta|Android|ADB|XRSP|MTP' -or
                $_.InstanceId -match 'VID_2833|VID_18D1'
            } |
            Select-Object Status, Class, FriendlyName, InstanceId
        foreach ($device in $devices) {
            $records += [ordered]@{
                status = [string]$device.Status
                class = [string]$device.Class
                friendlyName = [string]$device.FriendlyName
                instanceId = [string]$device.InstanceId
            }
        }
    }
    catch {
        $records += [ordered]@{
            status = 'unavailable'
            class = ''
            friendlyName = 'Get-PnpDevice failed'
            instanceId = $_.Exception.Message
        }
    }
    return $records
}

function Get-Recommendations {
    param(
        [object[]]$Devices,
        [object[]]$UsbInventory,
        [string]$Expected
    )

    $recommendations = @()
    $online = @($Devices | Where-Object { $_.state -eq 'device' })
    $unauthorized = @($Devices | Where-Object { $_.state -eq 'unauthorized' -and $_.serial -notmatch '^emulator-' })
    $offline = @($Devices | Where-Object { $_.state -eq 'offline' -and $_.serial -notmatch '^emulator-' })
    $offlineEmulators = @($Devices | Where-Object { $_.state -eq 'offline' -and $_.serial -match '^emulator-' })
    $physicalQuestUsb = @($UsbInventory | Where-Object {
        $_.instanceId -match 'VID_2833|VID_18D1' -or
        ($_.friendlyName -match 'Quest|Android|ADB|MTP|XRSP' -and $_.friendlyName -notmatch 'Virtual')
    })

    if ($online.Count -eq 0 -and $unauthorized.Count -gt 0) {
        $recommendations += 'Put on the headset and accept the Allow USB debugging prompt. If the prompt is missing, revoke USB debugging authorizations in Developer settings and reconnect.'
    }
    if ($online.Count -eq 0 -and $offline.Count -gt 0) {
        $recommendations += 'ADB sees an offline transport. Reconnect the USB cable, keep the headset awake/unlocked, and rerun with -RestartServer.'
    }
    if ($online.Count -eq 0 -and $offlineEmulators.Count -gt 0) {
        $recommendations += 'ADB sees an offline Android emulator only; that does not prove the Quest headset is connected.'
    }
    if ($online.Count -eq 0 -and $physicalQuestUsb.Count -eq 0) {
        $recommendations += 'Windows does not see a physical Quest/Android USB device. Try a data-capable USB cable, another USB port, and confirm Developer Mode is enabled on the headset.'
    }
    if ($online.Count -gt 1 -and [string]::IsNullOrWhiteSpace($Expected)) {
        $recommendations += 'Multiple online Android devices are present. Pass -ExpectedSerial or -Serial to downstream validation scripts.'
    }
    if (-not [string]::IsNullOrWhiteSpace($Expected) -and @($online | Where-Object { $_.serial -eq $Expected }).Count -eq 0) {
        $recommendations += "Expected serial $Expected is not online. Check the cable/authorization or pass the detected online serial."
    }
    if ($online.Count -eq 0) {
        $recommendations += 'For wireless ADB, enable wireless/debug-over-network in headset developer tools, then rerun with -ConnectAddress <ip:port>.'
    }
    if ($recommendations.Count -eq 0) {
        $recommendations += 'Quest ADB transport is online for install and file validation.'
    }
    return $recommendations
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
    foreach ($package in @(
        'org.questquestionnaire.stimulusdemo',
        'org.questquestionnaire.questionnaires2d',
        'org.questquestionnaire.temporaltracer2d',
        'org.questquestionnaire.chainlink',
        'com.oculus.vrshell',
        'com.oculus.shellenv'
    )) {
        if ($focusText -match [regex]::Escape($package)) {
            return $package
        }
    }
    return ''
}

function Get-ProductPathState {
    param(
        [object]$Power,
        [object]$Window,
        [string]$PowerPath,
        [string]$WindowPath,
        [string]$FocusPath
    )

    $powerText = (@($Power.output) | ForEach-Object { $_.ToString() }) -join "`n"
    $windowText = (@($Window.output) | ForEach-Object { $_.ToString() }) -join "`n"
    $wakefulness = if ($powerText -match 'mWakefulness=([^\r\n]+)') { $Matches[1].Trim() } else { '' }
    $interactive = if ($powerText -match 'mInteractive=([^\r\n]+)') { $Matches[1].Trim() } else { '' }
    $displayState = if ($powerText -match 'Display Power: state=([^\r\n]+)') { $Matches[1].Trim() } else { '' }
    $focusLines = Get-FocusLines -Text $windowText
    $focusText = $focusLines -join "`n"
    $windowSleeping = [bool]($windowText -match 'isSleeping=true')
    $displayOff = [bool]($displayState -match '^OFF\b' -or $interactive -eq 'false')
    $headsetAsleep = [bool]($wakefulness -match 'Asleep|Dozing|Dreaming' -or $windowSleeping)
    $launchCheckDialogFocused = [bool]($focusText -match 'LaunchCheckControllerRequiredDialogActivity' -or $windowText -match 'LaunchCheckControllerRequiredDialogActivity')
    $blockedReasons = New-Object 'System.Collections.Generic.List[string]'
    if ($Power.exitCode -ne 0 -or $Window.exitCode -ne 0) {
        $blockedReasons.Add('adb-power-or-window-probe-failed') | Out-Null
    }
    if ($headsetAsleep -or $displayOff) {
        $blockedReasons.Add('headset-asleep-or-display-off') | Out-Null
    }
    if ($launchCheckDialogFocused) {
        $blockedReasons.Add('horizon-launch-check-controller-dialog-focused') | Out-Null
    }
    $ready = $blockedReasons.Count -eq 0

    return [ordered]@{
        probed = $true
        status = if ($ready) { 'ready' } else { 'blocked' }
        ready = $ready
        blockedReasons = @($blockedReasons)
        wakefulness = $wakefulness
        interactive = $interactive
        displayState = $displayState
        headsetAsleep = $headsetAsleep
        displayOff = $displayOff
        windowSleeping = $windowSleeping
        launchCheckDialogFocused = $launchCheckDialogFocused
        focusedPackage = Get-FocusPackage -Text $windowText
        focusLines = $focusLines
        powerExitCode = $Power.exitCode
        windowExitCode = $Window.exitCode
        powerPath = $PowerPath
        windowPath = $WindowPath
        focusPath = $FocusPath
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$script:AdbPath = Resolve-Adb $Adb

if ($RestartServer) {
    Invoke-AdbCapture -Arguments @('kill-server') -OutputPath (Join-Path $OutputRoot 'adb-kill-server.txt') | Out-Null
    Start-Sleep -Seconds 1
    Invoke-AdbCapture -Arguments @('start-server') -OutputPath (Join-Path $OutputRoot 'adb-start-server.txt') | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($ConnectAddress)) {
    Invoke-AdbCapture -Arguments @('connect', $ConnectAddress) -OutputPath (Join-Path $OutputRoot 'adb-connect.txt') | Out-Null
}

$polls = @()
$deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))
$attempt = 0
do {
    $attempt++
    $path = Join-Path $OutputRoot ("adb-devices-{0:00}.txt" -f $attempt)
    $capture = Invoke-AdbCapture -Arguments @('devices', '-l') -OutputPath $path
    $devices = @(Parse-AdbDevices -Lines $capture.output)
    $online = @($devices | Where-Object { $_.state -eq 'device' })
    $targetOnline = if ([string]::IsNullOrWhiteSpace($ExpectedSerial)) {
        $online.Count -gt 0
    } else {
        @($online | Where-Object { $_.serial -eq $ExpectedSerial }).Count -gt 0
    }
    $polls += [ordered]@{
        attempt = $attempt
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        outputPath = $path
        devices = $devices
        onlineCount = $online.Count
        targetOnline = $targetOnline
    }
    if ($targetOnline) { break }
    if ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
    }
} while ((Get-Date) -lt $deadline)

$latestDevices = @($polls[-1].devices)
$onlineDevices = @($latestDevices | Where-Object { $_.state -eq 'device' })
$unauthorizedDevices = @($latestDevices | Where-Object { $_.state -eq 'unauthorized' -and $_.serial -notmatch '^emulator-' })
$offlineDevices = @($latestDevices | Where-Object { $_.state -eq 'offline' -and $_.serial -notmatch '^emulator-' })
$offlineEmulators = @($latestDevices | Where-Object { $_.state -eq 'offline' -and $_.serial -match '^emulator-' })
$targetDevice = $null
if ([string]::IsNullOrWhiteSpace($ExpectedSerial)) {
    $targetDevice = $onlineDevices | Select-Object -First 1
} else {
    $targetDevice = $onlineDevices | Where-Object { $_.serial -eq $ExpectedSerial } | Select-Object -First 1
}

$usbInventory = @(Get-QuestUsbInventory)
$usbInventoryPath = Join-Path $OutputRoot 'windows-usb-inventory.json'
$usbInventory | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $usbInventoryPath -Encoding UTF8

$deviceProps = [ordered]@{}
$productPath = [ordered]@{
    probed = $false
    status = 'not-probed'
    ready = $false
    blockedReasons = @()
}
if ($null -ne $targetDevice) {
    $serial = [string]$targetDevice.serial
    $probeDir = Join-Path $OutputRoot 'online-device-probes'
    New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
    $deviceProps.serial = $serial
    $deviceProps.model = (Invoke-SerialAdbCapture -Serial $serial -Arguments @('shell', 'getprop', 'ro.product.model') -OutputPath (Join-Path $probeDir 'model.txt')).output -join "`n"
    $deviceProps.manufacturer = (Invoke-SerialAdbCapture -Serial $serial -Arguments @('shell', 'getprop', 'ro.product.manufacturer') -OutputPath (Join-Path $probeDir 'manufacturer.txt')).output -join "`n"
    $deviceProps.androidRelease = (Invoke-SerialAdbCapture -Serial $serial -Arguments @('shell', 'getprop', 'ro.build.version.release') -OutputPath (Join-Path $probeDir 'android-release.txt')).output -join "`n"
    $deviceProps.wmSize = (Invoke-SerialAdbCapture -Serial $serial -Arguments @('shell', 'wm', 'size') -OutputPath (Join-Path $probeDir 'wm-size.txt')).output -join "`n"
    $deviceProps.wmDensity = (Invoke-SerialAdbCapture -Serial $serial -Arguments @('shell', 'wm', 'density') -OutputPath (Join-Path $probeDir 'wm-density.txt')).output -join "`n"
    $powerPath = Join-Path $probeDir 'dumpsys-power.txt'
    $windowPath = Join-Path $probeDir 'dumpsys-window.txt'
    $focusPath = Join-Path $probeDir 'focused-window.txt'
    $power = Invoke-SerialAdbCapture -Serial $serial -Arguments @('shell', 'dumpsys', 'power') -OutputPath $powerPath
    $window = Invoke-SerialAdbCapture -Serial $serial -Arguments @('shell', 'dumpsys', 'window') -OutputPath $windowPath
    (Get-FocusLines -Text ((@($window.output) | ForEach-Object { $_.ToString() }) -join "`n")) |
        Set-Content -LiteralPath $focusPath -Encoding UTF8
    $productPath = Get-ProductPathState -Power $power -Window $window -PowerPath $powerPath -WindowPath $windowPath -FocusPath $focusPath
}

$readiness = if ($null -ne $targetDevice) {
    'online'
} elseif ($unauthorizedDevices.Count -gt 0) {
    'unauthorized'
} elseif ($offlineDevices.Count -gt 0) {
    'offline'
} elseif ($offlineEmulators.Count -gt 0 -and $latestDevices.Count -eq $offlineEmulators.Count) {
    'not-detected'
} elseif ($latestDevices.Count -gt 0) {
    'adb-visible-not-online'
} else {
    'not-detected'
}

$recommendations = @(Get-Recommendations -Devices $latestDevices -UsbInventory $usbInventory -Expected $ExpectedSerial)
if ($readiness -eq 'online') {
    if ($productPath.status -eq 'ready') {
        $recommendations += 'Product-path launch appears ready: headset power/window state is awake and no Horizon launch-check dialog is focused.'
    } elseif ($productPath.status -eq 'blocked') {
        $reasonText = (@($productPath.blockedReasons) -join ', ')
        $recommendations += "ADB is online, but product-path launch is blocked: $reasonText. Put on/wake the headset and clear system launch prompts before direct handoff, replay/export, or foreground validation."
    }
}
$status = if ($readiness -eq 'online') { 'pass' } else { if ($RequireOnline) { 'fail' } else { 'warn' } }

$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.quest-adb-readiness.v1'
    status = $status
    readiness = $readiness
    adb = $script:AdbPath
    expectedSerial = $ExpectedSerial
    connectAddress = $ConnectAddress
    waitSeconds = $WaitSeconds
    outputRoot = $OutputRoot
    latestDevices = $latestDevices
    onlineCount = $onlineDevices.Count
    unauthorizedCount = $unauthorizedDevices.Count
    offlineCount = $offlineDevices.Count
    offlineEmulatorCount = $offlineEmulators.Count
    targetSerial = if ($targetDevice) { $targetDevice.serial } else { "" }
    deviceProps = $deviceProps
    productPathStatus = $productPath.status
    productPathReady = [bool]$productPath.ready
    productPath = $productPath
    usbInventory = $usbInventory
    usbInventoryPath = $usbInventoryPath
    recommendations = $recommendations
    polls = $polls
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'quest-adb-readiness-summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]@{
    Status = $status
    Readiness = $readiness
    Online = $onlineDevices.Count
    Unauthorized = $unauthorizedDevices.Count
    Offline = $offlineDevices.Count
    TargetSerial = if ($targetDevice) { $targetDevice.serial } else { "" }
    ProductPathStatus = $productPath.status
    Summary = $summaryPath
}

if ($RequireOnline -and $status -ne 'pass') {
    throw "Quest ADB is not ready: $readiness. See $summaryPath"
}
