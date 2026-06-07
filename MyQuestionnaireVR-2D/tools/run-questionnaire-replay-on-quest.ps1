param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$Apk = "",
    [string]$Serial = "",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [int]$WaitSeconds = 20,
    [switch]$DryRun,
    [switch]$LeaveForeground,
    [switch]$StopLegacyUnityApp
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "quest-replay-export-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-replay-export\" + $RunId)
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 12)

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonIfExists {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Resolve-ApkPath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
    }
    if (-not [System.IO.Path]::IsPathRooted($Value)) {
        $Value = Join-Path $ProjectPath $Value
    }
    $resolved = [System.IO.Path]::GetFullPath($Value)
    $projectRoot = $ProjectPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not ($resolved.Equals($ProjectPath, [System.StringComparison]::OrdinalIgnoreCase) -or $resolved.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "APK path must stay inside the project folder: $resolved"
    }
    if ([System.IO.Path]::GetExtension($resolved) -ne '.apk') {
        throw "Replay target must be an .apk file: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "APK not found: $resolved"
    }
    return $resolved
}

function Get-FileEvidence {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path = $Path
        bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
    }
}

$summaryPath = Join-Path $OutputRoot 'quest-replay-export-summary.json'
$resolvedApk = Resolve-ApkPath -Value $Apk
$apkEvidence = Get-FileEvidence -Path $resolvedApk

$readinessRoot = Join-Path $OutputRoot 'quest-adb-readiness'
$readinessArgs = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $ProjectPath 'tools\quest-adb-readiness.ps1'),
    '-ProjectPath',
    $ProjectPath,
    '-OutputRoot',
    $readinessRoot,
    '-RunId',
    ($RunId + '-readiness'),
    '-WaitSeconds',
    '0'
)
if (-not [string]::IsNullOrWhiteSpace($Serial)) {
    $readinessArgs += @('-ExpectedSerial', $Serial)
}
if (-not $DryRun) {
    $readinessArgs += '-RequireOnline'
}

$readinessOutputPath = Join-Path $OutputRoot 'quest-adb-readiness-output.txt'
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $readinessOutput = & powershell @readinessArgs 2>&1
    $readinessExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
}
finally {
    $ErrorActionPreference = $previous
}
@($readinessOutput) | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath $readinessOutputPath -Encoding UTF8

$readinessSummaryPath = Join-Path $readinessRoot 'quest-adb-readiness-summary.json'
$readinessSummary = Read-JsonIfExists -Path $readinessSummaryPath
$targetSerial = if ($readinessSummary -and $readinessSummary.targetSerial) { [string]$readinessSummary.targetSerial } else { $Serial }

$questValidationSummaryPath = Join-Path $OutputRoot 'quest-validation\my-questionnaire-2d-validation-summary.json'
$questValidation = $null
$questValidationExitCode = $null
$questValidationOutputPath = Join-Path $OutputRoot 'quest-validate-output.txt'
$notes = New-Object 'System.Collections.Generic.List[string]'

if ($DryRun) {
    $status = if ($readinessSummary -and $readinessSummary.readiness -eq 'online') { 'pass' } else { 'warn' }
    $notes.Add('Dry run: verified APK path and readiness summary without installing, launching, replaying, or pulling exports.') | Out-Null
}
elseif ($readinessExitCode -ne 0 -or -not $readinessSummary -or $readinessSummary.readiness -ne 'online') {
    $status = 'fail'
    $notes.Add('Quest ADB readiness did not reach online state; replay/export was not attempted.') | Out-Null
}
else {
    $questValidationRoot = Join-Path $OutputRoot 'quest-validation'
    $questArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $ProjectPath 'tools\quest-validate.ps1'),
        '-ProjectPath',
        $ProjectPath,
        '-OutputRoot',
        $questValidationRoot,
        '-Apk',
        $resolvedApk,
        '-Serial',
        $targetSerial,
        '-WaitSeconds',
        [string][Math]::Max(1, $WaitSeconds),
        '-SkipBuild'
    )
    if ($LeaveForeground) {
        $questArgs += '-LeaveForeground'
    }
    if ($StopLegacyUnityApp) {
        $questArgs += '-StopLegacyUnityApp'
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $questOutput = & powershell @questArgs 2>&1
        $questValidationExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    }
    finally {
        $ErrorActionPreference = $previous
    }
    @($questOutput) | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath $questValidationOutputPath -Encoding UTF8

    $questValidation = Read-JsonIfExists -Path $questValidationSummaryPath
    if ($questValidationExitCode -eq 0 -and $questValidation) {
        $status = 'pass'
        $notes.Add('Quest command replay/export validation completed successfully.') | Out-Null
    }
    else {
        $status = 'fail'
        $notes.Add('Quest command replay/export validation failed or did not write a summary.') | Out-Null
    }
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.quest-replay-export.v1'
    status = $status
    runId = $RunId
    projectPath = $ProjectPath
    dryRun = [bool]$DryRun
    apk = $apkEvidence
    serial = $targetSerial
    readiness = if ($readinessSummary) { $readinessSummary.readiness } else { 'missing-summary' }
    readinessStatus = if ($readinessSummary) { $readinessSummary.status } else { 'missing-summary' }
    readinessSummaryPath = $readinessSummaryPath
    readinessOutputPath = $readinessOutputPath
    questValidationExitCode = $questValidationExitCode
    questValidationSummaryPath = $questValidationSummaryPath
    questValidationOutputPath = $questValidationOutputPath
    questValidation = $questValidation
    notes = @($notes)
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
Write-Json -Value $summary -Path $summaryPath

[pscustomobject]@{
    Status = $status
    DryRun = [bool]$DryRun
    Apk = $resolvedApk
    Serial = $targetSerial
    Summary = $summaryPath
}

if ($status -eq 'fail') {
    throw "Quest replay/export validation failed or was not attempted. See $summaryPath"
}
