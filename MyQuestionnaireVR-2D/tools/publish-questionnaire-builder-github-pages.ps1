param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PagesRoot = "",
    [string]$PagesSubdir = "questionnaire-builder",
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-SafeFullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-ChildPath {
    param(
        [string]$Child,
        [string]$Parent
    )

    $childFull = Get-SafeFullPath $Child
    $parentFull = (Get-SafeFullPath $Parent).TrimEnd('\')
    if (-not $childFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside pages root. Child=$childFull Parent=$parentFull"
    }
}

function Write-Utf8NoBomLf {
    param(
        [string]$Path,
        [string]$Text
    )

    $normalized = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    [System.IO.File]::WriteAllText($Path, $normalized + "`n", [System.Text.UTF8Encoding]::new($false))
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

$sourceHtml = Join-Path $projectFull 'tools\questionnaire-config-editor\index.html'
$validateScript = Join-Path $projectFull 'tools\validate-questionnaire-builder.ps1'
if (-not (Test-Path -LiteralPath $sourceHtml)) {
    throw "Questionnaire builder HTML not found: $sourceHtml"
}
if (-not (Test-Path -LiteralPath $pagesRootFull)) {
    throw "Pages root not found: $pagesRootFull"
}
if (-not (Test-Path -LiteralPath $validateScript)) {
    throw "Questionnaire builder validator not found: $validateScript"
}

if (-not $SkipValidation) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validateScript -ProjectPath $projectFull | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Builder validation failed with exit code $LASTEXITCODE"
    }
}

$targetDir = Join-Path $pagesRootFull $PagesSubdir
Assert-ChildPath -Child $targetDir -Parent $pagesRootFull
if (Test-Path -LiteralPath $targetDir) {
    Remove-Item -LiteralPath $targetDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

Copy-Item -LiteralPath $sourceHtml -Destination (Join-Path $targetDir 'index.html') -Force

$readme = @"
# Quest Questionnaire Builder

This folder is the static GitHub Pages version of the questionnaire builder.
It can edit configs and import trigger catalogs entirely in the browser.

Local build actions require the Windows companion running on the user's PC:

```powershell
Start-QuestionnaireBuilderOnlineConnector.cmd
```

That companion exposes a token-protected API at `http://127.0.0.1:8765`.
Enter the printed pairing token in the web UI before saving configs,
checking dependencies, validating configs, or generating APKs.

The hosted page is intentionally static. It does not install software or run
build tools directly; the local companion owns file system and build actions.
"@
$readme | Set-Content -LiteralPath (Join-Path $targetDir 'README.md') -Encoding UTF8

$manifest = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.github-pages-builder.v1'
    status = 'pass'
    projectPath = $projectFull
    pagesRoot = $pagesRootFull
    targetDir = $targetDir
    entrypoint = Join-Path $targetDir 'index.html'
    localConnectorUrl = 'http://127.0.0.1:8765'
    localConnectorLauncher = 'Start-QuestionnaireBuilderOnlineConnector.cmd'
    completedAt = (Get-Date).ToString('o')
}
Write-Utf8NoBomLf -Path (Join-Path $targetDir 'questionnaire-builder-pages-manifest.json') -Text ($manifest | ConvertTo-Json -Depth 6)

Write-Host "GitHub Pages questionnaire builder staged at $targetDir"
Write-Host "Commit and push that folder from the Pages repository to publish it."
