param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PagesRoot = "",
    [string]$PagesSubdir = "questionnaire-builder",
    [string]$HostedUrl = "https://georgefejer91.github.io/quest-2d-questionnaire-apps/questionnaire-builder/",
    [string]$RunId = "",
    [string]$OutputDir = "",
    [int]$TimeoutSec = 30,
    [switch]$SkipHosted,
    [switch]$AllowHostedLag
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "hosted-builder-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

function Get-SafeFullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-NormalizedText {
    param([string]$Text)

    $normalized = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    return $normalized.TrimEnd() + "`n"
}

function Get-NormalizedFileText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required file not found: $Path"
    }
    return Get-NormalizedText -Text (Get-Content -LiteralPath $Path -Encoding UTF8 -Raw)
}

function Get-TextSha256 {
    param([string]$Text)

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-RequiredText {
    param(
        [string]$Name,
        [string]$Text,
        [array]$Requirements
    )

    $checks = @()
    foreach ($requirement in $Requirements) {
        $needle = [string]$requirement.text
        $checks += [ordered]@{
            id = $requirement.id
            text = $needle
            present = $Text.Contains($needle)
            artifact = $Name
        }
    }

    $missing = @($checks | Where-Object { -not [bool]$_.present })
    return [ordered]@{
        status = $(if ($missing.Count -eq 0) { 'pass' } else { 'fail' })
        artifact = $Name
        missingCount = $missing.Count
        missing = @($missing | ForEach-Object { $_.id })
        checks = $checks
    }
}

function New-ArtifactEvidence {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Text,
        [array]$Requirements
    )

    return [ordered]@{
        name = $Name
        path = $Path
        length = $Text.Length
        normalizedSha256 = Get-TextSha256 -Text $Text
        requiredText = Test-RequiredText -Name $Name -Text $Text -Requirements $Requirements
    }
}

$projectFull = Get-SafeFullPath $ProjectPath
if ([string]::IsNullOrWhiteSpace($PagesRoot)) {
    $parentRoot = Split-Path -Parent $projectFull
    if (Test-Path -LiteralPath (Join-Path $parentRoot '.git')) {
        $PagesRoot = $parentRoot
    }
    else {
        $PagesRoot = Join-Path (Split-Path -Parent $projectFull) 'meta-quest-agent-workflow'
    }
}
$pagesRootFull = Get-SafeFullPath $PagesRoot

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $projectFull ("artifacts\hosted-builder-validation\" + $RunId)
}
$outputFull = Get-SafeFullPath $OutputDir
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null

$sourceHtml = Join-Path $projectFull 'tools\questionnaire-config-editor\index.html'
$stagedHtml = Join-Path (Join-Path $pagesRootFull $PagesSubdir) 'index.html'

$requirements = @(
    [ordered]@{ id = 'apk-first-example-catalog'; text = 'Load example APK' },
    [ordered]@{ id = 'local-companion-token-header'; text = 'X-MQ-Builder-Token' },
    [ordered]@{ id = 'companion-status-health'; text = '/api/status' },
    [ordered]@{ id = 'save-config-endpoint'; text = '/api/save-config' },
    [ordered]@{ id = 'validate-config-endpoint'; text = '/api/validate-config' },
    [ordered]@{ id = 'generate-apk-endpoint'; text = '/api/generate-apk' },
    [ordered]@{ id = 'artifact-preview-endpoint'; text = '/api/artifact-preview' },
    [ordered]@{ id = 'evidence-bundle-endpoint'; text = '/api/evidence-bundle' },
    [ordered]@{ id = 'quest-readiness-endpoint'; text = '/api/quest-readiness' },
    [ordered]@{ id = 'install-apk-endpoint'; text = '/api/install-apk' },
    [ordered]@{ id = 'quest-replay-endpoint'; text = '/api/quest-replay' },
    [ordered]@{ id = 'direct-handoff-endpoint'; text = '/api/direct-handoff' },
    [ordered]@{ id = '2d-first-launcher-endpoint'; text = '/api/2d-first-launcher' },
    [ordered]@{ id = 'handoff-readiness-audit-endpoint'; text = '/api/handoff-readiness-audit' },
    [ordered]@{ id = 'direct-handoff-manual-signoff-endpoint'; text = '/api/direct-handoff-manual-signoff' },
    [ordered]@{ id = 'physical-gate-packet-endpoint'; text = '/api/physical-gate-packet' },
    [ordered]@{ id = 'validate-workflow-endpoint'; text = '/api/validate-workflow' },
    [ordered]@{ id = 'run-headset-sequence'; text = 'Run headset sequence' },
    [ordered]@{ id = 'run-2d-first-launcher'; text = 'Run 2D-first launch' },
    [ordered]@{ id = 'run-readiness-audit'; text = 'Audit readiness' },
    [ordered]@{ id = 'prepare-manual-signoff'; text = 'Prepare manual signoff' },
    [ordered]@{ id = 'prepare-physical-packet'; text = 'Prepare physical packet' },
    [ordered]@{ id = 'direct-handoff-preflight-toggle'; text = 'Preflight only' },
    [ordered]@{ id = 'wake-before-readiness-toggle'; text = 'Wake before readiness' },
    [ordered]@{ id = 'evidence-bundle-control'; text = 'Download evidence bundle' },
    [ordered]@{ id = 'workflow-receipt-rendering'; text = 'workflowReceipt' },
    [ordered]@{ id = 'runner-job-receipt-rendering'; text = 'jobReceipt' },
    [ordered]@{ id = 'example-trigger-catalog'; text = 'questionnaire-trigger-catalog.json' }
)

$sourceText = Get-NormalizedFileText -Path $sourceHtml
$stagedText = Get-NormalizedFileText -Path $stagedHtml

$sourceEvidence = New-ArtifactEvidence -Name 'source-builder-html' -Path $sourceHtml -Text $sourceText -Requirements $requirements
$stagedEvidence = New-ArtifactEvidence -Name 'staged-pages-html' -Path $stagedHtml -Text $stagedText -Requirements $requirements

$parityStatus = if ($sourceEvidence.normalizedSha256 -eq $stagedEvidence.normalizedSha256) { 'pass' } else { 'fail' }
$hostedEvidence = [ordered]@{
    status = 'skipped'
    skipped = [bool]$SkipHosted
    url = $HostedUrl
}

if (-not $SkipHosted) {
    try {
        $response = Invoke-WebRequest -Uri $HostedUrl -UseBasicParsing -TimeoutSec $TimeoutSec
        $hostedText = Get-NormalizedText -Text ([string]$response.Content)
        $hostedArtifact = New-ArtifactEvidence -Name 'hosted-pages-html' -Path $HostedUrl -Text $hostedText -Requirements $requirements
        $hashMatchesStaged = $hostedArtifact.normalizedSha256 -eq $stagedEvidence.normalizedSha256
        $requiredTextPasses = $hostedArtifact.requiredText.status -eq 'pass'
        $hostedStatus = 'pass'
        if (-not $hashMatchesStaged -or -not $requiredTextPasses) {
            $hostedStatus = if ($AllowHostedLag -and $requiredTextPasses) { 'warn' } else { 'fail' }
        }

        $hostedEvidence = [ordered]@{
            status = $hostedStatus
            url = $HostedUrl
            statusCode = [int]$response.StatusCode
            length = $hostedArtifact.length
            normalizedSha256 = $hostedArtifact.normalizedSha256
            hashMatchesStaged = $hashMatchesStaged
            allowHostedLag = [bool]$AllowHostedLag
            requiredText = $hostedArtifact.requiredText
        }
    }
    catch {
        $hostedEvidence = [ordered]@{
            status = 'fail'
            url = $HostedUrl
            error = $_.Exception.Message
        }
    }
}

$failed = @()
if ($sourceEvidence.requiredText.status -ne 'pass') { $failed += 'source-required-text' }
if ($stagedEvidence.requiredText.status -ne 'pass') { $failed += 'staged-required-text' }
if ($parityStatus -ne 'pass') { $failed += 'source-staged-parity' }
if ($hostedEvidence.status -eq 'fail') { $failed += 'hosted-pages' }

$status = if ($failed.Count -eq 0) {
    if ($hostedEvidence.status -eq 'warn') { 'warn' } else { 'pass' }
}
else {
    'fail'
}

$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.hosted-builder-validation.v1'
    status = $status
    failed = $failed
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    projectPath = $projectFull
    pagesRoot = $pagesRootFull
    pagesSubdir = $PagesSubdir
    hostedUrl = $HostedUrl
    source = $sourceEvidence
    staged = $stagedEvidence
    sourceStagedParity = [ordered]@{
        status = $parityStatus
        sourceSha256 = $sourceEvidence.normalizedSha256
        stagedSha256 = $stagedEvidence.normalizedSha256
    }
    hosted = $hostedEvidence
}

$summaryPath = Join-Path $outputFull 'hosted-questionnaire-builder-validation-summary.json'
$summary | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Hosted questionnaire builder validation status: $status"
Write-Host "Summary: $summaryPath"
if ($failed.Count -gt 0) {
    throw "Hosted questionnaire builder validation failed: $($failed -join ', ')"
}
