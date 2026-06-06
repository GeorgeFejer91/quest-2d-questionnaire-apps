$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $ProjectRoot 'app\src\main\assets\questionnaire'
$runtimeConfigPath = Join-Path $assets 'QuestionnaireConfig.json'
$requiredFiles = @('QuestionnaireConfig.json', 'UIText.txt')

foreach ($relative in $requiredFiles) {
    $path = Join-Path $assets $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required artifact: $path"
    }
}

function Count-NonEmptyLines {
    param([string]$Path)
    return @((Get-Content -LiteralPath $Path -Encoding UTF8) | Where-Object { $_.Trim().Length -gt 0 }).Count
}

$runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json
if ($runtimeConfig.schemaVersion -ne 'my-questionnaire-vr.config.v1') {
    throw "QuestionnaireConfig.json has unexpected schemaVersion: $($runtimeConfig.schemaVersion)"
}

$sliderBlock = @($runtimeConfig.blocks | Where-Object { $_.type -eq 'slider' } | Select-Object -First 1)[0]
$maiaBlock = @($runtimeConfig.blocks | Where-Object { $_.id -eq 'maia2' } | Select-Object -First 1)[0]
$pictographicBlock = @($runtimeConfig.blocks | Where-Object { $_.type -eq 'pictographic' } | Select-Object -First 1)[0]

if ($null -eq $sliderBlock) { throw "QuestionnaireConfig.json is missing a slider block." }

$expectedSliderCount = [int]$sliderBlock.expectedItemCount
$expectedMaiaCount = if ($maiaBlock) { [int]$maiaBlock.expectedItemCount } else { 0 }

$languageCounts = [ordered]@{}
foreach ($language in @($runtimeConfig.languages)) {
    $questionFile = Join-Path $assets ("Questions_$language.txt")
    if (-not (Test-Path -LiteralPath $questionFile)) {
        throw "Missing required slider language artifact: $questionFile"
    }

    $count = Count-NonEmptyLines $questionFile
    $languageCounts[$language] = $count
    if ($expectedSliderCount -gt 0 -and $count -ne $expectedSliderCount) {
        throw "Questions_$language.txt should contain $expectedSliderCount non-empty items, found $count"
    }
}

$maiaCount = 0
if ($maiaBlock) {
    $maiaPath = Join-Path $assets 'MAIA2_Questions.json'
    if (-not (Test-Path -LiteralPath $maiaPath)) {
        throw "Missing MAIA-2 artifact required by runtime config: $maiaPath"
    }

    $maiaCount = @((Get-Content -LiteralPath $maiaPath -Encoding UTF8 -Raw | ConvertFrom-Json)).Count
    if ($expectedMaiaCount -gt 0 -and $maiaCount -ne $expectedMaiaCount) {
        throw "MAIA2_Questions.json should contain $expectedMaiaCount items, found $maiaCount"
    }
}

if ($pictographicBlock) {
    foreach ($prompt in @($pictographicBlock.prompts)) {
        $imagePath = Join-Path $assets ("PictographicScales\" + $prompt.imageFileName)
        if (-not (Test-Path -LiteralPath $imagePath)) {
            throw "Missing pictographic image artifact: $imagePath"
        }
    }
}

$blockOrder = (@($runtimeConfig.blocks) | ForEach-Object { $_.id }) -join '>'
if (@($runtimeConfig.blocks).Count -lt 3 -or $runtimeConfig.blocks[0].type -ne 'demographics' -or $runtimeConfig.blocks[-1].type -ne 'blackScreen') {
    throw "QuestionnaireConfig.json block order should start with demographics and end with blackScreen: $blockOrder"
}

[pscustomobject]@{
    ProjectRoot = $ProjectRoot
    AndroidAssets = $assets
    SliderItems = $expectedSliderCount
    LanguageCounts = ($languageCounts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
    Maia2Items = $maiaCount
    PictographicImages = if ($pictographicBlock) { @($pictographicBlock.prompts).Count } else { 0 }
    RuntimeBlocks = @($runtimeConfig.blocks).Count
    Status = 'OK'
} | Format-List
