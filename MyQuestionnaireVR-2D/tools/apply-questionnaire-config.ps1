param(
    [string]$ConfigPath = "",
    [string]$ReferenceProjectPath = ""
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReferenceProjectPath)) {
    $siblingReference = Join-Path (Split-Path -Parent $ProjectRoot) 'MyQuestionnaireVR'
    if (Test-Path -LiteralPath $siblingReference) {
        $ReferenceProjectPath = [System.IO.Path]::GetFullPath($siblingReference)
    }
    else {
        $ReferenceProjectPath = $ProjectRoot
    }
}
else {
    $ReferenceProjectPath = [System.IO.Path]::GetFullPath($ReferenceProjectPath)
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $ProjectRoot 'QuestionnaireConfigs\quest-questionnaire-maia2.config.json'
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
    $sourceFull = [System.IO.Path]::GetFullPath($resolvedSource)
    $targetFull = [System.IO.Path]::GetFullPath($Target)
    if ($sourceFull -ieq $targetFull) {
        return
    }

    Copy-Item -LiteralPath $resolvedSource -Destination $Target -Force
}

function Format-LfNoTrailingWhitespace {
    param([string]$Text)

    $normalized = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    $lines = $normalized -split "`n", 0, "SimpleMatch"
    return (($lines | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd("`n") + "`n"
}

function Write-Utf8Text {
    param([string]$Target, [string]$Text)

    [System.IO.File]::WriteAllText($Target, (Format-LfNoTrailingWhitespace -Text $Text), [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Lines {
    param([object[]]$Items, [string]$Target)
    Write-Utf8Text -Target $Target -Text (@($Items) -join "`n")
}

function Write-Utf8Json {
    param([object[]]$Items, [string]$Target)
    Write-Utf8Text -Target $Target -Text (@($Items) | ConvertTo-Json -Depth 20)
}

function Write-DataUrlFile {
    param(
        [string]$DataUrl,
        [string]$Target
    )

    if ([string]::IsNullOrWhiteSpace($DataUrl) -or -not ($DataUrl -match '^data:[^;]+;base64,(.+)$')) {
        throw "Invalid dataUrl for target: $Target"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    [System.IO.File]::WriteAllBytes($Target, [Convert]::FromBase64String($Matches[1]))
}

function Get-FirstText {
    param([object[]]$Values)
    foreach ($value in @($Values)) {
        $text = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text.Trim()
        }
    }
    return ''
}

function Get-AppDisplayName {
    param([object]$Config)

    $configured = Get-FirstText @($Config.appDisplayName, $Config.displayName, $Config.appName)
    if (-not [string]::IsNullOrWhiteSpace($configured)) {
        return $configured
    }

    $startMode = if ($Config.chainDefaults -and $Config.chainDefaults.startMode) { [string]$Config.chainDefaults.startMode } else { 'unityFirst' }
    if ($startMode -ne 'questionnaireFirst') {
        return 'Quest Questionnaire 2D'
    }

    $targetLabel = Get-FirstText @(
        $Config.experimentBlockRegistry.targetApp.label,
        $Config.experimentBlockRegistry.scenario.label,
        $Config.triggerQuestionnaireMapping.scenarioLabel,
        $Config.chainDefaults.nextPackage
    )
    if ([string]::IsNullOrWhiteSpace($targetLabel)) {
        $targetLabel = 'Scenario APK'
    }
    return "Start Experiment | $targetLabel"
}

function Set-AndroidAppName {
    param([string]$DisplayName)

    $stringsPath = Join-Path $ProjectRoot 'app\src\main\res\values\strings.xml'
    $escaped = [System.Security.SecurityElement]::Escape($DisplayName)
    $xml = "<resources>`n    <string name=`"app_name`">$escaped</string>`n</resources>`n"
    Write-Utf8Text -Target $stringsPath -Text $xml
}

if ($config.uiTextSource) {
    $uiTextSource = Resolve-SourcePath $config.uiTextSource
    $uiTextTarget = Join-Path $assets 'UIText.txt'
    if (Test-Path -LiteralPath $uiTextSource) {
        Copy-Source $config.uiTextSource $uiTextTarget
    }
    elseif (-not (Test-Path -LiteralPath $uiTextTarget)) {
        throw "Source file not found: $uiTextSource"
    }
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
            $target = Join-Path $pictographic $prompt.imageFileName
            if ($prompt.PSObject.Properties.Name -contains 'dataUrl' -and -not [string]::IsNullOrWhiteSpace([string]$prompt.dataUrl)) {
                Write-DataUrlFile $prompt.dataUrl $target
            }
            else {
                Copy-Source $prompt.source $target
            }
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
            dataUrl = $prompt.dataUrl
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
    appDisplayName = Get-AppDisplayName -Config $config
    sourceConfig = 'QuestionnaireConfigs/' + [System.IO.Path]::GetFileName($ConfigPath)
    sourceRepository = if ($config.sourceRepository) { $config.sourceRepository } else { 'quest-2d-questionnaire-apps' }
    sourceCommit = if ($config.sourceCommit) { $config.sourceCommit } else { '7f0f7c9a40885aa841892b9a680acf45fa45b2d7' }
    maia2SourcePath = if ($config.maia2SourcePath) { $config.maia2SourcePath } else { '' }
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
            startMode = if ($config.chainDefaults.startMode) { $config.chainDefaults.startMode } else { 'unityFirst' }
            callerPackage = if ($config.chainDefaults.callerPackage) { $config.chainDefaults.callerPackage } else { '' }
            callerActivity = if ($config.chainDefaults.callerActivity) { $config.chainDefaults.callerActivity } else { '' }
            nextPackage = if ($config.chainDefaults.nextPackage) { $config.chainDefaults.nextPackage } else { '' }
            nextActivity = if ($config.chainDefaults.nextActivity) { $config.chainDefaults.nextActivity } else { '' }
            questionnaireMode = if ($config.chainDefaults.questionnaireMode) { $config.chainDefaults.questionnaireMode } else { '' }
            questionnaireSequence = if ($config.chainDefaults.PSObject.Properties.Name -contains 'questionnaireSequence' -and $null -ne $config.chainDefaults.questionnaireSequence) {
                @($config.chainDefaults.questionnaireSequence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            } else { @() }
            triggerId = if ($config.chainDefaults.triggerId) { $config.chainDefaults.triggerId } else { '' }
            blockNumber = if ($config.chainDefaults.blockNumber) { $config.chainDefaults.blockNumber } else { '' }
            blockId = if ($config.chainDefaults.blockId) { $config.chainDefaults.blockId } else { '' }
            saveNamespace = if ($config.chainDefaults.saveNamespace) { $config.chainDefaults.saveNamespace } else { '' }
            autoCloseDelayMs = if ($config.chainDefaults.PSObject.Properties.Name -contains 'autoCloseDelayMs' -and $null -ne $config.chainDefaults.autoCloseDelayMs) { [int]$config.chainDefaults.autoCloseDelayMs } else { 2000 }
        }
    } else {
        [ordered]@{
            finishBehavior = 'staySaved'
            startMode = 'unityFirst'
            callerPackage = ''
            callerActivity = ''
            nextPackage = ''
            nextActivity = ''
            questionnaireMode = ''
            questionnaireSequence = @()
            triggerId = ''
            blockNumber = ''
            blockId = ''
            saveNamespace = ''
            autoCloseDelayMs = 2000
        }
    }
}
if ($config.PSObject.Properties.Name -contains 'triggerQuestionnaireMapping' -and $null -ne $config.triggerQuestionnaireMapping) {
    $runtimeConfig.triggerQuestionnaireMapping = $config.triggerQuestionnaireMapping
}
Write-Utf8Text -Target (Join-Path $assets 'QuestionnaireConfig.json') -Text ($runtimeConfig | ConvertTo-Json -Depth 20)
Set-AndroidAppName -DisplayName $runtimeConfig.appDisplayName

[pscustomobject]@{
    AppliedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    AndroidAssets = $assets
    AppDisplayName = $runtimeConfig.appDisplayName
    Status = 'OK'
} | Format-List
