param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$AuditSummaryPath = "",
    [string]$CompanionSummaryPath = "",
    [string]$QuestSerial = ""
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "universal-handoff-physical-gate-packet-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

function Resolve-FullPath {
    param(
        [string]$Path,
        [string]$BasePath = (Get-Location).Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function ConvertTo-LongPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $IsWindows -and [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $fullPath
    }
    if ($fullPath.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
        return $fullPath
    }
    if ($fullPath.StartsWith('\\', [System.StringComparison]::Ordinal)) {
        return '\\?\UNC\' + $fullPath.TrimStart('\')
    }
    return '\\?\' + $fullPath
}

function Write-Utf8TextFile {
    param(
        [string]$Path,
        [string]$Text
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [System.IO.Directory]::CreateDirectory((ConvertTo-LongPath -Path $directory)) | Out-Null
    }
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText((ConvertTo-LongPath -Path $Path), $Text, $encoding)
}

function Write-Utf8JsonFile {
    param(
        [string]$Path,
        [object]$Object,
        [int]$Depth = 100
    )

    Write-Utf8TextFile -Path $Path -Text (($Object | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Test-FileExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return [System.IO.File]::Exists((ConvertTo-LongPath -Path $Path))
}

function Read-JsonIfExists {
    param([string]$Path)

    if (-not (Test-FileExists -Path $Path)) {
        return $null
    }
    return ([System.IO.File]::ReadAllText((ConvertTo-LongPath -Path $Path)) | ConvertFrom-Json)
}

function Get-JsonProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object -or -not $Object.PSObject -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }
    return $Object.$Name
}

function Invoke-LocalPowerShell {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    Push-Location $WorkingDirectory
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell @Arguments 2>&1 | ForEach-Object { $_.ToString() } | Out-String
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        return [ordered]@{
            exitCode = $exitCode
            output = $output.TrimEnd()
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }
}

function Resolve-LatestSummary {
    param(
        [string]$Root,
        [string]$Filter
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return ""
    }
    $candidate = Get-ChildItem -LiteralPath $Root -Recurse -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }
    return ""
}

function Get-RequirementRows {
    param([object]$Audit)

    $requirements = @(Get-JsonProperty -Object $Audit -Name 'requirements' -Default @())
    return @($requirements | ForEach-Object {
        [ordered]@{
            id = [string](Get-JsonProperty -Object $_ -Name 'id' -Default '')
            label = [string](Get-JsonProperty -Object $_ -Name 'label' -Default '')
            status = [string](Get-JsonProperty -Object $_ -Name 'status' -Default '')
            evidencePath = [string](Get-JsonProperty -Object $_ -Name 'evidencePath' -Default '')
            missingEvidence = @(Get-JsonProperty -Object $_ -Name 'missingEvidence' -Default @())
            blockedReasons = @(Get-JsonProperty -Object $_ -Name 'blockedReasons' -Default @())
        }
    })
}

$projectFull = Resolve-FullPath -Path $ProjectPath
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectFull ("artifacts\universal-handoff-physical-gate-packet\" + $RunId)
}
$outputFull = Resolve-FullPath -Path $OutputRoot
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null

$auditScript = Join-Path $projectFull 'tools\audit-universal-handoff-readiness.ps1'
$manualSignoffScript = Join-Path $projectFull 'tools\new-direct-handoff-manual-signoff.ps1'
$auditRunId = $RunId + '-audit'
$auditStdoutPath = Join-Path $outputFull 'audit-stdout.txt'
$manualStdoutPath = Join-Path $outputFull 'manual-signoff-stdout.txt'

if ([string]::IsNullOrWhiteSpace($AuditSummaryPath)) {
    $auditArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $auditScript,
        '-ProjectPath',
        $projectFull,
        '-RunId',
        $auditRunId
    )
    if (-not [string]::IsNullOrWhiteSpace($CompanionSummaryPath)) {
        $auditArgs += @('-CompanionSummaryPath', (Resolve-FullPath -Path $CompanionSummaryPath -BasePath $projectFull))
    }
    $auditResult = Invoke-LocalPowerShell -Arguments $auditArgs -WorkingDirectory $projectFull
    Write-Utf8TextFile -Path $auditStdoutPath -Text ($auditResult.output + [Environment]::NewLine)
    $AuditSummaryPath = Join-Path $projectFull ("artifacts\universal-handoff-readiness\$auditRunId\universal-handoff-readiness-audit-summary.json")
}
else {
    $AuditSummaryPath = Resolve-FullPath -Path $AuditSummaryPath -BasePath $projectFull
    $auditResult = [ordered]@{
        exitCode = 0
        output = "Using existing audit summary: $AuditSummaryPath"
    }
    Write-Utf8TextFile -Path $auditStdoutPath -Text ($auditResult.output + [Environment]::NewLine)
}

$auditSummary = Read-JsonIfExists -Path $AuditSummaryPath
if ($null -eq $auditSummary) {
    throw "Audit summary was not found: $AuditSummaryPath"
}

$manualRunId = $RunId + '-manual-signoff'
$manualOutputRoot = Join-Path $outputFull 'manual-signoff'
$manualArgs = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $manualSignoffScript,
    '-ProjectPath',
    $projectFull,
    '-RunId',
    $manualRunId,
    '-OutputRoot',
    $manualOutputRoot
)
if (-not [string]::IsNullOrWhiteSpace($QuestSerial)) {
    $manualArgs += @('-QuestSerial', $QuestSerial)
}
$manualResult = Invoke-LocalPowerShell -Arguments $manualArgs -WorkingDirectory $projectFull
Write-Utf8TextFile -Path $manualStdoutPath -Text ($manualResult.output + [Environment]::NewLine)
$manualSummaryPath = Join-Path $manualOutputRoot 'direct-handoff-manual-signoff-summary.json'
$manualSummary = Read-JsonIfExists -Path $manualSummaryPath

$counts = Get-JsonProperty -Object $auditSummary -Name 'counts' -Default ([pscustomobject]@{})
$nextPhysicalGates = Get-JsonProperty -Object $auditSummary -Name 'nextPhysicalGates' -Default ([pscustomobject]@{})
$failedOrMissing = [int](Get-JsonProperty -Object $counts -Name 'failedOrMissing' -Default 0)
$physicalPending = [int](Get-JsonProperty -Object $counts -Name 'physicalPending' -Default 0)
$completionApproved = [bool](Get-JsonProperty -Object $auditSummary -Name 'completionApproved' -Default $false)
$defaultDirectApproved = [bool](Get-JsonProperty -Object $auditSummary -Name 'defaultDirectPendingIntentApproved' -Default $false)
$packetStatus = if ($completionApproved) {
    'complete'
}
elseif ($failedOrMissing -gt 0) {
    'needs-offline-attention'
}
elseif ($physicalPending -gt 0) {
    'ready-for-operator'
}
else {
    [string](Get-JsonProperty -Object $auditSummary -Name 'status' -Default 'unknown')
}

$serialPlaceholder = if ([string]::IsNullOrWhiteSpace($QuestSerial)) { '<quest-serial>' } else { $QuestSerial }
$runbookPath = Join-Path $outputFull 'physical-gate-runbook.txt'
$packetSummaryPath = Join-Path $outputFull 'universal-handoff-physical-gate-packet-summary.json'
$remainingRequirements = @(Get-RequirementRows -Audit $auditSummary | Where-Object { $_.status -ne 'proven' })
$manualEvidence = Get-JsonProperty -Object $manualSummary -Name 'evidence' -Default ([pscustomobject]@{})

$runbook = @"
Universal Quest Handoff physical gate packet
===========================================

Packet status: $packetStatus
Generated at: $((Get-Date).ToUniversalTime().ToString('o'))
Project: $projectFull
Quest serial: $serialPlaceholder

Current audit
-------------

Audit summary:
$AuditSummaryPath

Audit status: $([string](Get-JsonProperty -Object $auditSummary -Name 'status' -Default 'unknown'))
Requirements proven: $([int](Get-JsonProperty -Object $counts -Name 'proven' -Default 0)) / $([int](Get-JsonProperty -Object $counts -Name 'requirements' -Default 0))
Physical gates pending: $physicalPending
Offline failed or missing: $failedOrMissing
Default direct PendingIntent approved: $defaultDirectApproved
Product-path status: $([string](Get-JsonProperty -Object $nextPhysicalGates -Name 'productPathStatus' -Default 'unknown'))
Product-path blocked reasons: $(@(Get-JsonProperty -Object $nextPhysicalGates -Name 'productPathBlockedReasons' -Default @()) -join ', ')

Remaining headset gates
-----------------------

1. 2D-first front door:
   GUI: Run 2D-first launch with Preflight only cleared.
   CLI:
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-2d-first-launcher-validate.ps1 -Serial $serialPlaceholder -WaitForReadySeconds 30

2. Ten clean direct PendingIntent product-path trials:
   GUI: Run direct handoff with Preflight only cleared, Direct trials = 10.
   CLI:
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-direct-handoff-validate.ps1 -Serial $serialPlaceholder -TrialCount 10 -WaitForReadySeconds 30 -FastVideoForValidation -AutoTraceForValidation

3. Manual headset signoff:
   Template:
   $([string](Get-JsonProperty -Object $manualEvidence -Name 'operatorSignoffTemplatePath' -Default ''))
   Instructions:
   $([string](Get-JsonProperty -Object $manualEvidence -Name 'instructionsPath' -Default ''))
   After the supervised run, save the filled template as operator-signoff.json and validate it:
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-direct-handoff-manual-signoff.ps1 -OperatorSignoffPath .\artifacts\direct-handoff-manual-signoff\<run-id>\operator-signoff.json -RequirePass

Final completion audit
----------------------

After those physical gates pass, rerun:
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-universal-handoff-readiness.ps1 -RequireComplete

Important boundary
------------------

This packet does not close any headset gate by itself. It packages the latest
offline evidence, exact remaining gates, and manual signoff template so the
operator can run the physical session without relying on chat memory.
"@
Write-Utf8TextFile -Path $runbookPath -Text ($runbook + [Environment]::NewLine)

$packet = [ordered]@{
    schemaVersion = 'mq.universal_handoff.physical_gate_packet.v1'
    status = $packetStatus
    runId = $RunId
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    projectPath = $projectFull
    questSerial = $QuestSerial
    completionApproved = $completionApproved
    defaultDirectPendingIntentApproved = $defaultDirectApproved
    physicalQuestProductPathPending = (-not $completionApproved)
    counts = $counts
    audit = [ordered]@{
        exitCode = [int]$auditResult.exitCode
        summaryPath = $AuditSummaryPath
        status = [string](Get-JsonProperty -Object $auditSummary -Name 'status' -Default 'unknown')
        nextPhysicalGates = $nextPhysicalGates
        stdoutPath = $auditStdoutPath
    }
    manualSignoff = [ordered]@{
        exitCode = [int]$manualResult.exitCode
        summaryPath = $manualSummaryPath
        status = if ($manualSummary) { [string](Get-JsonProperty -Object $manualSummary -Name 'status' -Default 'unknown') } else { 'missing-summary' }
        instructionsPath = [string](Get-JsonProperty -Object $manualEvidence -Name 'instructionsPath' -Default '')
        operatorSignoffTemplatePath = [string](Get-JsonProperty -Object $manualEvidence -Name 'operatorSignoffTemplatePath' -Default '')
        stdoutPath = $manualStdoutPath
    }
    remainingRequirements = $remainingRequirements
    nextActions = @(
        [ordered]@{
            id = 'detect-product-path-readiness'
            label = 'Detect Quest product-path readiness'
            gui = 'Detect Quest'
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-adb-readiness.ps1 -Serial $serialPlaceholder"
            closesGate = $false
        },
        [ordered]@{
            id = 'run-2d-first-live-front-door'
            label = 'Run one live 2D-first questionnaire-to-Unity launch'
            gui = 'Run 2D-first launch with Preflight only cleared'
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-2d-first-launcher-validate.ps1 -Serial $serialPlaceholder -WaitForReadySeconds 30"
            closesGate = $true
        },
        [ordered]@{
            id = 'run-ten-clean-direct-handoff-trials'
            label = 'Run ten clean direct PendingIntent product-path trials'
            gui = 'Run direct handoff with Preflight only cleared and Direct trials = 10'
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-direct-handoff-validate.ps1 -Serial $serialPlaceholder -TrialCount 10 -WaitForReadySeconds 30 -FastVideoForValidation -AutoTraceForValidation"
            closesGate = $true
        },
        [ordered]@{
            id = 'fill-and-validate-manual-signoff'
            label = 'Fill and validate the manual headset signoff'
            gui = 'Prepare manual signoff with the filled operator JSON path'
            command = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-direct-handoff-manual-signoff.ps1 -OperatorSignoffPath <operator-signoff.json> -RequirePass'
            closesGate = $true
        },
        [ordered]@{
            id = 'run-final-completion-audit'
            label = 'Run the completion audit'
            gui = 'Audit readiness after physical evidence is collected'
            command = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-universal-handoff-readiness.ps1 -RequireComplete'
            closesGate = $false
        }
    )
    artifacts = [ordered]@{
        summaryPath = $packetSummaryPath
        runbookPath = $runbookPath
        auditSummaryPath = $AuditSummaryPath
        manualSignoffSummaryPath = $manualSummaryPath
        manualSignoffInstructionsPath = [string](Get-JsonProperty -Object $manualEvidence -Name 'instructionsPath' -Default '')
        operatorSignoffTemplatePath = [string](Get-JsonProperty -Object $manualEvidence -Name 'operatorSignoffTemplatePath' -Default '')
    }
    proofBoundary = 'This packet prepares the physical validation session. It does not install, launch, wake, or otherwise change the Quest, and it does not replace live product-path trials or human headset signoff.'
}

Write-Utf8JsonFile -Path $packetSummaryPath -Object $packet -Depth 100

Write-Host "Universal Handoff physical gate packet written:"
Write-Host $packetSummaryPath
Write-Host "Status: $packetStatus"
