param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$RepoRoot = "",
    [string]$UnityProjectPath = "",
    [string]$UnityApk = "",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [switch]$SkipBuilder,
    [switch]$SkipGradleTests,
    [switch]$SkipQuestionnaireApkBuild,
    [switch]$SkipUnityInputModality
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-SafeFullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function New-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Detail,
        [string]$Evidence = ''
    )

    [ordered]@{
        name = $Name
        pass = $Pass
        detail = $Detail
        evidence = $Evidence
    }
}

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [bool]$Pass,
        [string]$Detail,
        [string]$Evidence = ''
    )

    $Checks.Add((New-Check -Name $Name -Pass $Pass -Detail $Detail -Evidence $Evidence)) | Out-Null
}

function ConvertTo-SafeFileName {
    param([string]$Name)
    $safe = $Name -replace '[^A-Za-z0-9_.-]+', '-'
    return $safe.Trim('-')
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [System.Collections.Generic.List[object]]$Steps
    )

    $safeName = ConvertTo-SafeFileName -Name $Name
    $logPath = Join-Path $script:OutputRootFull "$safeName.log"
    $startedAt = (Get-Date).ToUniversalTime().ToString('o')
    $exitCode = 0
    $output = $null
    Push-Location -LiteralPath $WorkingDirectory
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Executable @Arguments 2>&1
        if ($null -ne $LASTEXITCODE) {
            $exitCode = [int]$LASTEXITCODE
        }
    }
    catch {
        $exitCode = 1
        $output = $_
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }

    ($output | Out-String) | Set-Content -LiteralPath $logPath -Encoding UTF8
    $completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $step = [ordered]@{
        name = $Name
        status = if ($exitCode -eq 0) { 'pass' } else { 'fail' }
        exitCode = $exitCode
        executable = $Executable
        arguments = $Arguments
        workingDirectory = $WorkingDirectory
        logPath = $logPath
        startedAt = $startedAt
        completedAt = $completedAt
    }
    $Steps.Add($step) | Out-Null
    return $step
}

function Get-LatestSummaryPath {
    param(
        [string]$Root,
        [string]$FileName
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return ''
    }
    $folder = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $folder) {
        return ''
    }
    $path = Join-Path $folder.FullName $FileName
    if (Test-Path -LiteralPath $path) {
        return $path
    }
    return ''
}

function Get-SummaryPath {
    param(
        [string]$Root,
        [string]$FileName
    )

    $direct = Join-Path $Root $FileName
    if (Test-Path -LiteralPath $direct) {
        return $direct
    }
    return Get-LatestSummaryPath -Root $Root -FileName $FileName
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-ZipTextEntries {
    param(
        [string]$Path,
        [string]$Pattern
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $items = New-Object 'System.Collections.Generic.List[object]'
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match $Pattern) {
                $reader = New-Object System.IO.StreamReader($entry.Open())
                try {
                    $items.Add([ordered]@{
                        name = $entry.FullName
                        text = $reader.ReadToEnd()
                    }) | Out-Null
                }
                finally {
                    $reader.Dispose()
                }
            }
        }
    }
    finally {
        $zip.Dispose()
    }
    return @($items.ToArray())
}

function Inspect-UnityApkCatalog {
    param([string]$ApkPath)

    $result = [ordered]@{
        apk = $ApkPath
        status = 'missing'
        catalogCount = 0
        package = ''
        activity = ''
        triggerCount = 0
        triggerIds = @()
        entry = ''
    }
    if (-not (Test-Path -LiteralPath $ApkPath)) {
        return $result
    }

    $entries = @(Get-ZipTextEntries -Path $ApkPath -Pattern 'questionnaire-trigger-catalog\.json$')
    $result.catalogCount = $entries.Count
    if ($entries.Count -ne 1) {
        $result.status = 'fail'
        return $result
    }

    $catalog = $entries[0].text | ConvertFrom-Json
    $result.status = 'pass'
    $result.entry = [string]$entries[0].name
    $result.package = [string]$catalog.package
    $result.activity = [string]$catalog.activity
    $triggers = @($catalog.triggers)
    $result.triggerCount = $triggers.Count
    $result.triggerIds = @($triggers | ForEach-Object { [string]$_.triggerId })
    return $result
}

$projectFull = Get-SafeFullPath $ProjectPath
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $projectFull
}
$repoRootFull = Get-SafeFullPath $RepoRoot
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "minimal-apk-trigger-protocol-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectFull "artifacts\minimal-apk-trigger-protocol\$RunId"
}
$script:OutputRootFull = Get-SafeFullPath $OutputRoot
New-Item -ItemType Directory -Force -Path $script:OutputRootFull | Out-Null

if ([string]::IsNullOrWhiteSpace($UnityProjectPath)) {
    $UnityProjectPath = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo'
}
if ([string]::IsNullOrWhiteSpace($UnityApk)) {
    $UnityApk = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo\Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk'
}
$unityProjectFull = Get-SafeFullPath $UnityProjectPath
$unityApkFull = Get-SafeFullPath $UnityApk
$questionnaireApk = Join-Path $projectFull 'Builds\MyQuestionnaireVR-2D.apk'
$pairConfig = Join-Path $projectFull 'QuestionnaireConfigs\examples\quest-questionnaire-three-circle-protocol-demo.config.json'

$steps = New-Object 'System.Collections.Generic.List[object]'
$checks = New-Object 'System.Collections.Generic.List[object]'

$passiveSummary = Join-Path $script:OutputRootFull 'passive-trigger-protocol-summary.json'
Invoke-Step `
    -Name 'passive-trigger-protocol' `
    -Executable 'powershell' `
    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $projectFull 'tools\validate-passive-trigger-protocol.ps1'), '-ProjectPath', $projectFull, '-OutputPath', $passiveSummary) `
    -WorkingDirectory $projectFull `
    -Steps $steps | Out-Null

if (-not $SkipBuilder) {
    Invoke-Step `
        -Name 'questionnaire-builder-smoke' `
        -Executable 'powershell' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $projectFull 'tools\validate-questionnaire-builder.ps1'), '-ProjectPath', $projectFull, '-OutputDir', (Join-Path $script:OutputRootFull 'builder-smoke')) `
        -WorkingDirectory $projectFull `
        -Steps $steps | Out-Null
}

if (-not $SkipGradleTests) {
    Invoke-Step `
        -Name 'android-trigger-contract-tests' `
        -Executable (Join-Path $projectFull 'gradlew.bat') `
        -Arguments @(':app:testDebugUnitTest', '--tests', 'org.questquestionnaire.questionnaires2d.ChainLaunchContractTest', '--tests', 'org.questquestionnaire.questionnaires2d.QuestChainBrokerTest') `
        -WorkingDirectory $projectFull `
        -Steps $steps | Out-Null
}

if (-not $SkipQuestionnaireApkBuild) {
    Invoke-Step `
        -Name 'questionnaire-apk-build' `
        -Executable 'powershell' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $projectFull 'tools\build-apk.ps1'), '-ProjectPath', $projectFull, '-SkipTests') `
        -WorkingDirectory $projectFull `
        -Steps $steps | Out-Null
}

if (-not $SkipUnityInputModality) {
    Invoke-Step `
        -Name 'unity-input-modality' `
        -Executable 'powershell' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $projectFull 'tools\validate-unity-input-modality.ps1'), '-UnityProjectPath', $unityProjectFull, '-UnityApk', $unityApkFull, '-OutputRoot', (Join-Path $script:OutputRootFull 'unity-input-modality')) `
        -WorkingDirectory $projectFull `
        -Steps $steps | Out-Null
}

$pairAuditSummary = Join-Path $script:OutputRootFull 'two-apk-pair-summary.json'
Invoke-Step `
    -Name 'two-apk-pair-audit' `
    -Executable 'powershell' `
    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $projectFull 'tools\validate-two-apk-pair.ps1'), '-ProjectPath', $projectFull, '-QuestionnaireConfig', $pairConfig, '-UnityApk', $unityApkFull, '-OutputPath', $pairAuditSummary) `
    -WorkingDirectory $projectFull `
    -Steps $steps | Out-Null

$passive = Read-JsonFile -Path $passiveSummary
Add-Check -Checks $checks -Name 'passive trigger protocol validation' -Pass ($passive -and [string]$passive.status -eq 'pass') -Detail ($(if ($passive) { "checks=$($passive.checkCount) failed=$($passive.failedCount)" } else { 'summary missing' })) -Evidence $passiveSummary

$pairAudit = if (Test-Path -LiteralPath $pairAuditSummary) { Read-JsonFile -Path $pairAuditSummary } else { $null }
Add-Check -Checks $checks -Name 'two-apk pair audit validation' -Pass ($pairAudit -and [string]$pairAudit.status -eq 'pass') -Detail ($(if ($pairAudit) { "checks=$($pairAudit.checkCount) failed=$($pairAudit.failedCount) warnings=$($pairAudit.warningCount)" } else { 'summary missing' })) -Evidence $pairAuditSummary

$launcherContext = Join-Path $projectFull 'app\src\main\java\org\questquestionnaire\questionnaires2d\QuestionnaireLaunchContext.java'
$launcherText = if (Test-Path -LiteralPath $launcherContext) { Get-Content -LiteralPath $launcherContext -Raw } else { '' }
Add-Check -Checks $checks -Name 'questionnaire emits trigger receiver extras' -Pass ($launcherText -match 'mq\.triggerReceiverPackage' -and $launcherText -match 'mq\.triggerReceiverActivity' -and $launcherText -match 'mq\.triggerReceiverAction') -Detail 'Questionnaire completion intent tells Unity where passive triggers should return.' -Evidence $launcherContext
Add-Check -Checks $checks -Name 'questionnaire does not return questionnaire sequence to Unity' -Pass ($launcherText -notmatch 'target\.putExtra\s*\(\s*EXTRA_QUESTIONNAIRE_SEQUENCE') -Detail 'Questionnaire sequence stays inside the generated 2D APK/export state, not the Unity completion intent.' -Evidence $launcherContext

$unityTemplate = Join-Path $projectFull 'tools\unity\QuestQuestionnaireChainBridge.cs'
$unityTemplateText = if (Test-Path -LiteralPath $unityTemplate) { Get-Content -LiteralPath $unityTemplate -Raw } else { '' }
Add-Check -Checks $checks -Name 'unity template resolves trigger receiver' -Pass ($unityTemplateText -match 'ResolveTriggerReceiver' -and $unityTemplateText -match 'getIntent' -and $unityTemplateText -match 'mq\.triggerReceiverPackage') -Detail 'Unity helper reads the questionnaire-supplied receiver target from launch extras.' -Evidence $unityTemplate

$minimalUnityBridge = Join-Path $projectFull 'tools\unity\QuestQuestionnairePassiveTriggerBridge.cs'
$minimalUnityBridgeText = if (Test-Path -LiteralPath $minimalUnityBridge) { Get-Content -LiteralPath $minimalUnityBridge -Raw } else { '' }
Add-Check -Checks $checks -Name 'minimal passive Unity bridge exists' -Pass (Test-Path -LiteralPath $minimalUnityBridge) -Detail 'Copy-first Unity bridge for v2 passive trigger emission.' -Evidence $minimalUnityBridge
Add-Check -Checks $checks -Name 'minimal passive Unity bridge resolves trigger receiver' -Pass ($minimalUnityBridgeText -match 'ResolveTriggerReceiver' -and $minimalUnityBridgeText -match 'getIntent' -and $minimalUnityBridgeText -match 'mq\.triggerReceiverPackage') -Detail 'Minimal bridge reads the questionnaire-supplied receiver target from launch extras.' -Evidence $minimalUnityBridge
$minimalForbiddenRouting = @([regex]::Matches($minimalUnityBridgeText, 'mq\.(questionnaireMode|questionnaireSequence|blockId|blockNumber|finishBehavior|nextPackage|nextActivity|exportBehavior|score)') | ForEach-Object { $_.Value } | Sort-Object -Unique)
Add-Check -Checks $checks -Name 'minimal passive Unity bridge has no questionnaire routing extras' -Pass ($minimalForbiddenRouting.Count -eq 0) -Detail ($(if ($minimalForbiddenRouting.Count -eq 0) { 'Minimal bridge emits passive trigger metadata only.' } else { "forbidden=$($minimalForbiddenRouting -join ', ')" })) -Evidence $minimalUnityBridge
$minimalHardCodedFallback = @([regex]::Matches($minimalUnityBridgeText, 'FallbackQuestionnaire|org\.questquestionnaire\.questionnaires2d|QuestionnairePackage\s*=') | ForEach-Object { $_.Value } | Sort-Object -Unique)
Add-Check -Checks $checks -Name 'minimal passive Unity bridge has no hard-coded questionnaire fallback' -Pass ($minimalHardCodedFallback.Count -eq 0) -Detail ($(if ($minimalHardCodedFallback.Count -eq 0) { 'Minimal bridge uses the questionnaire-supplied receiver target only.' } else { "fallback=$($minimalHardCodedFallback -join ', ')" })) -Evidence $minimalUnityBridge

$circleBridge = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\Scripts\CircleDemoQuestionnaireBridge.cs'
$circleBridgeText = if (Test-Path -LiteralPath $circleBridge) { Get-Content -LiteralPath $circleBridge -Raw } else { '' }
Add-Check -Checks $checks -Name 'three-circle demo resolves trigger receiver' -Pass ($circleBridgeText -match 'ResolveTriggerReceiver' -and $circleBridgeText -match 'getIntent' -and $circleBridgeText -match 'mq\.triggerReceiverPackage') -Detail 'Public Unity demo returns triggers to the receiver supplied by the questionnaire APK.' -Evidence $circleBridge

$forbiddenUnityRouting = @([regex]::Matches($circleBridgeText, 'mq\.(questionnaireMode|questionnaireSequence|blockId|blockNumber|finishBehavior|nextPackage|nextActivity|exportBehavior|score)') | ForEach-Object { $_.Value } | Sort-Object -Unique)
Add-Check -Checks $checks -Name 'three-circle demo has no questionnaire routing extras' -Pass ($forbiddenUnityRouting.Count -eq 0) -Detail ($(if ($forbiddenUnityRouting.Count -eq 0) { 'Unity demo emits passive trigger metadata only.' } else { "forbidden=$($forbiddenUnityRouting -join ', ')" })) -Evidence $circleBridge

$hardCodedQuestionnaireFallback = @([regex]::Matches($circleBridgeText, 'FallbackQuestionnaire|org\.questquestionnaire\.questionnaires2d|QuestionnairePackage\s*=') | ForEach-Object { $_.Value } | Sort-Object -Unique)
Add-Check -Checks $checks -Name 'three-circle demo has no hard-coded questionnaire fallback' -Pass ($hardCodedQuestionnaireFallback.Count -eq 0) -Detail ($(if ($hardCodedQuestionnaireFallback.Count -eq 0) { 'Public Unity demo uses the questionnaire-supplied receiver target only.' } else { "fallback=$($hardCodedQuestionnaireFallback -join ', ')" })) -Evidence $circleBridge

$circleActivity = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\Plugins\Android\QuestQuestionnaireUnityActivity.java'
$circleActivityText = if (Test-Path -LiteralPath $circleActivity) { Get-Content -LiteralPath $circleActivity -Raw } else { '' }
Add-Check -Checks $checks -Name 'three-circle Unity activity refreshes launch intent' -Pass ($circleActivityText -match 'extends\s+UnityPlayerGameActivity' -and $circleActivityText -match 'onNewIntent\s*\(' -and $circleActivityText -match 'setIntent\s*\(\s*intent\s*\)') -Detail 'singleTop Unity launches update currentActivity.getIntent() so direct Meta Home launches cannot reuse stale receiver extras.' -Evidence $circleActivity

$circleManifest = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\Plugins\Android\AndroidManifest.xml'
$circleManifestText = if (Test-Path -LiteralPath $circleManifest) { Get-Content -LiteralPath $circleManifest -Raw } else { '' }
Add-Check -Checks $checks -Name 'three-circle manifest uses intent-refreshing activity' -Pass ($circleManifestText -match 'org\.questquestionnaire\.circletriggerdemo\.QuestQuestionnaireUnityActivity' -and $circleManifestText -match 'android:launchMode="singleTop"') -Detail 'Public demo launcher targets the activity that refreshes launch intents.' -Evidence $circleManifest
Add-Check -Checks $checks -Name 'three-circle manifest has no legacy chain action' -Pass ($circleManifestText -notmatch 'org\.questquestionnaire\.CHAIN_COMMAND') -Detail 'The public Unity demo is launched explicitly by the generated questionnaire APK and does not expose the legacy chain command action.' -Evidence $circleManifest

$circleSourceCatalog = Join-Path $repoRootFull 'example-scenario-apk\unity-project\three-circle-trigger-demo\Assets\StreamingAssets\mq\questionnaire-trigger-catalog.json'
$circleSourceCatalogObject = if (Test-Path -LiteralPath $circleSourceCatalog) { Get-Content -LiteralPath $circleSourceCatalog -Raw | ConvertFrom-Json } else { $null }
Add-Check -Checks $checks -Name 'three-circle source catalog names intent-refreshing activity' -Pass ($circleSourceCatalogObject -and [string]$circleSourceCatalogObject.activity -eq 'org.questquestionnaire.circletriggerdemo.QuestQuestionnaireUnityActivity') -Detail "activity=$($circleSourceCatalogObject.activity)" -Evidence $circleSourceCatalog

$unityCatalog = Inspect-UnityApkCatalog -ApkPath $unityApkFull
Add-Check -Checks $checks -Name 'unity apk has one embedded trigger catalog' -Pass ([string]$unityCatalog.status -eq 'pass') -Detail "catalogCount=$($unityCatalog.catalogCount) entry=$($unityCatalog.entry)" -Evidence $unityApkFull
Add-Check -Checks $checks -Name 'unity apk trigger catalog contains passive ids' -Pass ($unityCatalog.triggerCount -gt 0 -and (@($unityCatalog.triggerIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0)) -Detail "triggerCount=$($unityCatalog.triggerCount) triggerIds=$(@($unityCatalog.triggerIds) -join ',')" -Evidence $unityApkFull
Add-Check -Checks $checks -Name 'unity apk catalog names intent-refreshing activity' -Pass ([string]$unityCatalog.activity -eq 'org.questquestionnaire.circletriggerdemo.QuestQuestionnaireUnityActivity') -Detail "activity=$($unityCatalog.activity)" -Evidence $unityApkFull

Add-Check -Checks $checks -Name 'questionnaire apk built' -Pass (Test-Path -LiteralPath $questionnaireApk) -Detail $questionnaireApk -Evidence $questionnaireApk
Add-Check -Checks $checks -Name 'live quest product path kept separate' -Pass $true -Detail 'This validator performs local software checks only. It does not install, wake, launch, force-stop, or foreground-switch a headset.' -Evidence ''

$stepArray = @($steps.ToArray())
foreach ($step in $stepArray) {
    Add-Check -Checks $checks -Name "step $($step.name)" -Pass ([string]$step.status -eq 'pass') -Detail "exitCode=$($step.exitCode)" -Evidence $step.logPath
}

$checkArray = @($checks.ToArray())
$failed = @($checkArray | Where-Object { -not $_.pass })
$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.minimal-apk-trigger-protocol.validation.v1'
    status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
    runId = $RunId
    projectPath = $projectFull
    repoRoot = $repoRootFull
    outputRoot = $script:OutputRootFull
    proofBoundary = 'Local software protocol validated. Live Quest install, participant launch, Unity focus, passive trigger return, and export pull remain a separate physical gate.'
    productContract = [ordered]@{
        frontDoor = 'participant launches generated 2D questionnaire APK'
        stimulusRole = 'immersive Unity/stimulus APK presents content and emits passive trigger ids'
        questionnaireRole = 'generated 2D questionnaire APK owns block routing, state, exports, repeat rules, and trigger interpretation'
        triggerTransport = 'explicit Android intent with mq.triggerId to questionnaire-supplied mq.triggerReceiver* target'
        lslRole = 'optional host-side passive marker adapter into the same questionnaire-owned broker, not the default foreground-switching path'
    }
    artifacts = [ordered]@{
        passiveSummary = $passiveSummary
        pairAuditSummary = $pairAuditSummary
        questionnaireApk = $questionnaireApk
        unityApk = $unityApkFull
        unityInputSummary = Get-SummaryPath -Root (Join-Path $script:OutputRootFull 'unity-input-modality') -FileName 'unity-input-modality-summary.json'
    }
    unityCatalog = $unityCatalog
    steps = $stepArray
    checks = $checkArray
    checkCount = $checkArray.Count
    failedCount = $failed.Count
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $script:OutputRootFull 'minimal-apk-trigger-protocol-summary.json'
$summary | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]@{
    Status = $summary.status
    Checks = $summary.checkCount
    Failed = $summary.failedCount
    Summary = $summaryPath
    ProofBoundary = $summary.proofBoundary
}

if ($failed.Count -gt 0) {
    throw "Minimal APK trigger protocol validation failed. See $summaryPath"
}

exit 0
