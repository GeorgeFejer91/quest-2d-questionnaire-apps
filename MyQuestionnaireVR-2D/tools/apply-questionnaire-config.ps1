param(
    [string]$ConfigPath = "",
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR"
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $ProjectRoot 'QuestionnaireConfigs\viscereality-maia2.config.json'
}

$validateConfigScript = Join-Path $PSScriptRoot 'validate-questionnaire-config.ps1'
& $validateConfigScript -ConfigPath $ConfigPath -ReferenceProjectPath $ReferenceProjectPath | Out-Host

$config = Get-Content -LiteralPath $ConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json
$assets = Join-Path $ProjectRoot 'app\src\main\assets\questionnaire'
$pictographic = Join-Path $assets 'PictographicScales'
New-Item -ItemType Directory -Force -Path $assets, $pictographic | Out-Null

function Resolve-SourcePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    $local = Join-Path $ProjectRoot ($Path -replace '/', '\')
    if (Test-Path -LiteralPath $local) {
        return $local
    }

    return Join-Path $ReferenceProjectPath ($Path -replace '/', '\')
}

function Copy-Source {
    param(
        [string]$Source,
        [string]$Target
    )
    $resolvedSource = Resolve-SourcePath $Source
    if (-not (Test-Path -LiteralPath $resolvedSource)) {
        throw "Source file not found: $resolvedSource"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    Copy-Item -LiteralPath $resolvedSource -Destination $Target -Force
}

function Write-Utf8Lines {
    param([object[]]$Items, [string]$Target)
    [System.IO.File]::WriteAllText($Target, (@($Items) -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Json {
    param([object[]]$Items, [string]$Target)
    [System.IO.File]::WriteAllText($Target, (@($Items) | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

if ($config.uiTextSource) {
    Copy-Source $config.uiTextSource (Join-Path $assets 'UIText.txt')
}

foreach ($block in @($config.blocks)) {
    if ($block.type -eq 'likert') {
        $target = Join-Path $assets 'MAIA2_Questions.json'
        if ($block.PSObject.Properties.Name -contains 'items') {
            Write-Utf8Json @($block.items) $target
        }
        else {
            Copy-Source $block.source $target
        }
    }

    if ($block.type -eq 'slider') {
        foreach ($languageProperty in $block.languages.PSObject.Properties) {
            $target = Join-Path $assets ("Questions_" + $languageProperty.Name + ".txt")
            $languageBlock = $languageProperty.Value
            if ($languageBlock.PSObject.Properties.Name -contains 'items') {
                Write-Utf8Lines @($languageBlock.items) $target
            }
            else {
                Copy-Source $languageBlock.source $target
            }
        }
    }

    if ($block.type -eq 'pictographic') {
        foreach ($prompt in @($block.prompts)) {
            Copy-Source $prompt.source (Join-Path $pictographic $prompt.imageFileName)
        }
    }
}

$runtimeBlocks = @()
foreach ($block in @($config.blocks)) {
    $languageSources = @()
    if ($block.PSObject.Properties.Name -contains 'languages' -and $null -ne $block.languages) {
        foreach ($languageProperty in $block.languages.PSObject.Properties) {
            $languageBlock = $languageProperty.Value
            $inlineCount = if ($languageBlock.PSObject.Properties.Name -contains 'items') { @($languageBlock.items).Count } else { 0 }
            $languageSources += [ordered]@{
                language = $languageProperty.Name
                source = $languageBlock.source
                target = "app/src/main/assets/questionnaire/Questions_$($languageProperty.Name).txt"
                inlineItemCount = $inlineCount
            }
        }
    }

    $prompts = @()
    foreach ($prompt in @($block.prompts)) {
        if ($null -eq $prompt) { continue }
        $prompts += [ordered]@{
            id = $prompt.id
            imageFileName = $prompt.imageFileName
            source = $prompt.source
            promptEnglish = $prompt.promptEnglish
            promptDeutsch = $prompt.promptDeutsch
            choices = @($prompt.choices)
        }
    }

    $scoreGroups = @()
    foreach ($group in @($block.scoreGroups)) {
        if ($null -eq $group) { continue }
        $scoreGroups += [ordered]@{
            id = $group.id
            label = $group.label
            items = @($group.items | ForEach-Object { [int]$_ })
        }
    }

    $anchors = $null
    if ($block.PSObject.Properties.Name -contains 'anchors' -and $null -ne $block.anchors) {
        $anchors = [ordered]@{ left = $block.anchors.left; right = $block.anchors.right }
    }

    $runtimeBlocks += [ordered]@{
        id = $block.id
        type = $block.type
        expectedItemCount = if ($block.expectedItemCount) { [int]$block.expectedItemCount } else { 0 }
        min = if ($null -ne $block.min) { [int]$block.min } else { 0 }
        max = if ($null -ne $block.max) { [int]$block.max } else { 0 }
        wholeNumbers = [bool]$block.wholeNumbers
        anchors = $anchors
        languageSources = $languageSources
        prompts = $prompts
        scoreGroups = $scoreGroups
        choices = @($block.choices)
    }
}

$runtimeParticipantFields = @()
foreach ($field in @($config.participantFields)) {
    $runtimeParticipantFields += [ordered]@{
        id = $field.id
        type = $field.type
        required = [bool]$field.required
    }
}

$runtimeConfig = [ordered]@{
    schemaVersion = $config.schemaVersion
    questionnaireId = $config.questionnaireId
    questionnaireVersion = $config.questionnaireVersion
    appVersion = $config.appVersion
    sourceConfig = 'QuestionnaireConfigs/' + [System.IO.Path]::GetFileName($ConfigPath)
    sourceRepository = if ($config.sourceRepository) { $config.sourceRepository } else { 'MesmerPrism/Viscereality' }
    sourceCommit = if ($config.sourceCommit) { $config.sourceCommit } else { '7f0f7c9a40885aa841892b9a680acf45fa45b2d7' }
    maia2SourcePath = if ($config.maia2SourcePath) { $config.maia2SourcePath } else { 'C:\Users\cogpsy-vrlab\Documents\GitHub\maia-2\questionnaire\src' }
    languages = @($config.languages)
    participantFields = $runtimeParticipantFields
    blocks = $runtimeBlocks
    exports = [ordered]@{
        destination = 'getExternalFilesDir(null)/QuestionnaireExports'
        formats = @($config.exports.formats)
    }
    chainDefaults = if ($config.PSObject.Properties.Name -contains 'chainDefaults' -and $null -ne $config.chainDefaults) {
        [ordered]@{
            finishBehavior = if ($config.chainDefaults.finishBehavior) { $config.chainDefaults.finishBehavior } else { 'staySaved' }
            callerPackage = if ($config.chainDefaults.callerPackage) { $config.chainDefaults.callerPackage } else { '' }
            callerActivity = if ($config.chainDefaults.callerActivity) { $config.chainDefaults.callerActivity } else { '' }
            nextPackage = if ($config.chainDefaults.nextPackage) { $config.chainDefaults.nextPackage } else { '' }
            nextActivity = if ($config.chainDefaults.nextActivity) { $config.chainDefaults.nextActivity } else { '' }
            autoCloseDelayMs = if ($config.chainDefaults.autoCloseDelayMs) { [int]$config.chainDefaults.autoCloseDelayMs } else { 2000 }
        }
    } else {
        [ordered]@{
            finishBehavior = 'staySaved'
            callerPackage = ''
            callerActivity = ''
            nextPackage = ''
            nextActivity = ''
            autoCloseDelayMs = 2000
        }
    }
}
[System.IO.File]::WriteAllText((Join-Path $assets 'QuestionnaireConfig.json'), ($runtimeConfig | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    AppliedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    AndroidAssets = $assets
    Status = 'OK'
} | Format-List
