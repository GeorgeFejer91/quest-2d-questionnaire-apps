param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$assetRoot = Join-Path $ProjectPath 'app\src\main\assets\sam'
$sourceRoot = Join-Path $assetRoot 'source'
$gridRoot = Join-Path $assetRoot 'grid'
New-Item -ItemType Directory -Force -Path `
    (Join-Path $sourceRoot 'valence'), `
    (Join-Path $sourceRoot 'arousal'), `
    $gridRoot | Out-Null

$headers = @{ 'User-Agent' = 'QuestQuestionnaireSAM2D' }
$sourceRepository = 'https://github.com/hexa-/SAM-vectors'
$sourceLicense = 'CC0-1.0'
$sourceReference = 'Lang, P. J. (1980). Behavioral treatment and bio-behavioral assessment: computer applications.'

$valenceUrls = @(
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/valence/%20valence-1.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/valence/%20valence-2.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/valence/%20valence-3.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/valence/%20valence-4.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/valence/%20valence-5.svg'
)
$arousalUrls = @(
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/arousal/arousal-1.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/arousal/arousal-2.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/arousal/arousal-3.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/arousal/arousal-4.svg',
    'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/arousal/arousal-5.svg'
)

function Save-Url {
    param(
        [string]$Url,
        [string]$Path
    )
    Invoke-WebRequest -Uri $Url -Headers $headers -OutFile $Path
}

for ($i = 0; $i -lt 5; $i++) {
    Save-Url -Url $valenceUrls[$i] -Path (Join-Path $sourceRoot ("valence\valence-$($i + 1).svg"))
    Save-Url -Url $arousalUrls[$i] -Path (Join-Path $sourceRoot ("arousal\arousal-$($i + 1).svg"))
}

Save-Url -Url 'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/LICENSE' -Path (Join-Path $assetRoot 'SAM-vectors-LICENSE-CC0.txt')
Save-Url -Url 'https://raw.githubusercontent.com/hexa-/SAM-vectors/master/README.md' -Path (Join-Path $assetRoot 'SAM-vectors-README.md')

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DataUri {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return 'data:image/svg+xml;base64,' + [System.Convert]::ToBase64String($bytes)
}

function Write-Grid {
    param(
        [string]$Dimension,
        [string]$Title,
        [string]$LowAnchor,
        [string]$HighAnchor,
        [string]$OutputPath
    )

    $slotWidth = 120
    $height = 220
    $width = 9 * $slotWidth
    $svg = New-Object System.Text.StringBuilder
    [void]$svg.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$svg.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`">")
    [void]$svg.AppendLine('  <rect width="100%" height="100%" fill="#ffffff"/>')
    [void]$svg.AppendLine("  <text x=`"16`" y=`"28`" font-family=`"Arial, sans-serif`" font-size=`"22`" font-weight=`"700`" fill=`"#111827`">$Title</text>")
    [void]$svg.AppendLine("  <line x1=`"20`" y1=`"110`" x2=`"$($width - 20)`" y2=`"110`" stroke=`"#CBD5E1`" stroke-width=`"2`"/>")
    for ($score = 1; $score -le 9; $score++) {
        $x = ($score - 1) * $slotWidth
        $cx = $x + ($slotWidth / 2)
        if ($score % 2 -eq 1) {
            $index = [int](($score - 1) / 2) + 1
            $sourcePath = Join-Path $sourceRoot "$Dimension\$Dimension-$index.svg"
            $dataUri = Get-DataUri -Path $sourcePath
            [void]$svg.AppendLine("  <image href=`"$dataUri`" x=`"$($x + 10)`" y=`"48`" width=`"100`" height=`"107`" preserveAspectRatio=`"xMidYMid meet`"/>")
        }
        else {
            [void]$svg.AppendLine("  <circle cx=`"$cx`" cy=`"110`" r=`"13`" fill=`"#ffffff`" stroke=`"#475569`" stroke-width=`"3`"/>")
        }
        [void]$svg.AppendLine("  <text x=`"$cx`" y=`"182`" text-anchor=`"middle`" font-family=`"Arial, sans-serif`" font-size=`"16`" fill=`"#334155`">$score</text>")
    }
    [void]$svg.AppendLine("  <text x=`"20`" y=`"208`" font-family=`"Arial, sans-serif`" font-size=`"16`" fill=`"#475569`">$LowAnchor</text>")
    [void]$svg.AppendLine("  <text x=`"$($width - 20)`" y=`"208`" text-anchor=`"end`" font-family=`"Arial, sans-serif`" font-size=`"16`" fill=`"#475569`">$HighAnchor</text>")
    [void]$svg.AppendLine('</svg>')
    [System.IO.File]::WriteAllText($OutputPath, $svg.ToString(), [System.Text.UTF8Encoding]::new($false))
}

$valenceGrid = Join-Path $gridRoot 'sam_valence_grid.svg'
$arousalGrid = Join-Path $gridRoot 'sam_arousal_grid.svg'
Write-Grid -Dimension 'valence' -Title 'Valence' -LowAnchor 'Very unpleasant' -HighAnchor 'Very pleasant' -OutputPath $valenceGrid
Write-Grid -Dimension 'arousal' -Title 'Arousal' -LowAnchor 'Very calm' -HighAnchor 'Very excited' -OutputPath $arousalGrid

$sourceFiles = @()
foreach ($dimension in @('valence', 'arousal')) {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot $dimension) -Filter '*.svg' -File | Sort-Object Name)) {
        $sourceFiles += [ordered]@{
            dimension = $dimension
            file = $file.Name
            relativePath = "source/$dimension/$($file.Name)"
            sha256 = Get-Sha256 -Path $file.FullName
        }
    }
}

$provenance = [ordered]@{
    schema = 'quest-questionnaire.sam-assets.v1'
    sourceRepository = $sourceRepository
    sourceLicense = $sourceLicense
    sourceReference = $sourceReference
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    sourceFiles = $sourceFiles
    composedGrids = [ordered]@{
        valence = [ordered]@{
            relativePath = 'grid/sam_valence_grid.svg'
            sha256 = Get-Sha256 -Path $valenceGrid
        }
        arousal = [ordered]@{
            relativePath = 'grid/sam_arousal_grid.svg'
            sha256 = Get-Sha256 -Path $arousalGrid
        }
    }
}

$provenancePath = Join-Path $assetRoot 'asset-provenance.json'
$provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $provenancePath -Encoding UTF8

Write-Host "SAM assets synced to $assetRoot"
Write-Host "Provenance: $provenancePath"
