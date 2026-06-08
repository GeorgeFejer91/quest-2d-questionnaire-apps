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

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json
$errors = New-Object 'System.Collections.Generic.List[string]'
$warnings = New-Object 'System.Collections.Generic.List[string]'

function Add-ConfigError {
    param([string]$Message)
    $errors.Add($Message) | Out-Null
}

function Add-ConfigWarning {
    param([string]$Message)
    $warnings.Add($Message) | Out-Null
}

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

function Count-NonEmptyLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-ConfigError "Missing text file: $Path"
        return 0
    }

    return @((Get-Content -LiteralPath $Path -Encoding UTF8) | Where-Object { $_.Trim().Length -gt 0 }).Count
}

function Count-JsonArrayItems {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-ConfigError "Missing JSON file: $Path"
        return 0
    }

    try {
        return @((Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json)).Count
    }
    catch {
        Add-ConfigError "Invalid JSON item file: $Path :: $($_.Exception.Message)"
        return 0
    }
}

foreach ($required in @('schemaVersion', 'questionnaireId', 'questionnaireVersion', 'blocks', 'exports')) {
    if (-not ($config.PSObject.Properties.Name -contains $required)) {
        Add-ConfigError "Missing required config field: $required"
    }
}

if ($config.schemaVersion -ne 'my-questionnaire-vr.config.v1') {
    Add-ConfigError "Unsupported schemaVersion: $($config.schemaVersion)"
}

$blocks = @($config.blocks)
$languages = @($config.languages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($languages.Count -eq 0) {
    $languages = @('English', 'Deutsch')
}

if (-not ($blocks | Where-Object { $_.id -eq 'demographics' -and $_.type -eq 'demographics' })) {
    Add-ConfigError "Missing required demographics block."
}

if (-not ($blocks | Where-Object { $_.id -eq 'end' -and $_.type -eq 'blackScreen' })) {
    Add-ConfigError "Missing required final blackScreen block with id end."
}

if ($blocks.Count -gt 0) {
    if ($blocks[0].type -ne 'demographics') {
        Add-ConfigError "The first block should be demographics."
    }

    if ($blocks[$blocks.Count - 1].type -ne 'blackScreen') {
        Add-ConfigError "The final block should be blackScreen."
    }
}

if ($config.PSObject.Properties.Name -contains 'chainDefaults' -and $null -ne $config.chainDefaults) {
    $allowedFinishBehaviors = @('resumeCaller', 'openNext', 'staySaved')
    $allowedStartModes = @('unityFirst', 'questionnaireFirst')
    $allowedDefaultQuestionnaireModes = @('', 'none', 'demographics', 'baseline', 'maia2', 'pictographic', 'slider', 'full')
    $allowedQuestionnaireModules = @('demographics', 'maia2', 'pictographic', 'slider')
    $finishBehavior = if ($config.chainDefaults.finishBehavior) { [string]$config.chainDefaults.finishBehavior } else { 'staySaved' }
    $startMode = if ($config.chainDefaults.startMode) { [string]$config.chainDefaults.startMode } else { 'unityFirst' }
    $questionnaireMode = if ($config.chainDefaults.questionnaireMode) { [string]$config.chainDefaults.questionnaireMode } else { '' }
    $questionnaireSequence = @($config.chainDefaults.questionnaireSequence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($config.chainDefaults.finishBehavior -and $allowedFinishBehaviors -notcontains $config.chainDefaults.finishBehavior) {
        Add-ConfigError "chainDefaults.finishBehavior must be one of: $($allowedFinishBehaviors -join ', ')."
    }
    if ($allowedStartModes -notcontains $startMode) {
        Add-ConfigError "chainDefaults.startMode must be unityFirst or questionnaireFirst when present."
    }
    if ($allowedDefaultQuestionnaireModes -notcontains $questionnaireMode) {
        Add-ConfigError "chainDefaults.questionnaireMode must be one of: none, demographics, baseline, maia2, pictographic, slider, full, or blank."
    }
    foreach ($module in $questionnaireSequence) {
        if ($allowedQuestionnaireModules -notcontains [string]$module) {
            Add-ConfigError "chainDefaults.questionnaireSequence contains unsupported module: $module."
        }
    }
    if ($config.chainDefaults.blockNumber -and -not ([string]$config.chainDefaults.blockNumber -match '^\d{3}$')) {
        Add-ConfigError "chainDefaults.blockNumber must be a three-digit block number when present."
    }
    if ($finishBehavior -eq 'openNext' -and -not $config.chainDefaults.nextPackage) {
        Add-ConfigError "chainDefaults.finishBehavior=openNext requires chainDefaults.nextPackage."
    }
    if ($startMode -eq 'questionnaireFirst') {
        if ($finishBehavior -ne 'openNext') {
            Add-ConfigError "chainDefaults.startMode=questionnaireFirst requires chainDefaults.finishBehavior=openNext."
        }
        if ($questionnaireSequence.Count -eq 0 -and ($questionnaireMode -eq '' -or $questionnaireMode -eq 'none')) {
            Add-ConfigWarning "Block 1 has no questionnaire elements. This is allowed for V2 but should be intentional."
        }
        if (-not $config.chainDefaults.triggerId) {
            Add-ConfigError "chainDefaults.startMode=questionnaireFirst requires chainDefaults.triggerId so Unity receives the completed first-block handoff."
        }
        if (-not $config.chainDefaults.nextPackage) {
            Add-ConfigError "chainDefaults.startMode=questionnaireFirst requires the Unity APK package in chainDefaults.nextPackage."
        }
    }
    if ($config.chainDefaults.PSObject.Properties.Name -contains 'autoCloseDelayMs' -and $null -ne $config.chainDefaults.autoCloseDelayMs -and [int]$config.chainDefaults.autoCloseDelayMs -lt 0) {
        Add-ConfigError "chainDefaults.autoCloseDelayMs must be 0 or greater."
    }
}

if ($config.PSObject.Properties.Name -contains 'triggerQuestionnaireMapping' -and $null -ne $config.triggerQuestionnaireMapping) {
    $mapping = $config.triggerQuestionnaireMapping
    if ($mapping.schemaVersion -and $mapping.schemaVersion -ne 'mq.quest_questionnaire_trigger_mapping.v1') {
        Add-ConfigError "triggerQuestionnaireMapping.schemaVersion must be mq.quest_questionnaire_trigger_mapping.v1."
    }

    if (-not ($mapping.PSObject.Properties.Name -contains 'triggers')) {
        Add-ConfigError "triggerQuestionnaireMapping.triggers is required when triggerQuestionnaireMapping is present."
    }

    foreach ($warning in @($mapping.passiveTriggerWarnings)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$warning)) {
            Add-ConfigWarning ([string]$warning)
        }
    }

    $allowedTriggerModes = @('none', 'demographics', 'baseline', 'maia2', 'pictographic', 'slider', 'temporalTracer', 'full')
    $allowedQuestionnaireModules = @('demographics', 'maia2', 'pictographic', 'slider')
    $seenTriggers = @{}
    foreach ($trigger in @($mapping.triggers)) {
        $triggerId = [string]$trigger.triggerId
        $triggerId = $triggerId.Trim()
        if ([string]::IsNullOrWhiteSpace($triggerId)) {
            Add-ConfigError "A trigger mapping is missing triggerId."
            continue
        }

        $key = $triggerId.ToLowerInvariant()
        if ($seenTriggers.ContainsKey($key)) {
            Add-ConfigError "Trigger $triggerId is mapped more than once."
        }
        $seenTriggers[$key] = $true

        $mode = [string]$trigger.questionnaireMode
        if ([string]::IsNullOrWhiteSpace($mode)) {
            $mode = 'none'
        }
        if ($allowedTriggerModes -notcontains $mode) {
            Add-ConfigError "Trigger $triggerId uses unsupported questionnaireMode $mode."
        }
        $triggerSequence = @($trigger.questionnaireSequence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        foreach ($module in $triggerSequence) {
            if ($allowedQuestionnaireModules -notcontains [string]$module) {
                Add-ConfigError "Trigger $triggerId questionnaireSequence contains unsupported module: $module."
            }
        }

        if ($trigger.PSObject.Properties.Name -contains 'sourceRecommendedMode' -and -not [string]::IsNullOrWhiteSpace([string]$trigger.sourceRecommendedMode) -and [string]$trigger.sourceRecommendedMode -ne 'none') {
            Add-ConfigWarning "Trigger $triggerId came from a Unity catalog with source recommendedMode=$($trigger.sourceRecommendedMode); V2 should keep questionnaire assignment in the 2D questionnaire protocol instead."
        }
        if ($trigger.PSObject.Properties.Name -contains 'sourceStudyLogicFields') {
            $fields = @($trigger.sourceStudyLogicFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($fields.Count -gt 0) {
                Add-ConfigWarning "Trigger $triggerId source catalog includes study-logic fields ($($fields -join ', ')); Unity should emit passive trigger IDs only."
            }
        }

        $enabled = $true
        if ($trigger.PSObject.Properties.Name -contains 'enabled') {
            $enabled = [bool]$trigger.enabled
        }
        if ($enabled -and ($mode -ne 'none' -or $triggerSequence.Count -gt 0)) {
            if ([string]::IsNullOrWhiteSpace([string]$trigger.blockId)) {
                Add-ConfigError "Trigger $triggerId needs a blockId."
            }
            if (-not ([string]$trigger.blockNumber -match '^\d{3}$')) {
                Add-ConfigError "Trigger $triggerId needs a three-digit blockNumber."
            }
        }

        if ($trigger.PSObject.Properties.Name -contains 'autoCloseDelayMs' -and $null -ne $trigger.autoCloseDelayMs) {
            if ([int]$trigger.autoCloseDelayMs -lt 0) {
                Add-ConfigError "Trigger $triggerId autoCloseDelayMs must be 0 or greater."
            }
        }
    }
}

foreach ($block in $blocks) {
    switch ($block.type) {
        'demographics' {
            if ($block.id -ne 'demographics') {
                Add-ConfigError "Demographics block id should be demographics."
            }
        }
        'likert' {
            if ($block.id -ne 'maia2') {
                Add-ConfigError "Only the MAIA-2 likert block is supported in this runtime; unsupported likert block id: $($block.id)."
            }

            if ($block.min -ne 0 -or $block.max -ne 5) {
                Add-ConfigError "Likert block $($block.id) should use a 0..5 range."
            }

            $count = 0
            if ($block.PSObject.Properties.Name -contains 'items') {
                $count = @($block.items).Count
            }
            elseif ($block.source) {
                $count = Count-JsonArrayItems (Resolve-SourcePath $block.source)
            }
            else {
                Add-ConfigError "Likert block $($block.id) must define items or source."
            }

            if ($block.expectedItemCount -and $count -ne [int]$block.expectedItemCount) {
                Add-ConfigError "Likert block $($block.id) expected $($block.expectedItemCount) items, found $count."
            }

            if ($block.id -eq 'maia2' -and @($block.scoreGroups).Count -ne 8) {
                Add-ConfigError "MAIA-2 block should define 8 score groups."
            }
        }
        'pictographic' {
            if (@($block.prompts).Count -lt 1) {
                Add-ConfigError "Pictographic block should define at least 1 prompt when included."
            }

            $expectedChoicesByImage = @{
                '1.PerceivedBodyBoundariesScale.png' = @('A', 'B', 'C', 'D', 'E', 'F', 'G')
                '2.SpatialFrameReferenceContinuum.png' = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H')
                '3.SmallSelf.png' = @('A', 'B', 'C', 'D', 'E', 'F', 'G')
            }

            foreach ($prompt in @($block.prompts)) {
                $hasDataUrl = $prompt.PSObject.Properties.Name -contains 'dataUrl' -and -not [string]::IsNullOrWhiteSpace([string]$prompt.dataUrl)
                if ($hasDataUrl) {
                    if (-not ([string]$prompt.dataUrl -match '^data:image/png;base64,')) {
                        Add-ConfigError "Pictographic prompt $($prompt.id) dataUrl must be a PNG data URL."
                    }
                }
                else {
                    $source = Resolve-SourcePath $prompt.source
                    if (-not (Test-Path -LiteralPath $source)) {
                        Add-ConfigError "Missing pictographic source image: $source"
                    }
                }

                if ($expectedChoicesByImage.ContainsKey($prompt.imageFileName)) {
                    $choices = @($prompt.choices)
                    $expectedChoices = @($expectedChoicesByImage[$prompt.imageFileName])
                    if ((Compare-Object -ReferenceObject $expectedChoices -DifferenceObject $choices -SyncWindow 0).Count -gt 0) {
                        Add-ConfigError "Pictographic prompt $($prompt.id) choices should be $($expectedChoices -join ','); found $($choices -join ',')."
                    }
                }
            }
        }
        'slider' {
            if ($block.min -ne 0 -or $block.max -ne 100 -or -not $block.wholeNumbers) {
                Add-ConfigError "Slider block $($block.id) should use whole-number 0..100 scores."
            }

            foreach ($language in $languages) {
                $languageBlock = $block.languages.$language
                if ($null -eq $languageBlock) {
                    Add-ConfigError "Slider block $($block.id) missing language: $language"
                    continue
                }

                $count = 0
                if ($languageBlock.PSObject.Properties.Name -contains 'items') {
                    $count = @($languageBlock.items).Count
                }
                elseif ($languageBlock.source) {
                    $count = Count-NonEmptyLines (Resolve-SourcePath $languageBlock.source)
                }
                else {
                    Add-ConfigError "Slider block $($block.id) language $language must define items or source."
                }

                if ($block.expectedItemCount -and $count -ne [int]$block.expectedItemCount) {
                    Add-ConfigError "Slider block $($block.id) language $language expected $($block.expectedItemCount) items, found $count."
                }
            }
        }
        'blackScreen' { }
        default {
            Add-ConfigError "Unsupported block type: $($block.type)"
        }
    }
}

if ($errors.Count -gt 0) {
    throw ($errors -join [Environment]::NewLine)
}

foreach ($warning in @($warnings.ToArray())) {
    Write-Warning $warning
}

[pscustomobject]@{
    ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    QuestionnaireId = $config.questionnaireId
    QuestionnaireVersion = $config.questionnaireVersion
    Blocks = @($config.blocks).Count
    WarningCount = $warnings.Count
    Warnings = @($warnings.ToArray())
    Status = 'OK'
} | Format-List
