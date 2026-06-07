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
    $ConfigPath = Join-Path $ProjectRoot 'QuestionnaireConfigs\viscereality-maia2.config.json'
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json
$errors = New-Object 'System.Collections.Generic.List[string]'

function Add-ConfigError {
    param([string]$Message)
    $errors.Add($Message) | Out-Null
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

if (-not ($blocks | Where-Object { $_.type -eq 'slider' })) {
    Add-ConfigError "At least one slider block is required for the current native Android questionnaire runtime."
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
    if ($config.chainDefaults.finishBehavior -and $allowedFinishBehaviors -notcontains $config.chainDefaults.finishBehavior) {
        Add-ConfigError "chainDefaults.finishBehavior must be one of: $($allowedFinishBehaviors -join ', ')."
    }
    if ($config.chainDefaults.autoCloseDelayMs -and [int]$config.chainDefaults.autoCloseDelayMs -lt 0) {
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

    $allowedTriggerModes = @('none', 'demographics', 'baseline', 'maia2', 'pictographic', 'slider', 'temporalTracer', 'full')
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

        $enabled = $true
        if ($trigger.PSObject.Properties.Name -contains 'enabled') {
            $enabled = [bool]$trigger.enabled
        }
        if ($enabled -and $mode -ne 'none') {
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
                $source = Resolve-SourcePath $prompt.source
                if (-not (Test-Path -LiteralPath $source)) {
                    Add-ConfigError "Missing pictographic source image: $source"
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

[pscustomobject]@{
    ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    QuestionnaireId = $config.questionnaireId
    QuestionnaireVersion = $config.questionnaireVersion
    Blocks = @($config.blocks).Count
    Status = 'OK'
} | Format-List
