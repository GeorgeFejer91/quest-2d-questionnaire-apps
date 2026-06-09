param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory = $true)]
    [string]$QuestionnaireConfig,
    [Parameter(Mandatory = $true)]
    [string]$UnityApk,
    [string]$OutputPath = "",
    [string]$Aapt = ""
)

$ErrorActionPreference = 'Stop'

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [bool]$Pass,
        [string]$Detail,
        [string]$Level = 'error'
    )

    $Checks.Add([ordered]@{
        name = $Name
        pass = $Pass
        detail = $Detail
        level = $Level
    }) | Out-Null
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-Prop {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-PropertyNamesRecursive {
    param([object]$Value)

    $names = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Value) { return @() }
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
    param([object]$Value)

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
    )
    $forbiddenSet = @{}
    foreach ($field in $forbidden) {
        $forbiddenSet[$field.ToLowerInvariant()] = $true
        $forbiddenSet[("mq." + $field).ToLowerInvariant()] = $true
    }

    $matches = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in Get-PropertyNamesRecursive -Value $Value) {
        $clean = ([string]$name).Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        $key = $clean.ToLowerInvariant()
        if ($forbiddenSet.ContainsKey($key) -or $key -like 'mq.score*') {
            $matches.Add($clean) | Out-Null
        }
    }
    return @($matches.ToArray() | Sort-Object -Unique)
}

function Read-ZipTextEntries {
    param([string]$Path, [string]$Pattern)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $items = New-Object 'System.Collections.Generic.List[object]'
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
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

function Resolve-AaptTool {
    param([string]$Requested, [string]$ProjectPath)

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (Test-Path -LiteralPath $Requested) { return (Resolve-Path -LiteralPath $Requested).Path }
        throw "aapt/aapt2 not found: $Requested"
    }

    $candidateRoots = New-Object 'System.Collections.Generic.List[string]'
    $localProperties = Join-Path $ProjectPath 'local.properties'
    if (Test-Path -LiteralPath $localProperties) {
        $sdkLine = Get-Content -LiteralPath $localProperties | Where-Object { $_ -like 'sdk.dir=*' } | Select-Object -First 1
        if ($sdkLine) {
            $candidateRoots.Add(($sdkLine -replace '^sdk.dir=', '').Replace('/', '\')) | Out-Null
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) { $candidateRoots.Add($env:ANDROID_HOME) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) { $candidateRoots.Add($env:ANDROID_SDK_ROOT) | Out-Null }
    $defaultSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $candidateRoots.Add($defaultSdk) | Out-Null }

    foreach ($root in @($candidateRoots.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $tool = Get-ChildItem -LiteralPath (Join-Path $root 'build-tools') -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('aapt2.exe', 'aapt.exe') } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($tool) { return $tool.FullName }
    }

    $pathTool = Get-Command aapt2.exe,aapt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathTool) { return $pathTool.Source }
    return ''
}

function Get-ApkBadging {
    param([string]$Apk, [string]$AaptPath)

    if ([string]::IsNullOrWhiteSpace($AaptPath)) {
        return [ordered]@{
            status = 'skipped'
            package = ''
            activity = ''
            raw = ''
        }
    }

    $output = & $AaptPath dump badging $Apk 2>&1
    $exitCode = $LASTEXITCODE
    $text = (@($output) -join "`n")
    if ($exitCode -ne 0) {
        return [ordered]@{
            status = 'failed'
            package = ''
            activity = ''
            raw = $text
        }
    }

    $package = if ($text -match "package:\s+name='([^']+)'") { $Matches[1] } else { '' }
    $activity = if ($text -match "launchable-activity:\s+name='([^']+)'") { $Matches[1] } else { '' }
    return [ordered]@{
        status = 'pass'
        package = $package
        activity = $activity
        raw = $text
    }
}

function Get-TriggerIds {
    param([object[]]$Items)
    return @($Items | ForEach-Object { [string](Get-Prop -Object $_ -Name 'triggerId' -Default '') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$projectFull = (Resolve-Path -LiteralPath $ProjectPath).Path
$configFull = (Resolve-Path -LiteralPath $QuestionnaireConfig).Path
$unityApkFull = (Resolve-Path -LiteralPath $UnityApk).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $runId = 'two-apk-pair-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $outputDir = Join-Path $projectFull "artifacts\two-apk-pair\$runId"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $OutputPath = Join-Path $outputDir 'two-apk-pair-summary.json'
} else {
    $outputDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
    if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$config = Read-JsonFile -Path $configFull
$entries = @(Read-ZipTextEntries -Path $unityApkFull -Pattern 'questionnaire-trigger-catalog\.json$')

Add-Check -Checks $checks -Name 'questionnaire config exists' -Pass (Test-Path -LiteralPath $configFull) -Detail $configFull
Add-Check -Checks $checks -Name 'unity apk exists' -Pass (Test-Path -LiteralPath $unityApkFull) -Detail $unityApkFull
Add-Check -Checks $checks -Name 'unity apk has exactly one trigger catalog' -Pass ($entries.Count -eq 1) -Detail "catalogCount=$($entries.Count)"

$catalog = $null
$catalogEntry = ''
if ($entries.Count -eq 1) {
    $catalogEntry = [string]$entries[0].name
    $catalog = $entries[0].text | ConvertFrom-Json
}

Add-Check -Checks $checks -Name 'config schema version' -Pass ([string](Get-Prop -Object $config -Name 'schemaVersion') -eq 'my-questionnaire-vr.config.v1') -Detail "schemaVersion=$(Get-Prop -Object $config -Name 'schemaVersion')"
Add-Check -Checks $checks -Name 'questionnaire-first start mode' -Pass ([string](Get-Prop -Object (Get-Prop -Object $config -Name 'chainDefaults') -Name 'startMode') -eq 'questionnaireFirst') -Detail "startMode=$(Get-Prop -Object (Get-Prop -Object $config -Name 'chainDefaults') -Name 'startMode')"

if ($catalog) {
    $catalogPackage = [string](Get-Prop -Object $catalog -Name 'package')
    $catalogActivity = [string](Get-Prop -Object $catalog -Name 'activity')
    $catalogTriggers = @((Get-Prop -Object $catalog -Name 'triggers' -Default @()))
    $catalogTriggerIds = @(Get-TriggerIds -Items $catalogTriggers)
    $duplicateCatalogIds = @($catalogTriggerIds | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    $forbiddenCatalogFields = @(Test-ForbiddenStudyLogicFields -Value $catalog)

    Add-Check -Checks $checks -Name 'catalog schema version' -Pass ([string](Get-Prop -Object $catalog -Name 'schemaVersion') -eq 'mq.quest_questionnaire_trigger_catalog.v1') -Detail "schemaVersion=$(Get-Prop -Object $catalog -Name 'schemaVersion')"
    Add-Check -Checks $checks -Name 'catalog package present' -Pass (-not [string]::IsNullOrWhiteSpace($catalogPackage)) -Detail "package=$catalogPackage"
    Add-Check -Checks $checks -Name 'catalog activity present' -Pass (-not [string]::IsNullOrWhiteSpace($catalogActivity)) -Detail "activity=$catalogActivity"
    Add-Check -Checks $checks -Name 'catalog trigger ids present' -Pass ($catalogTriggerIds.Count -gt 0 -and $catalogTriggerIds.Count -eq $catalogTriggers.Count) -Detail "triggerCount=$($catalogTriggers.Count)"
    Add-Check -Checks $checks -Name 'catalog trigger ids unique' -Pass ($duplicateCatalogIds.Count -eq 0) -Detail ($(if ($duplicateCatalogIds.Count -eq 0) { 'unique' } else { "duplicates=$($duplicateCatalogIds -join ',')" }))
    Add-Check -Checks $checks -Name 'catalog contains passive fields only' -Pass ($forbiddenCatalogFields.Count -eq 0) -Detail ($(if ($forbiddenCatalogFields.Count -eq 0) { 'no questionnaire routing fields in Unity catalog' } else { "forbidden=$($forbiddenCatalogFields -join ',')" }))

    $chainDefaults = Get-Prop -Object $config -Name 'chainDefaults'
    Add-Check -Checks $checks -Name 'chain default next package matches Unity catalog' -Pass ([string](Get-Prop -Object $chainDefaults -Name 'nextPackage') -eq $catalogPackage) -Detail "config=$((Get-Prop -Object $chainDefaults -Name 'nextPackage')); catalog=$catalogPackage"
    Add-Check -Checks $checks -Name 'chain default next activity matches Unity catalog' -Pass ([string](Get-Prop -Object $chainDefaults -Name 'nextActivity') -eq $catalogActivity) -Detail "config=$((Get-Prop -Object $chainDefaults -Name 'nextActivity')); catalog=$catalogActivity"

    $registry = Get-Prop -Object $config -Name 'experimentBlockRegistry'
    $registryScenario = Get-Prop -Object $registry -Name 'scenario'
    $registryTarget = Get-Prop -Object $registry -Name 'targetApp'
    Add-Check -Checks $checks -Name 'registry scenario package matches Unity catalog' -Pass ([string](Get-Prop -Object $registryScenario -Name 'package') -eq $catalogPackage) -Detail "registry=$((Get-Prop -Object $registryScenario -Name 'package')); catalog=$catalogPackage"
    Add-Check -Checks $checks -Name 'registry scenario activity matches Unity catalog' -Pass ([string](Get-Prop -Object $registryScenario -Name 'activity') -eq $catalogActivity) -Detail "registry=$((Get-Prop -Object $registryScenario -Name 'activity')); catalog=$catalogActivity"
    Add-Check -Checks $checks -Name 'registry target package matches Unity catalog' -Pass ([string](Get-Prop -Object $registryTarget -Name 'package') -eq $catalogPackage) -Detail "target=$((Get-Prop -Object $registryTarget -Name 'package')); catalog=$catalogPackage"
    Add-Check -Checks $checks -Name 'registry target activity matches Unity catalog' -Pass ([string](Get-Prop -Object $registryTarget -Name 'activity') -eq $catalogActivity) -Detail "target=$((Get-Prop -Object $registryTarget -Name 'activity')); catalog=$catalogActivity"

    $sourceCatalog = Get-Prop -Object $registry -Name 'sourceTriggerCatalog'
    Add-Check -Checks $checks -Name 'registry source trigger count matches catalog' -Pass ([int](Get-Prop -Object $sourceCatalog -Name 'triggerCount' -Default -1) -eq $catalogTriggerIds.Count) -Detail "registry=$((Get-Prop -Object $sourceCatalog -Name 'triggerCount')); catalog=$($catalogTriggerIds.Count)"

    $mapping = Get-Prop -Object $config -Name 'triggerQuestionnaireMapping'
    $mappingTriggers = @((Get-Prop -Object $mapping -Name 'triggers' -Default @()))
    $mappingTriggerIds = @(Get-TriggerIds -Items $mappingTriggers)
    $returnMappingIds = @($mappingTriggerIds | Where-Object { $_ -ne 'study_start_block_1' })
    $missingMappedIds = @($catalogTriggerIds | Where-Object { $returnMappingIds -notcontains $_ })
    $extraMappedIds = @($returnMappingIds | Where-Object { $catalogTriggerIds -notcontains $_ })
    Add-Check -Checks $checks -Name 'trigger mapping package matches Unity catalog' -Pass ([string](Get-Prop -Object $mapping -Name 'scenarioPackage') -eq $catalogPackage) -Detail "mapping=$((Get-Prop -Object $mapping -Name 'scenarioPackage')); catalog=$catalogPackage"
    Add-Check -Checks $checks -Name 'trigger mapping activity matches Unity catalog' -Pass ([string](Get-Prop -Object $mapping -Name 'scenarioActivity') -eq $catalogActivity) -Detail "mapping=$((Get-Prop -Object $mapping -Name 'scenarioActivity')); catalog=$catalogActivity"
    Add-Check -Checks $checks -Name 'every Unity trigger maps to questionnaire-owned return block' -Pass ($missingMappedIds.Count -eq 0) -Detail ($(if ($missingMappedIds.Count -eq 0) { "mapped=$($catalogTriggerIds.Count)" } else { "missing=$($missingMappedIds -join ',')" }))
    Add-Check -Checks $checks -Name 'no extra return mappings absent from Unity catalog' -Pass ($extraMappedIds.Count -eq 0) -Detail ($(if ($extraMappedIds.Count -eq 0) { 'no extras' } else { "extra=$($extraMappedIds -join ',')" }))

    $registryBlocks = @((Get-Prop -Object $registry -Name 'blocks' -Default @()))
    $frontDoorBlocks = @($registryBlocks | Where-Object { [string](Get-Prop -Object (Get-Prop -Object $_ -Name 'trigger') -Name 'type') -eq 'questionnaireFrontDoor' })
    $returnBlocks = @($registryBlocks | Where-Object { [string](Get-Prop -Object (Get-Prop -Object $_ -Name 'trigger') -Name 'type') -eq 'apkManifestTrigger' })
    $returnBlockTriggerIds = @(Get-TriggerIds -Items @($returnBlocks | ForEach-Object { Get-Prop -Object $_ -Name 'trigger' }))
    $missingReturnBlocks = @($catalogTriggerIds | Where-Object { $returnBlockTriggerIds -notcontains $_ })
    Add-Check -Checks $checks -Name 'registry has one questionnaire front-door block' -Pass ($frontDoorBlocks.Count -eq 1) -Detail "frontDoorBlocks=$($frontDoorBlocks.Count)"
    Add-Check -Checks $checks -Name 'registry has one return block per Unity trigger' -Pass ($returnBlocks.Count -eq $catalogTriggerIds.Count -and $missingReturnBlocks.Count -eq 0) -Detail "returnBlocks=$($returnBlocks.Count); catalogTriggers=$($catalogTriggerIds.Count); missing=$($missingReturnBlocks -join ',')"

    $aaptPath = Resolve-AaptTool -Requested $Aapt -ProjectPath $projectFull
    $badging = Get-ApkBadging -Apk $unityApkFull -AaptPath $aaptPath
    Add-Check -Checks $checks -Name 'apk badging readable' -Pass ([string]$badging.status -eq 'pass') -Detail "status=$($badging.status); aapt=$aaptPath" -Level $(if ([string]$badging.status -eq 'skipped') { 'warn' } else { 'error' })
    if ([string]$badging.status -eq 'pass') {
        Add-Check -Checks $checks -Name 'apk package matches trigger catalog' -Pass ([string]$badging.package -eq $catalogPackage) -Detail "badging=$($badging.package); catalog=$catalogPackage"
        Add-Check -Checks $checks -Name 'apk launch activity matches trigger catalog' -Pass ([string]$badging.activity -eq $catalogActivity) -Detail "badging=$($badging.activity); catalog=$catalogActivity"
    }
}

$checkArray = @($checks.ToArray())
$failed = @($checkArray | Where-Object { -not $_.pass -and [string]$_.level -ne 'warn' })
$warnings = @($checkArray | Where-Object { -not $_.pass -and [string]$_.level -eq 'warn' })
$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.two_apk_pair.validation.v1'
    status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
    proofBoundary = 'No-headset pair audit only. Live Quest install, participant launch, Unity focus, passive trigger return, and export pull remain separate physical gates.'
    questionnaireConfig = $configFull
    unityApk = $unityApkFull
    catalogEntry = $catalogEntry
    catalog = if ($catalog) {
        [ordered]@{
            package = [string](Get-Prop -Object $catalog -Name 'package')
            activity = [string](Get-Prop -Object $catalog -Name 'activity')
            triggerCount = @((Get-Prop -Object $catalog -Name 'triggers' -Default @())).Count
        }
    } else { $null }
    checkCount = $checkArray.Count
    failedCount = $failed.Count
    warningCount = $warnings.Count
    checks = $checkArray
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    Status = $summary.status
    Checks = $summary.checkCount
    Failed = $summary.failedCount
    Warnings = $summary.warningCount
    Summary = $OutputPath
    ProofBoundary = $summary.proofBoundary
}

if ($failed.Count -gt 0) {
    throw "Two-APK pair validation failed. See $OutputPath"
}
