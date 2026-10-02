param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$assetRoot = Join-Path $ProjectPath 'app\src\main\assets\sam'
$provenancePath = Join-Path $assetRoot 'asset-provenance.json'
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Test-XmlFile {
    param([string]$Path)
    try {
        [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8) | Out-Null
        return $true
    }
    catch {
        Add-Failure "Invalid XML/SVG: $Path :: $($_.Exception.Message)"
        return $false
    }
}

if (-not (Test-Path -LiteralPath $assetRoot)) {
    Add-Failure "Missing SAM asset root: $assetRoot"
}

foreach ($dimension in @('valence', 'arousal')) {
    for ($i = 1; $i -le 5; $i++) {
        $path = Join-Path $assetRoot "source\$dimension\$dimension-$i.svg"
        if (-not (Test-Path -LiteralPath $path)) {
            Add-Failure "Missing source SVG: $path"
            continue
        }
        if ((Get-Item -LiteralPath $path).Length -lt 1000) {
            Add-Failure "Source SVG is unexpectedly small: $path"
        }
        Test-XmlFile -Path $path | Out-Null
    }
}

foreach ($grid in @('grid\sam_valence_grid.svg', 'grid\sam_arousal_grid.svg')) {
    $path = Join-Path $assetRoot $grid
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Missing composed grid SVG: $path"
        continue
    }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($text -notmatch 'data:image/svg\+xml;base64,') {
        Add-Failure "Composed grid SVG should be self-contained with embedded source SVGs: $path"
    }
    Test-XmlFile -Path $path | Out-Null
}

if (-not (Test-Path -LiteralPath $provenancePath)) {
    Add-Failure "Missing provenance file: $provenancePath"
}
else {
    $provenance = Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($provenance.schema -ne 'quest-questionnaire.sam-assets.v1') {
        Add-Failure "Unexpected provenance schema: $($provenance.schema)"
    }
    if ($provenance.sourceLicense -ne 'CC0-1.0') {
        Add-Failure "Unexpected SAM source license: $($provenance.sourceLicense)"
    }
    if (@($provenance.sourceFiles).Count -ne 10) {
        Add-Failure "Expected 10 source file hashes, found $(@($provenance.sourceFiles).Count)"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $assetRoot 'SAM-vectors-LICENSE-CC0.txt'))) {
    Add-Failure "Missing copied CC0 license text."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "SAM asset validation failed."
}

[pscustomobject]@{
    schema = 'quest-questionnaire.sam-assets.validation.v1'
    assetRoot = $assetRoot
    sourceSvgCount = 10
    gridSvgCount = 2
    provenance = $provenancePath
    status = 'OK'
} | ConvertTo-Json -Depth 4
