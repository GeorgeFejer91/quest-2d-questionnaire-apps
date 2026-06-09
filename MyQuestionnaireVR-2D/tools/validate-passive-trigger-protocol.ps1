param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string[]]$CatalogPath = @(),
    [string[]]$ApkPath = @(),
    [string[]]$LslCommandPath = @(),
    [string]$OutputPath = ""
)

$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function New-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Detail
    )

    [ordered]@{
        name = $Name
        pass = $Pass
        detail = $Detail
    }
}

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [bool]$Pass,
        [string]$Detail
    )

    $Checks.Add((New-Check -Name $Name -Pass $Pass -Detail $Detail)) | Out-Null
}

function Get-PropertyNamesRecursive {
    param([object]$Value)

    $names = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            foreach ($name in Get-PropertyNamesRecursive -Value $item) {
                $names.Add($name) | Out-Null
            }
        }
        return @($names.ToArray())
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            $names.Add([string]$property.Name) | Out-Null
            foreach ($name in Get-PropertyNamesRecursive -Value $property.Value) {
                $names.Add($name) | Out-Null
            }
        }
    }
    return @($names.ToArray())
}

function Test-ForbiddenStudyLogicFields {
    param(
        [object]$Value,
        [string[]]$ExtraForbidden = @()
    )

    $forbidden = @(
        'recommendedMode',
        'questionnaireMode',
        'questionnaireType',
        'questionnaireSequence',
        'blockId',
        'blockNumber',
        'flowMode',
        'finishBehavior',
        'nextPackage',
        'nextActivity',
        'score',
        'scoring',
        'scoreGroups',
        'scoreFormula',
        'exportBehavior',
        'participantState'
    ) + $ExtraForbidden

    $forbiddenSet = @{}
    foreach ($field in $forbidden) {
        $forbiddenSet[$field.ToLowerInvariant()] = $true
        $forbiddenSet[("mq." + $field).ToLowerInvariant()] = $true
    }

    $matches = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in Get-PropertyNamesRecursive -Value $Value) {
        $clean = ([string]$name).Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) {
            continue
        }
        $key = $clean.ToLowerInvariant()
        if ($forbiddenSet.ContainsKey($key) -or $key -like 'mq.score*') {
            $matches.Add($clean) | Out-Null
        }
    }
    return @($matches.ToArray() | Sort-Object -Unique)
}

function Test-TriggerCatalog {
    param(
        [object]$Catalog,
        [string]$Label,
        [System.Collections.Generic.List[object]]$Checks
    )

    Add-Check -Checks $Checks -Name "$Label schema version" -Pass ([string]$Catalog.schemaVersion -eq 'mq.quest_questionnaire_trigger_catalog.v1') -Detail "schemaVersion=$($Catalog.schemaVersion)"
    Add-Check -Checks $Checks -Name "$Label package present" -Pass (-not [string]::IsNullOrWhiteSpace([string]$Catalog.package)) -Detail "package=$($Catalog.package)"
    Add-Check -Checks $Checks -Name "$Label activity present" -Pass (-not [string]::IsNullOrWhiteSpace([string]$Catalog.activity)) -Detail "activity=$($Catalog.activity)"

    $triggers = @($Catalog.triggers)
    Add-Check -Checks $Checks -Name "$Label trigger count" -Pass ($triggers.Count -gt 0) -Detail "triggerCount=$($triggers.Count)"

    $seen = @{}
    foreach ($trigger in $triggers) {
        $triggerId = ([string]$trigger.triggerId).Trim()
        $validId = -not [string]::IsNullOrWhiteSpace($triggerId) -and $triggerId -match '^[A-Za-z0-9_.:-]+$'
        Add-Check -Checks $Checks -Name "$Label trigger id valid $triggerId" -Pass $validId -Detail "triggerId=$triggerId"
        $key = $triggerId.ToLowerInvariant()
        $duplicate = $seen.ContainsKey($key)
        Add-Check -Checks $Checks -Name "$Label trigger id unique $triggerId" -Pass (-not $duplicate) -Detail "triggerId=$triggerId"
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $seen[$key] = $true
        }
    }

    $forbidden = Test-ForbiddenStudyLogicFields -Value $Catalog
    Add-Check -Checks $Checks -Name "$Label passive-only fields" -Pass ($forbidden.Count -eq 0) -Detail ($(if ($forbidden.Count -eq 0) { 'no questionnaire routing fields found' } else { "forbidden=$($forbidden -join ', ')" }))
}

function Read-ZipTextEntries {
    param(
        [string]$Path,
        [string]$Pattern
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $items = New-Object 'System.Collections.Generic.List[object]'
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match $Pattern) {
                $reader = New-Object System.IO.StreamReader($entry.Open())
                try {
                    $text = $reader.ReadToEnd()
                } finally {
                    $reader.Dispose()
                }
                $items.Add([ordered]@{
                    name = $entry.FullName
                    text = $text
                }) | Out-Null
            }
        }
    } finally {
        $zip.Dispose()
    }
    return @($items.ToArray())
}

function Test-LslCommand {
    param(
        [object]$Command,
        [string]$Label,
        [System.Collections.Generic.List[object]]$Checks
    )

    $commandName = [string]$Command.command
    Add-Check -Checks $Checks -Name "$Label command is trigger" -Pass ($commandName -eq 'trigger') -Detail "command=$commandName"
    Add-Check -Checks $Checks -Name "$Label trigger id present" -Pass (-not [string]::IsNullOrWhiteSpace([string]$Command.triggerId)) -Detail "triggerId=$($Command.triggerId)"
    $allowed = @(
        'schemaVersion',
        'command',
        'sessionId',
        'invocationId',
        'experimentId',
        'scenarioId',
        'trialId',
        'chainId',
        'triggerId',
        'triggerSource',
        'triggerTimestampUtc',
        'triggerTimestampUnixMs'
    )
    $allowedSet = @{}
    foreach ($field in $allowed) {
        $allowedSet[$field] = $true
    }
    $unknown = New-Object 'System.Collections.Generic.List[string]'
    foreach ($property in $Command.PSObject.Properties.Name) {
        if (-not $allowedSet.ContainsKey([string]$property)) {
            $unknown.Add([string]$property) | Out-Null
        }
    }
    $unknownArray = @($unknown.ToArray() | Sort-Object -Unique)
    Add-Check -Checks $Checks -Name "$Label passive trigger allow-list" -Pass ($unknownArray.Count -eq 0) -Detail ($(if ($unknownArray.Count -eq 0) { 'only passive trigger/session/source/timing fields found' } else { "unexpected=$($unknownArray -join ', ')" }))
    $forbidden = Test-ForbiddenStudyLogicFields -Value $Command -ExtraForbidden @('chainPlan', 'chainPlanJson', 'chainPlanBase64', 'chainPlanPath')
    Add-Check -Checks $Checks -Name "$Label passive-only fields" -Pass ($forbidden.Count -eq 0) -Detail ($(if ($forbidden.Count -eq 0) { 'no routing payload found' } else { "forbidden=$($forbidden -join ', ')" }))
}

function Test-LslTriggerSchema {
    param(
        [string]$Path,
        [System.Collections.Generic.List[object]]$Checks
    )

    $exists = Test-Path -LiteralPath $Path
    Add-Check -Checks $Checks -Name 'lsl trigger schema exists' -Pass $exists -Detail $Path
    if (-not $exists) {
        return
    }

    $schema = Read-JsonFile -Path $Path
    $triggerRule = @($schema.allOf) | Where-Object {
        $_.if -and $_.if.properties -and $_.if.properties.command -and [string]$_.if.properties.command.const -eq 'trigger'
    } | Select-Object -First 1
    Add-Check -Checks $Checks -Name 'lsl trigger schema has trigger-specific rule' -Pass ($null -ne $triggerRule) -Detail 'command=trigger has a dedicated passive payload rule.'
    if ($null -eq $triggerRule) {
        return
    }

    $required = @($triggerRule.then.required)
    Add-Check -Checks $Checks -Name 'lsl trigger schema requires triggerId' -Pass ($required -contains 'triggerId') -Detail "required=$($required -join ',')"
    $allowed = @($triggerRule.then.propertyNames.enum)
    $forbiddenAllowed = @(
        'questionnaireMode',
        'questionnaireSequence',
        'questionnaireType',
        'blockId',
        'blockNumber',
        'flowMode',
        'finishBehavior',
        'nextPackage',
        'nextActivity',
        'targetPackage',
        'targetActivity',
        'chainPlan',
        'chainPlanJson',
        'chainPlanBase64',
        'chainPlanPath',
        'commandReplayPlan',
        'exportBehavior',
        'participantState'
    ) | Where-Object { $allowed -contains $_ }
    Add-Check -Checks $Checks -Name 'lsl trigger schema excludes routing fields' -Pass ($forbiddenAllowed.Count -eq 0) -Detail ($(if ($forbiddenAllowed.Count -eq 0) { 'trigger allow-list is passive only' } else { "allowedForbidden=$($forbiddenAllowed -join ', ')" }))
}

function Test-LslBridgeSource {
    param(
        [string]$Path,
        [System.Collections.Generic.List[object]]$Checks
    )

    $exists = Test-Path -LiteralPath $Path
    Add-Check -Checks $Checks -Name 'lsl bridge source exists' -Pass $exists -Detail $Path
    if (-not $exists) {
        return
    }

    $text = Get-Content -LiteralPath $Path -Raw
    Add-Check -Checks $Checks -Name 'lsl bridge defines passive trigger allow-list' -Pass ($text -match 'PASSIVE_TRIGGER_ALLOWED_KEYS') -Detail 'Passive trigger command fields are allow-listed.'
    Add-Check -Checks $Checks -Name 'lsl bridge sanitizes passive trigger commands' -Pass ($text -match 'def\s+sanitize_passive_trigger_command' -and $text -match 'rejected') -Detail 'Passive LSL triggers are rejected when they carry non-passive fields.'
    Add-Check -Checks $Checks -Name 'lsl trigger branch uses sanitizer' -Pass ($text -match 'start_broker\(args,\s*sanitize_passive_trigger_command\(command\),\s*"trigger"\)') -Detail 'command=trigger is sanitized before broker forwarding.'

    $allowedMatch = [regex]::Match($text, 'PASSIVE_TRIGGER_ALLOWED_KEYS\s*=\s*\{(?<body>.*?)\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $allowedBody = if ($allowedMatch.Success) { $allowedMatch.Groups['body'].Value } else { '' }
    $forbiddenAllowed = @(
        'questionnaireMode',
        'questionnaireSequence',
        'questionnaireType',
        'blockId',
        'blockNumber',
        'flowMode',
        'finishBehavior',
        'nextPackage',
        'nextActivity',
        'targetPackage',
        'targetActivity',
        'chainPlan',
        'chainPlanJson',
        'chainPlanBase64',
        'chainPlanPath',
        'commandReplayPlan',
        'exportBehavior',
        'participantState'
    ) | Where-Object { $allowedBody -match ('"' + [regex]::Escape($_) + '"') }
    Add-Check -Checks $Checks -Name 'lsl bridge passive allow-list excludes routing fields' -Pass ($forbiddenAllowed.Count -eq 0) -Detail ($(if ($forbiddenAllowed.Count -eq 0) { 'bridge allow-list is passive only' } else { "allowedForbidden=$($forbiddenAllowed -join ', ')" }))
}

function Test-TransportDecisionDocs {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[object]]$Checks
    )

    $decisionPath = Join-Path $RepoRoot 'docs\trigger-transport-decision-record.md'
    $protocolPath = Join-Path $RepoRoot 'docs\minimal-apk-trigger-protocol.md'
    $guidePath = Join-Path $RepoRoot 'docs\minimal-trigger-integration-guide.md'

    $decisionExists = Test-Path -LiteralPath $decisionPath
    $protocolExists = Test-Path -LiteralPath $protocolPath
    $guideExists = Test-Path -LiteralPath $guidePath

    Add-Check -Checks $Checks -Name 'trigger transport decision record exists' -Pass $decisionExists -Detail $decisionPath
    Add-Check -Checks $Checks -Name 'minimal protocol doc exists' -Pass $protocolExists -Detail $protocolPath
    Add-Check -Checks $Checks -Name 'minimal integration guide exists' -Pass $guideExists -Detail $guidePath

    if ($decisionExists) {
        $decisionText = Get-Content -LiteralPath $decisionPath -Raw
        Add-Check -Checks $Checks -Name 'transport decision makes Android intents default' -Pass (Test-Text -Text $decisionText -Pattern 'Use Android intents as the default transport') -Detail 'Default transport is Android intents, not LSL.'
        Add-Check -Checks $Checks -Name 'transport decision keeps LSL optional' -Pass (Test-Text -Text $decisionText -Pattern 'Use LSL only as an optional marker input adapter') -Detail 'LSL is an adapter into questionnaire-owned trigger handling.'
        Add-Check -Checks $Checks -Name 'transport decision keeps questionnaire authoritative' -Pass (Test-Text -Text $decisionText -Pattern 'The questionnaire APK owns') -Detail 'Questionnaire APK owns study state and routing.'
        Add-Check -Checks $Checks -Name 'transport decision forbids Unity fallback' -Pass (Test-Text -Text $decisionText -Pattern 'must not contain a\s+hard-coded questionnaire package fallback') -Detail 'Public Unity demos depend on questionnaire-supplied receiver extras.'
        Add-Check -Checks $Checks -Name 'transport decision documents native LSL as future advanced' -Pass ((Test-Text -Text $decisionText -Pattern 'Native LSL inside the questionnaire APK is technically possible') -and (Test-Text -Text $decisionText -Pattern 'future/advanced transport')) -Detail 'Native in-APK LSL is documented as possible but not the v2 default.'
        Add-Check -Checks $Checks -Name 'transport decision cites Android and LSL sources' -Pass ((Test-Text -Text $decisionText -Pattern 'developer\.android\.com/guide/components/activities/secure-bal') -and (Test-Text -Text $decisionText -Pattern 'labstreaminglayer\.readthedocs\.io/dev/build_android')) -Detail 'Decision record links primary Android and LSL references.'
    }

    if ($protocolExists) {
        $protocolText = Get-Content -LiteralPath $protocolPath -Raw
        Add-Check -Checks $Checks -Name 'minimal protocol links transport decision' -Pass (Test-Text -Text $protocolText -Pattern 'trigger-transport-decision-record\.md') -Detail 'Protocol doc points readers to the decision record.'
    }

    if ($guideExists) {
        $guideText = Get-Content -LiteralPath $guidePath -Raw
        Add-Check -Checks $Checks -Name 'integration guide links transport decision' -Pass (Test-Text -Text $guideText -Pattern 'trigger-transport-decision-record\.md') -Detail 'Public guide points readers to the decision record.'
    }
}

function Test-PassiveTriggerKit {
    param(
        [string]$ProjectPath,
        [System.Collections.Generic.List[object]]$Checks
    )

    $kitDir = Join-Path $ProjectPath 'tools\unity\passive-trigger-kit'
    $readmePath = Join-Path $kitDir 'README.md'
    $catalogPath = Join-Path $kitDir 'questionnaire-trigger-catalog.template.json'
    $activityPath = Join-Path $kitDir 'QuestQuestionnaireUnityActivity.template.java'
    $manifestPath = Join-Path $kitDir 'AndroidManifest.activity-snippet.xml'

    $kitExists = Test-Path -LiteralPath $kitDir
    Add-Check -Checks $Checks -Name 'passive trigger kit directory exists' -Pass $kitExists -Detail $kitDir
    if (-not $kitExists) {
        return
    }

    Add-Check -Checks $Checks -Name 'passive trigger kit readme exists' -Pass (Test-Path -LiteralPath $readmePath) -Detail $readmePath
    Add-Check -Checks $Checks -Name 'passive trigger kit catalog template exists' -Pass (Test-Path -LiteralPath $catalogPath) -Detail $catalogPath
    Add-Check -Checks $Checks -Name 'passive trigger kit activity template exists' -Pass (Test-Path -LiteralPath $activityPath) -Detail $activityPath
    Add-Check -Checks $Checks -Name 'passive trigger kit manifest snippet exists' -Pass (Test-Path -LiteralPath $manifestPath) -Detail $manifestPath

    if (Test-Path -LiteralPath $readmePath) {
        $readmeText = Get-Content -LiteralPath $readmePath -Raw
        Add-Check -Checks $Checks -Name 'passive trigger kit documents copy bridge' -Pass (Test-Text -Text $readmeText -Pattern 'QuestQuestionnairePassiveTriggerBridge\.cs') -Detail 'Kit points Unity users at the copyable bridge.'
        Add-Check -Checks $Checks -Name 'passive trigger kit keeps questionnaire logic out of Unity' -Pass (Test-Text -Text $readmeText -Pattern 'generated Quest 2D questionnaire\s+APK own all study logic') -Detail 'Kit states questionnaire APK owns study logic.'
        Add-Check -Checks $Checks -Name 'passive trigger kit forbids routing payload' -Pass (Test-Text -Text $readmeText -Pattern 'Do not add questionnaire decisions to Unity') -Detail 'Kit lists forbidden Unity payload fields.'
        Add-Check -Checks $Checks -Name 'passive trigger kit forbids hard-coded fallback' -Pass (Test-Text -Text $readmeText -Pattern 'hard-coded questionnaire package\s+fallbacks') -Detail 'Kit warns against public Unity fallback packages.'
    }

    if (Test-Path -LiteralPath $catalogPath) {
        $catalog = Read-JsonFile -Path $catalogPath
        Test-TriggerCatalog -Catalog $catalog -Label 'passive trigger kit catalog template' -Checks $Checks
    }

    if (Test-Path -LiteralPath $activityPath) {
        $activityText = Get-Content -LiteralPath $activityPath -Raw
        Add-Check -Checks $Checks -Name 'passive trigger kit activity refreshes intent' -Pass ($activityText -match 'extends\s+UnityPlayerGameActivity' -and $activityText -match 'onNewIntent\s*\(' -and $activityText -match 'setIntent\s*\(\s*intent\s*\)') -Detail 'Template activity refreshes currentActivity.getIntent() for singleTop launches.'
    }

    if (Test-Path -LiteralPath $manifestPath) {
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw
        Add-Check -Checks $Checks -Name 'passive trigger kit manifest singleTop' -Pass (Test-Text -Text $manifestText -Pattern 'android:launchMode="singleTop"') -Detail 'Manifest snippet keeps repeated launches on one Unity activity instance.'
        Add-Check -Checks $Checks -Name 'passive trigger kit manifest has no questionnaire package fallback' -Pass (-not (Test-Text -Text $manifestText -Pattern 'org\.questquestionnaire\.questionnaires2d')) -Detail 'Manifest snippet does not target a questionnaire package directly.'
        Add-Check -Checks $Checks -Name 'passive trigger kit manifest has no legacy chain action' -Pass (-not (Test-Text -Text $manifestText -Pattern 'org\.questquestionnaire\.CHAIN_COMMAND')) -Detail 'Public v2 Unity snippet is launched explicitly by the generated questionnaire APK, not through the legacy chain action.'
    }
}

function Test-Text {
    param(
        [string]$Text,
        [string]$Pattern
    )

    return [bool]([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline))
}

function Test-UnityBridgeSource {
    param(
        [string]$Path,
        [string]$Label,
        [bool]$RequireNoRoutingExtras,
        [System.Collections.Generic.List[object]]$Checks
    )

    $exists = Test-Path -LiteralPath $Path
    Add-Check -Checks $Checks -Name "$Label source exists" -Pass $exists -Detail $Path
    if (-not $exists) {
        return
    }

    $text = Get-Content -LiteralPath $Path -Raw
    Add-Check -Checks $Checks -Name "$Label trigger receiver package extra" -Pass (Test-Text $text 'mq\.triggerReceiverPackage') -Detail 'Unity trigger target can be supplied by the questionnaire launch intent.'
    Add-Check -Checks $Checks -Name "$Label trigger receiver activity extra" -Pass (Test-Text $text 'mq\.triggerReceiverActivity') -Detail 'Unity trigger target can be supplied by the questionnaire launch intent.'
    Add-Check -Checks $Checks -Name "$Label trigger receiver action extra" -Pass (Test-Text $text 'mq\.triggerReceiverAction') -Detail 'Unity trigger action can be supplied by the questionnaire launch intent.'
    Add-Check -Checks $Checks -Name "$Label resolves receiver from launch intent" -Pass ((Test-Text $text 'ResolveTriggerReceiver') -and (Test-Text $text 'getIntent')) -Detail 'Bridge reads trigger receiver metadata from the Unity launch intent.'

    if ($RequireNoRoutingExtras) {
        $routingPattern = 'mq\.(questionnaireMode|questionnaireSequence|blockId|blockNumber|finishBehavior|nextPackage|nextActivity|exportBehavior|score)'
        $matches = @([regex]::Matches($text, $routingPattern) | ForEach-Object { $_.Value } | Sort-Object -Unique)
        Add-Check -Checks $Checks -Name "$Label no Unity-side questionnaire routing extras" -Pass ($matches.Count -eq 0) -Detail ($(if ($matches.Count -eq 0) { 'no forbidden routing extras found' } else { "forbidden=$($matches -join ', ')" }))
        $fallbackMatches = @([regex]::Matches($text, 'FallbackQuestionnaire|org\.questquestionnaire\.questionnaires2d|QuestionnairePackage\s*=') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        Add-Check -Checks $Checks -Name "$Label no hard-coded questionnaire fallback" -Pass ($fallbackMatches.Count -eq 0) -Detail ($(if ($fallbackMatches.Count -eq 0) { 'public Unity demo depends on questionnaire-supplied receiver extras only' } else { "fallback=$($fallbackMatches -join ', ')" }))
        Add-Check -Checks $Checks -Name "$Label filters passive metadata" -Pass (($text -match 'PassiveMetadataExtraSet') -and ($text -match 'FilterPassiveMetadata')) -Detail 'Public passive bridge allow-lists outgoing session/source/timing metadata.'
    }
}

$projectFull = (Resolve-Path -LiteralPath $ProjectPath).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $projectFull '..')).Path

if ($CatalogPath.Count -eq 0) {
    $CatalogPath = @(
        (Join-Path $repoRoot 'example-scenario-apk\questionnaire-trigger-catalog.json'),
        (Join-Path $repoRoot 'example-scenario-apk\multi-trigger-demos\2-triggers\questionnaire-trigger-catalog.json'),
        (Join-Path $repoRoot 'example-scenario-apk\multi-trigger-demos\3-triggers\questionnaire-trigger-catalog.json'),
        (Join-Path $repoRoot 'example-scenario-apk\multi-trigger-demos\4-triggers\questionnaire-trigger-catalog.json'),
        (Join-Path $repoRoot 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\StreamingAssets\mq\questionnaire-trigger-catalog.json'),
        (Join-Path $projectFull 'QuestionnaireConfigs\examples\scenario-trigger-catalog.example.json')
    )
}

if ($ApkPath.Count -eq 0) {
    $candidateApk = Join-Path $repoRoot 'example-scenario-apk\unity-project\three-circle-trigger-demo\Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk'
    if (Test-Path -LiteralPath $candidateApk) {
        $ApkPath = @($candidateApk)
    }
}

if ($LslCommandPath.Count -eq 0) {
    $LslCommandPath = @(
        (Join-Path $projectFull 'QuestionnaireConfigs\examples\lsl-trigger.example.json')
    )
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$catalogResults = New-Object 'System.Collections.Generic.List[object]'
$apkResults = New-Object 'System.Collections.Generic.List[object]'
$lslResults = New-Object 'System.Collections.Generic.List[object]'

Test-TransportDecisionDocs `
    -RepoRoot $repoRoot `
    -Checks $checks
Test-PassiveTriggerKit `
    -ProjectPath $projectFull `
    -Checks $checks
Test-LslTriggerSchema `
    -Path (Join-Path $projectFull 'QuestionnaireConfigs\lsl-chain-command.schema.json') `
    -Checks $checks
Test-LslBridgeSource `
    -Path (Join-Path $projectFull 'tools\lsl-chain-bridge.py') `
    -Checks $checks

Test-UnityBridgeSource `
    -Path (Join-Path $projectFull 'tools\unity\QuestQuestionnairePassiveTriggerBridge.cs') `
    -Label 'minimal passive Unity bridge' `
    -RequireNoRoutingExtras $true `
    -Checks $checks
Test-UnityBridgeSource `
    -Path (Join-Path $projectFull 'tools\unity\QuestQuestionnaireChainBridge.cs') `
    -Label 'unity bridge template' `
    -RequireNoRoutingExtras $false `
    -Checks $checks
Test-UnityBridgeSource `
    -Path (Join-Path $repoRoot 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\Scripts\CircleDemoQuestionnaireBridge.cs') `
    -Label 'three-circle demo bridge' `
    -RequireNoRoutingExtras $true `
    -Checks $checks

$circleActivityPath = Join-Path $repoRoot 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\Plugins\Android\QuestQuestionnaireUnityActivity.java'
$circleActivityExists = Test-Path -LiteralPath $circleActivityPath
Add-Check -Checks $checks -Name 'three-circle activity source exists' -Pass $circleActivityExists -Detail $circleActivityPath
if ($circleActivityExists) {
    $circleActivityText = Get-Content -LiteralPath $circleActivityPath -Raw
    Add-Check -Checks $checks -Name 'three-circle activity refreshes singleTop intent' -Pass ($circleActivityText -match 'extends\s+UnityPlayerGameActivity' -and $circleActivityText -match 'onNewIntent\s*\(' -and $circleActivityText -match 'setIntent\s*\(\s*intent\s*\)') -Detail 'Direct Unity launches clear stale questionnaire receiver extras by replacing the current Android intent.'
}

$circleManifestPath = Join-Path $repoRoot 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\Plugins\Android\AndroidManifest.xml'
$circleManifestExists = Test-Path -LiteralPath $circleManifestPath
Add-Check -Checks $checks -Name 'three-circle manifest exists' -Pass $circleManifestExists -Detail $circleManifestPath
if ($circleManifestExists) {
    $circleManifestText = Get-Content -LiteralPath $circleManifestPath -Raw
    Add-Check -Checks $checks -Name 'three-circle manifest uses intent-refreshing activity' -Pass ($circleManifestText -match 'org\.questquestionnaire\.circletriggerdemo\.QuestQuestionnaireUnityActivity' -and $circleManifestText -match 'android:launchMode="singleTop"') -Detail 'Public Unity demo launcher targets the activity that refreshes the current intent.'
    Add-Check -Checks $checks -Name 'three-circle manifest has no legacy chain action' -Pass ($circleManifestText -notmatch 'org\.questquestionnaire\.CHAIN_COMMAND') -Detail 'Public three-circle Unity demo is an immersive stimulus APK launched explicitly by the questionnaire APK.'
}

foreach ($path in $CatalogPath) {
    $exists = Test-Path -LiteralPath $path
    Add-Check -Checks $checks -Name "catalog exists $path" -Pass $exists -Detail $path
    if (-not $exists) {
        continue
    }
    $catalog = Read-JsonFile -Path $path
    Test-TriggerCatalog -Catalog $catalog -Label "catalog $(Split-Path -Leaf $path)" -Checks $checks
    $catalogResults.Add([ordered]@{
        path = $path
        triggerCount = @($catalog.triggers).Count
        package = [string]$catalog.package
        activity = [string]$catalog.activity
    }) | Out-Null
}

foreach ($path in $ApkPath) {
    $exists = Test-Path -LiteralPath $path
    Add-Check -Checks $checks -Name "apk exists $path" -Pass $exists -Detail $path
    if (-not $exists) {
        continue
    }
    $entries = @(Read-ZipTextEntries -Path $path -Pattern 'questionnaire-trigger-catalog\.json$')
    Add-Check -Checks $checks -Name "apk trigger catalog count $(Split-Path -Leaf $path)" -Pass ($entries.Count -eq 1) -Detail "catalogCount=$($entries.Count)"
    foreach ($entry in $entries) {
        $catalog = $entry.text | ConvertFrom-Json
        Test-TriggerCatalog -Catalog $catalog -Label "apk $(Split-Path -Leaf $path):$($entry.name)" -Checks $checks
        if ((Split-Path -Leaf $path) -eq 'QuestQuestionnaireThreeCircleTriggerDemo.apk') {
            Add-Check -Checks $checks -Name "apk three-circle catalog uses intent-refreshing activity" -Pass ([string]$catalog.activity -eq 'org.questquestionnaire.circletriggerdemo.QuestQuestionnaireUnityActivity') -Detail "activity=$($catalog.activity)"
        }
        $apkResults.Add([ordered]@{
            path = $path
            entry = $entry.name
            triggerCount = @($catalog.triggers).Count
            package = [string]$catalog.package
            activity = [string]$catalog.activity
        }) | Out-Null
    }
}

foreach ($path in $LslCommandPath) {
    $exists = Test-Path -LiteralPath $path
    Add-Check -Checks $checks -Name "lsl command exists $path" -Pass $exists -Detail $path
    if (-not $exists) {
        continue
    }
    $command = Read-JsonFile -Path $path
    Test-LslCommand -Command $command -Label "lsl $(Split-Path -Leaf $path)" -Checks $checks
    $lslResults.Add([ordered]@{
        path = $path
        command = [string]$command.command
        triggerId = [string]$command.triggerId
    }) | Out-Null
}

$checkArray = @($checks.ToArray())
$failed = @($checkArray | Where-Object { -not $_.pass })
$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.passive-trigger-protocol.validation.v1'
    status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
    checkCount = $checkArray.Count
    failedCount = $failed.Count
    catalogs = @($catalogResults.ToArray())
    apks = @($apkResults.ToArray())
    lslCommands = @($lslResults.ToArray())
    checks = $checkArray
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $runId = Get-Date -Format 'yyyyMMddTHHmmssZ'
    $folder = Join-Path $projectFull "artifacts\passive-trigger-protocol\$runId"
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $OutputPath = Join-Path $folder 'passive-trigger-protocol-summary.json'
} else {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    Status = $summary.status
    Checks = $summary.checkCount
    Failed = $summary.failedCount
    Summary = $OutputPath
}

if ($failed.Count -gt 0) {
    throw "Passive trigger protocol validation failed. See $OutputPath"
}
