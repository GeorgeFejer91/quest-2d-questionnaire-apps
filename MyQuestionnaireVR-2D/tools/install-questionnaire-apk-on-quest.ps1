param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$Apk = "",
    [string]$Serial = "",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [int]$WaitSeconds = 0,
    [string]$Package = "org.questquestionnaire.questionnaires2d",
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "quest-apk-install-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath ("artifacts\quest-apk-install\" + $RunId)
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 10)

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
        throw "Install target must be an .apk file: $resolved"
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

function Invoke-AdbCapture {
    param(
        [string]$Adb,
        [string]$Serial,
        [string[]]$Arguments,
        [string]$OutputPath
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Adb -s $Serial @Arguments 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    }
    finally {
        $ErrorActionPreference = $previous
    }
    @($output) | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return [ordered]@{
        exitCode = $exitCode
        outputPath = $OutputPath
        outputTail = (@($output) | ForEach-Object { $_.ToString() } | Select-Object -Last 20) -join "`n"
    }
}

$summaryPath = Join-Path $OutputRoot 'install-questionnaire-apk-summary.json'
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
    [string][Math]::Max(0, $WaitSeconds)
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
$adbPath = if ($readinessSummary -and $readinessSummary.adb) { [string]$readinessSummary.adb } else { "" }
$install = [ordered]@{
    attempted = $false
    exitCode = $null
    outputPath = ''
    outputTail = ''
}
$packageCheck = [ordered]@{
    attempted = $false
    exitCode = $null
    outputPath = ''
    outputTail = ''
}

$status = 'warn'
$notes = New-Object 'System.Collections.Generic.List[string]'
if ($DryRun) {
    $status = if ($readinessSummary -and $readinessSummary.readiness -eq 'online') { 'pass' } else { 'warn' }
    $notes.Add('Dry run: verified APK path and readiness summary without installing.') | Out-Null
}
elseif ($readinessExitCode -ne 0 -or -not $readinessSummary -or $readinessSummary.readiness -ne 'online') {
    $status = 'fail'
    $notes.Add('Quest ADB readiness did not reach online state; install was not attempted.') | Out-Null
}
else {
    $installPath = Join-Path $OutputRoot 'adb-install.txt'
    $install = Invoke-AdbCapture -Adb $adbPath -Serial $targetSerial -Arguments @('install', '-r', '-d', '-g', $resolvedApk) -OutputPath $installPath
    $install.attempted = $true

    $packagePath = Join-Path $OutputRoot 'adb-package-path.txt'
    $packageCheck = Invoke-AdbCapture -Adb $adbPath -Serial $targetSerial -Arguments @('shell', 'pm', 'path', $Package) -OutputPath $packagePath
    $packageCheck.attempted = $true

    if ($install.exitCode -eq 0 -and $packageCheck.exitCode -eq 0 -and $packageCheck.outputTail -match '(?m)^package:') {
        $status = 'pass'
        $notes.Add('APK installed and package path was visible on the Quest.') | Out-Null
    }
    else {
        $status = 'fail'
        $notes.Add('ADB install or package visibility check failed.') | Out-Null
    }
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.quest-apk-install.v1'
    status = $status
    runId = $RunId
    projectPath = $ProjectPath
    dryRun = [bool]$DryRun
    apk = $apkEvidence
    package = $Package
    serial = $targetSerial
    readiness = if ($readinessSummary) { $readinessSummary.readiness } else { 'missing-summary' }
    readinessStatus = if ($readinessSummary) { $readinessSummary.status } else { 'missing-summary' }
    readinessSummaryPath = $readinessSummaryPath
    readinessOutputPath = $readinessOutputPath
    adb = $adbPath
    install = $install
    packageCheck = $packageCheck
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
    throw "Quest APK install failed or was not attempted. See $summaryPath"
}
