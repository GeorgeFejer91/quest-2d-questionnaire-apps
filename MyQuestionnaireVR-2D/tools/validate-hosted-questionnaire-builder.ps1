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
    [ordered]@{ id = 'hosted-final-product-mode'; text = 'hosted-final-product' },
    [ordered]@{ id = 'development-only-markers'; text = 'data-dev-only' },
    [ordered]@{ id = 'downloads-companion-zip'; text = 'Companion software ZIP' },
    [ordered]@{ id = 'downloads-online-connector'; text = 'Online connector launcher' },
    [ordered]@{ id = 'dependency-status-before-apk'; text = 'id="dependencyStatusButton" type="button">Dependency status' },
    [ordered]@{ id = 'dependency-install-before-apk'; text = 'id="installDependenciesButton" type="button">Install dependencies' },
    [ordered]@{ id = 'apk-first-example-catalog'; text = 'Load preloaded demo APK' },
    [ordered]@{ id = 'apk-scan-stage'; text = 'Load APK and scan triggers' },
    [ordered]@{ id = 'trigger-block-assignment'; text = 'Block 1' },
    [ordered]@{ id = 'questionnaire-type-select'; text = 'Add questionnaire page' },
    [ordered]@{ id = 'questionnaire-empty-page-card'; text = 'questionnaire-empty-page' },
    [ordered]@{ id = 'block1-module-controls'; text = 'id="block1ModuleDemographics"' },
    [ordered]@{ id = 'questionnaire-sequence-contract'; text = 'id="chainQuestionnaireSequence"' },
    [ordered]@{ id = 'csv-template-selector'; text = 'id="csvTemplateKind"' },
    [ordered]@{ id = 'csv-template-download'; text = 'id="downloadCsvTemplateButton"' },
    [ordered]@{ id = 'csv-upload-visible'; text = 'id="loadCsvInput"' },
    [ordered]@{ id = 'pictographic-zip-template-download'; text = 'id="downloadPictographicZipTemplateButton"' },
    [ordered]@{ id = 'pictographic-zip-upload-visible'; text = 'id="loadPictographicZipInput"' },
    [ordered]@{ id = 'local-companion-token-header'; text = 'X-MQ-Builder-Token' },
    [ordered]@{ id = 'companion-status-health'; text = '/api/status' },
    [ordered]@{ id = 'generate-apk-endpoint'; text = '/api/generate-apk' },
    [ordered]@{ id = 'generate-apk-button'; text = 'Bake questionnaire APK' },
    [ordered]@{ id = 'install-apk-button'; text = 'Install both APKs on Quest' },
    [ordered]@{ id = 'generate-apk-button-gated'; text = 'id="generateApkAppButton" class="primary" type="button" data-requires-apk-control' },
    [ordered]@{ id = 'install-apk-button-gated'; text = 'id="installApkAppButton" class="primary" type="button" data-requires-apk-control' },
    [ordered]@{ id = 'stage-scenario-apk-endpoint'; text = '/api/stage-scenario-apk' },
    [ordered]@{ id = 'stage-scenario-apk-capability'; text = 'stage-scenario-apk' },
    [ordered]@{ id = 'repo-example-apk-scan-endpoint'; text = '/api/stage-repo-example-scenario-apk' },
    [ordered]@{ id = 'repo-example-apk-scan-capability'; text = 'stage-repo-example-scenario-apk' },
    [ordered]@{ id = 'hidden-legacy-questionnaire-stage'; text = 'id="questionnaire-stage" class="stage" data-requires-apk data-dev-only hidden' },
    [ordered]@{ id = 'hidden-project-stage'; text = 'id="project-stage" class="stage" data-requires-apk data-dev-only hidden' },
    [ordered]@{ id = 'hidden-review-stage'; text = 'id="review-stage" class="stage" data-requires-apk data-dev-only hidden' },
    [ordered]@{ id = 'developer-controls-hidden-by-default'; text = '[data-dev-only]' },
    [ordered]@{ id = 'dynamic-block-nav'; text = 'id="dynamicBlockNavLinks"' },
    [ordered]@{ id = 'startup-block-segment-anchor'; text = 'block-segment-startup' },
    [ordered]@{ id = 'trigger-block-segment-anchor'; text = 'block-segment-trigger-' },
    [ordered]@{ id = 'hosted-runner-unlocked'; text = 'runnerStage.removeAttribute("data-requires-apk")' },
    [ordered]@{ id = 'hosted-editable-block-front-door'; text = 'shouldUseHostedQuestionnaireFirstDefaults' },
    [ordered]@{ id = 'quest-readiness-endpoint'; text = '/api/quest-readiness' },
    [ordered]@{ id = 'install-apk-endpoint'; text = '/api/install-apk' },
    [ordered]@{ id = 'hosted-product-capabilities'; text = 'hostedProductBackendCapabilities' },
    [ordered]@{ id = 'product-mode-hides-validation'; text = 'validateWorkflowAppButton" type="button" data-dev-only' },
    [ordered]@{ id = 'product-mode-hides-review'; text = 'review-stage" class="stage" data-requires-apk data-dev-only' },
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
