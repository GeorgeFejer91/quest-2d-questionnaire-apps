param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$Serial = "",
    [string]$Apk = "",
    [string]$AdbPath = "",
    [switch]$SkipBuild,
    [int]$Valence = 5,
    [int]$Arousal = 4
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$package = 'org.questquestionnaire.sam2d'
$activity = 'org.questquestionnaire.sam2d.MainActivity'
$receiver = 'org.questquestionnaire.sam2d.SamSelfValidationReceiver'
$exports = "/sdcard/Android/data/$package/files/SamQuestionnaireExports"

if ([string]::IsNullOrWhiteSpace($AdbPath)) {
    $mqdhAdb = "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe"
    if (Test-Path -LiteralPath $mqdhAdb) {
        $AdbPath = $mqdhAdb
    }
    else {
        $AdbPath = "adb"
    }
}

if (-not $SkipBuild) {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\build-apk.ps1')
}

if ([string]::IsNullOrWhiteSpace($Apk)) {
    $Apk = Join-Path $ProjectPath 'Builds\SAMQuestionnaireVR-2D.apk'
}
if (-not (Test-Path -LiteralPath $Apk)) {
    throw "APK not found: $Apk"
}
if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = & $AdbPath devices | Select-String -Pattern 'device$'
    if (@($devices).Count -ne 1) {
        throw "No unique Quest serial detected. Pass -Serial explicitly."
    }
    $Serial = ((@($devices)[0].ToString() -split '\s+')[0])
}

$runId = "sam-quest-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
$outRoot = Join-Path $ProjectPath "artifacts\quest-sam-validation\$runId"
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

function Invoke-AdbText {
    param(
        [string[]]$Arguments,
        [string]$OutputName
    )
    $out = Join-Path $outRoot "$OutputName.txt"
    $err = Join-Path $outRoot "$OutputName.err.txt"
    $process = Start-Process -FilePath $AdbPath -ArgumentList (@('-s', $Serial) + $Arguments) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $out; Stderr = $err }
}

function Get-PngEvidence {
    param([System.IO.FileInfo]$File)

    $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $validSignature = (
        $bytes.Length -ge 24 -and
        $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47 -and
        $bytes[4] -eq 0x0D -and $bytes[5] -eq 0x0A -and $bytes[6] -eq 0x1A -and $bytes[7] -eq 0x0A
    )
    $width = 0
    $height = 0
    if ($validSignature) {
        $widthBytes = [byte[]]$bytes[16..19]
        $heightBytes = [byte[]]$bytes[20..23]
        [array]::Reverse($widthBytes)
        [array]::Reverse($heightBytes)
        $width = [BitConverter]::ToInt32($widthBytes, 0)
        $height = [BitConverter]::ToInt32($heightBytes, 0)
    }
    $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{
        path = $File.FullName
        name = $File.Name
        bytes = $File.Length
        validPng = $validSignature
        width = $width
        height = $height
        sha256 = $hash
        passesArtifactGate = ($validSignature -and $File.Length -ge 5000 -and $width -ge 640 -and $height -ge 480)
    }
}

Invoke-AdbText -Arguments @('install', '-r', '-d', '-g', $Apk) -OutputName 'install' | Out-Null
Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $package) -OutputName 'force-stop' | Out-Null
Invoke-AdbText -Arguments @('shell', "rm -rf '$exports'") -OutputName 'clear-exports' | Out-Null
Invoke-AdbText -Arguments @('logcat', '-c') -OutputName 'logcat-clear' | Out-Null

$launchArgs = @(
    'shell', 'am', 'broadcast',
    '-n', "$package/$receiver",
    '-a', 'org.questquestionnaire.sam2d.SELF_VALIDATE',
    '--ez', 'mq.autoSam', 'true',
    '--ei', 'mq.autoSamValence', ([string]$Valence),
    '--ei', 'mq.autoSamArousal', ([string]$Arousal),
    '--ez', 'mq.capturePanel', 'true',
    '--es', 'mq.capturePanelStage', 'all',
    '--es', 'mq.sessionId', $runId,
    '--es', 'mq.participantId', 'AUTO_SAM_001',
    '--es', 'mq.participantName', 'AutoSAM'
)
Invoke-AdbText -Arguments $launchArgs -OutputName 'self-validate-sam' | Out-Null
Start-Sleep -Seconds 6
Invoke-AdbText -Arguments @('logcat', '-d', '-v', 'time', 'SAM2D:I', '*:S') -OutputName 'logcat-sam' | Out-Null

$pullRoot = Join-Path $outRoot 'exports'
New-Item -ItemType Directory -Force -Path $pullRoot | Out-Null
Invoke-AdbText -Arguments @('pull', $exports, $pullRoot) -OutputName 'pull-exports' | Out-Null

$jsonFiles = @(Get-ChildItem -LiteralPath $pullRoot -Recurse -Filter '*.json' -File | Where-Object { $_.Name -ne 'session-index.jsonl' })
$csvFiles = @(Get-ChildItem -LiteralPath $pullRoot -Recurse -Filter '*.csv' -File)
$pngFiles = @(Get-ChildItem -LiteralPath $pullRoot -Recurse -Filter '*.png' -File)
$pngEvidence = @($pngFiles | ForEach-Object { Get-PngEvidence -File $_ })
$logText = Get-Content -LiteralPath (Join-Path $outRoot 'logcat-sam.txt') -Raw -ErrorAction SilentlyContinue
$status = 'pass'
$failures = New-Object System.Collections.Generic.List[string]
if ($jsonFiles.Count -lt 1) { $failures.Add('missing-json-export') | Out-Null }
if ($csvFiles.Count -lt 1) { $failures.Add('missing-csv-export') | Out-Null }
if ($logText -notmatch 'SAM_COMMAND_REPLAY_EXPORT_MATCH') { $failures.Add('missing-command-replay-pass-marker') | Out-Null }
if ($logText -notmatch 'SAM_EXPORT_COMPLETE') { $failures.Add('missing-export-complete-marker') | Out-Null }
if ($logText -notmatch 'SAM_SELF_VALIDATE_PASS') { $failures.Add('missing-self-validation-pass-marker') | Out-Null }
foreach ($stage in @('sam-selected', 'affective-slider-selected', 'saved')) {
    $stagePng = @($pngEvidence | Where-Object { $_.name -match "_screen_$([regex]::Escape($stage))\.png$" })
    if ($stagePng.Count -lt 1) {
        $failures.Add("missing-panel-capture-$stage") | Out-Null
    }
    elseif (-not [bool]$stagePng[0].passesArtifactGate) {
        $failures.Add("invalid-panel-capture-$stage") | Out-Null
    }
    if ($logText -notmatch "SAM_PANEL_CAPTURE_PASS stage=$([regex]::Escape($stage))") {
        $failures.Add("missing-panel-capture-log-$stage") | Out-Null
    }
}

if ($jsonFiles.Count -gt 0) {
    $json = Get-Content -LiteralPath $jsonFiles[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$json.sam.valenceRaw1To5 -ne $Valence) { $failures.Add("json-valence-mismatch") | Out-Null }
    if ([int]$json.sam.arousalRaw1To5 -ne $Arousal) { $failures.Add("json-arousal-mismatch") | Out-Null }
    if ([string]$json.ratingTarget -ne 'previous_session') { $failures.Add("json-rating-target-mismatch") | Out-Null }
    if ($null -eq $json.affectiveSlider) { $failures.Add("missing-affective-slider-json") | Out-Null }
}

if ($failures.Count -gt 0) {
    $status = 'fail'
}

$summary = [ordered]@{
    schemaVersion = 'quest-questionnaire.sam2d.quest-validation.v1'
    runId = $runId
    serial = $Serial
    apk = $Apk
    package = $package
    validationMode = 'broadcast-self-renderer'
    exportPath = $exports
    outputRoot = $outRoot
    jsonExportCount = $jsonFiles.Count
    csvExportCount = $csvFiles.Count
    panelCapturePngCount = $pngFiles.Count
    panelCapturePngs = @($pngEvidence)
    expectedValence = $Valence
    expectedArousal = $Arousal
    failures = @($failures.ToArray())
    status = $status
}
$summaryPath = Join-Path $outRoot 'quest-sam-validation-summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Quest SAM validation status: $status"
Write-Host "Summary: $summaryPath"
if ($status -ne 'pass') {
    throw "Quest SAM validation failed. See $summaryPath"
}
