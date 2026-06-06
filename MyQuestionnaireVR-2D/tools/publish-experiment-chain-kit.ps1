param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$KitName = "ExperimentChainKit",
    [string]$RunId = "",
    [switch]$BuildCoreApks,
    [switch]$IncludeOptionalApks,
    [switch]$SkipEvidence
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-SafeFullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-ChildPath {
    param(
        [string]$Child,
        [string]$Parent
    )

    $childFull = Get-SafeFullPath $Child
    $parentFull = (Get-SafeFullPath $Parent).TrimEnd('\')
    if (-not $childFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside output root. Child=$childFull Parent=$parentFull"
    }
}

function Get-RelativePathForManifest {
    param(
        [string]$Root,
        [string]$Path
    )

    $rootUri = [System.Uri]((Get-SafeFullPath $Root).TrimEnd('\') + '\')
    $pathUri = [System.Uri](Get-SafeFullPath $Path)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Get-ManifestFile {
    param(
        [string]$Root,
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path
    [ordered]@{
        relativePath = Get-RelativePathForManifest -Root $Root -Path $item.FullName
        bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Copy-RequiredFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Required file missing: $Source"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-OptionalFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Source) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return $true
    }
    return $false
}

function Copy-LatestArtifactFile {
    param(
        [string]$ProjectRoot,
        [string]$Category,
        [string]$FileName,
        [string]$EvidenceDir
    )

    $categoryRoot = Join-Path $ProjectRoot "artifacts\$Category"
    if (-not (Test-Path -LiteralPath $categoryRoot)) {
        return $null
    }
    $latest = Get-ChildItem -LiteralPath $categoryRoot -Directory |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $latest) {
        return $null
    }
    $source = Join-Path $latest.FullName $FileName
    if (-not (Test-Path -LiteralPath $source)) {
        return $null
    }

    $destination = Join-Path $EvidenceDir "$Category\$($latest.Name)\$FileName"
    Copy-OptionalFile -Source $source -Destination $destination | Out-Null
    return [ordered]@{
        category = $Category
        runId = $latest.Name
        source = $source
        packaged = $destination
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath 'Builds'
}
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "experiment-chain-kit-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

$projectFull = Get-SafeFullPath $ProjectPath
$outputFull = Get-SafeFullPath $OutputRoot
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null

if ($BuildCoreApks) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectFull 'tools\build-apk.ps1') -ProjectPath $projectFull -SkipTests | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Questionnaire APK build failed with exit code $LASTEXITCODE" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectFull 'tools\build-orchestrator-apk.ps1') -ProjectPath $projectFull | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Orchestrator APK build failed with exit code $LASTEXITCODE" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectFull 'tools\build-chainlink-apk.ps1') -ProjectPath $projectFull | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "ChainLink APK build failed with exit code $LASTEXITCODE" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectFull 'tools\build-hook-wrapper-apk.ps1') -ProjectPath $projectFull | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Wrapper APK build failed with exit code $LASTEXITCODE" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectFull 'tools\build-source-hook-stub-apk.ps1') -ProjectPath $projectFull | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Source hook stub APK build failed with exit code $LASTEXITCODE" }
}

$packageDir = Join-Path $outputFull $KitName
Assert-ChildPath -Child $packageDir -Parent $outputFull
if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}

$apksDir = Join-Path $packageDir 'apks'
$plansDir = Join-Path $packageDir 'chain-plans'
$configsDir = Join-Path $packageDir 'questionnaire-configs'
$schemasDir = Join-Path $packageDir 'schemas'
$toolsDir = Join-Path $packageDir 'tools'
$docsDir = Join-Path $packageDir 'docs'
$unityDir = Join-Path $packageDir 'unity'
$evidenceDir = Join-Path $packageDir 'evidence'

foreach ($dir in @($apksDir, $plansDir, $configsDir, $schemasDir, $toolsDir, $docsDir, $unityDir, $evidenceDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$requiredApks = @(
    'MyQuestionnaireVR-2D.apk',
    'ViscerealityExperimentOrchestrator.apk',
    'ViscerealityChainLink.apk',
    'ViscerealityChainHookWrapper.apk'
)
foreach ($apkName in $requiredApks) {
    Copy-RequiredFile -Source (Join-Path $projectFull "Builds\$apkName") -Destination (Join-Path $apksDir $apkName)
}

$optionalApkNames = @(
    'ViscerealitySourceHookStub.apk',
    'PeripersonalSpaceRight-device-base.apk'
)
if ($IncludeOptionalApks) {
    $optionalApkNames += @(
        'custom-presence-check-0.1.0.apk',
        'demo-slider-1.0.0.apk'
    )
}
$packagedOptionalApks = @()
foreach ($apkName in $optionalApkNames) {
    $source = Join-Path $projectFull "Builds\$apkName"
    $destination = Join-Path $apksDir $apkName
    if (Copy-OptionalFile -Source $source -Destination $destination) {
        $packagedOptionalApks += $apkName
    }
}

Copy-RequiredFile -Source (Join-Path $projectFull 'QuestionnaireConfigs\viscereality-maia2.config.json') -Destination (Join-Path $configsDir 'viscereality-maia2.config.json')

Get-ChildItem -LiteralPath (Join-Path $projectFull 'QuestionnaireConfigs\examples') -File |
    Where-Object { $_.Extension -in @('.json', '.csv') } |
    ForEach-Object {
        if ($_.Name -like '*.chain-plan.json') {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $plansDir $_.Name) -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $configsDir $_.Name) -Force
        }
    }

$schemaFiles = @(
    'chain-plan.schema.json',
    'lsl-chain-command.schema.json'
)
foreach ($schemaName in $schemaFiles) {
    Copy-OptionalFile -Source (Join-Path $projectFull "QuestionnaireConfigs\$schemaName") -Destination (Join-Path $schemasDir $schemaName) | Out-Null
}

$toolFiles = @(
    'get-apk-launch-info.ps1',
    'quest-adb-readiness.ps1',
    'run-live-chainlink-stress.ps1',
    'validate-experiment-setup.ps1',
    'stress-chainlink-scenario-batch.ps1',
    'new-chainlink-plan.ps1',
    'new-wrapper-chain-plan.ps1',
    'audit-unity-source-hook-candidates.ps1',
    'publish-experiment-chain-kit.ps1',
    'build-unity-source-hook-apk.ps1',
    'build-apk.ps1',
    'build-chainlink-apk.ps1',
    'build-orchestrator-apk.ps1',
    'build-hook-wrapper-apk.ps1',
    'build-source-hook-stub-apk.ps1',
    'quest-orchestrator-wrapper-chain-validate.ps1',
    'quest-wrapper-manual-gate-validate.ps1',
    'quest-installed-scenario-batch-validate.ps1',
    'quest-wrapper-chain-validate.ps1',
    'quest-orchestrator-chain-validate.ps1',
    'quest-source-hook-chain-validate.ps1',
    'quest-chain-validate.ps1',
    'quest-chainlink-plan-validate.ps1',
    'quest-broker-chain-validate.ps1',
    'quest-manual-hardware-gate.ps1',
    'quest-validate.ps1',
    'render-questionnaire-visuals.ps1',
    'lsl-chain-bridge.ps1',
    'lsl-chain-bridge.py',
    'lsl-send-command.py',
    'unity-source-hook-preflight.ps1',
    'validate-unity-chainlink-hook.ps1',
    'validate-questionnaire-config.ps1',
    'validate-questionnaire-assets.ps1',
    'validate-questionnaire-pipeline.ps1'
)
foreach ($toolName in $toolFiles) {
    Copy-OptionalFile -Source (Join-Path $projectFull "tools\$toolName") -Destination (Join-Path $toolsDir $toolName) | Out-Null
}

$unityFiles = @(
    'QuestQuestionnaireChainBridge.cs',
    'ChainLinkControllerHook.cs',
    'README.md'
)
foreach ($unityName in $unityFiles) {
    Copy-OptionalFile -Source (Join-Path $projectFull "tools\unity\$unityName") -Destination (Join-Path $unityDir $unityName) | Out-Null
}

Get-ChildItem -LiteralPath (Join-Path $projectFull 'docs') -File |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $docsDir $_.Name) -Force
    }

$evidenceFiles = @()
if (-not $SkipEvidence) {
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'experiment-setup-status' -FileName 'experiment-setup-status.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'experiment-chain-evidence-index' -FileName 'experiment-chain-evidence-index.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'peripersonal-source-mapping' -FileName 'peripersonal-source-mapping.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'unity-source-hook-candidates' -FileName 'unity-source-hook-candidates.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'unity-source-hook-build' -FileName 'unity-source-hook-build-wrapper-summary.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'qmanual' -FileName 'quest-wrapper-manual-gate-validation-summary.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'qmanual' -FileName 'operator-instructions.md' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'qbatch' -FileName 'quest-installed-scenario-batch-validation-summary.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'quest-orchestrator-wrapper-chain-validation' -FileName 'quest-orchestrator-wrapper-chain-validation-summary.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'unity-source-hook-preflight' -FileName 'unity-source-hook-preflight.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'unity-batchmode-compile' -FileName 'unity-batchmode-summary.json' -EvidenceDir $evidenceDir
    $evidenceFiles += Copy-LatestArtifactFile -ProjectRoot $projectFull -Category 'experiment-setup-validation' -FileName 'experiment-setup-validation-summary.json' -EvidenceDir $evidenceDir
    $evidenceFiles = @($evidenceFiles | Where-Object { $null -ne $_ })
}

$installScriptPath = Join-Path $packageDir 'install-core-apks.ps1'
$installScript = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$Serial,
    [string]$Adb = "adb",
    [switch]$InstallPeripersonal
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$apks = @(
    "MyQuestionnaireVR-2D.apk",
    "ViscerealityExperimentOrchestrator.apk",
    "ViscerealityChainLink.apk",
    "ViscerealityChainHookWrapper.apk"
)
if ($InstallPeripersonal) {
    $apks += "PeripersonalSpaceRight-device-base.apk"
}

foreach ($apk in $apks) {
    $path = Join-Path $root "apks\$apk"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "APK missing from kit: $path"
    }
    & $Adb -s $Serial install -r -d $path
    if ($LASTEXITCODE -ne 0) {
        throw "adb install failed for $apk with exit code $LASTEXITCODE"
    }
}

Write-Host "Installed core experiment-chain APKs on $Serial"
'@
$installScript | Set-Content -LiteralPath $installScriptPath -Encoding UTF8

$readmePath = Join-Path $packageDir 'README.md'
$readme = @"
# Viscereality Experiment Chain Kit

This kit packages the tested Quest APK-chain workflow for the questionnaire
Android 2D app for Meta Horizon OS and Viscereality scenario APKs.

## Contents

- `apks\MyQuestionnaireVR-2D.apk`: questionnaire 2D panel app.
- `apks\ViscerealityExperimentOrchestrator.apk`: on-headset plan owner.
- `apks\ViscerealityChainLink.apk`: numbered block registry switchboard for APK launches.
- `apks\ViscerealityChainHookWrapper.apk`: wrapper for closed/legacy scenario APKs.
- `apks\PeripersonalSpaceRight-device-base.apk`: pulled Peripersonal Space Right APK, when available.
- `chain-plans\*.chain-plan.json`: orchestrator plans, including Peripersonal Space Right before/after questionnaire.
- `tools\quest-wrapper-manual-gate-validate.ps1`: closed-APK manual/controller gate validation.
- `tools\quest-adb-readiness.ps1`: Quest ADB transport readiness and USB/wireless diagnostic gate.
- `tools\run-live-chainlink-stress.ps1`: restartable wait/dry-run/live ChainLink stress harness.
- `tools\validate-experiment-setup.ps1`: one-command local/device experiment setup validation index.
- `tools\quest-installed-scenario-batch-validate.ps1`: batch stress validation for installed Viscereality APKs.
- `tools\stress-chainlink-scenario-batch.ps1`: discover launchable APK targets and run ChainLink dry-run/device stress for each.
- `tools\quest-chainlink-plan-validate.ps1`: direct ChainLink numbered-plan stress validation with simulated foreground-hook `nextBlock` commands.
- `tools\audit-unity-source-hook-candidates.ps1`: inspect Unity source scenes/build profiles for source-hook readiness.
- `tools\build-unity-source-hook-apk.ps1`: build a chosen Unity scene/package with the source-hook entrypoint.
- `tools\validate-unity-chainlink-hook.ps1`: static validation for the drop-in ChainLink Unity hook.
- `tools\lsl-chain-bridge.ps1`: optional LSL-to-broker command source.
- `unity\QuestQuestionnaireChainBridge.cs`: source-hook helper for rebuildable Unity scenarios.
- `unity\ChainLinkControllerHook.cs`: drop-in left-controller foreground hook for ChainLink `nextBlock`.
- `docs\experiment-chain-workflow.md`: operational recipe and current evidence notes.

## Install Core APKs

Before live headset stress, verify the Quest ADB transport:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-adb-readiness.ps1 `
  -RestartServer `
  -WaitSeconds 30 `
  -RequireOnline
```

Run the consolidated local setup gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-experiment-setup.ps1 `
  -SkipPublish
```

When ADB is online, add `-Serial <quest-serial> -RunLiveDeviceBatch` to include
the live ChainLink scenario batch.

For repeated plug-in stress sessions, use the restartable live harness. It waits
for a physical Quest ADB device, dry-runs all launchable scenario APKs, and only
attempts install/launch/export stress when a Quest serial is online:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-live-chainlink-stress.ps1 `
  -RestartServer `
  -WaitSeconds 90 `
  -SkipBuild
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-core-apks.ps1 `
  -Serial <quest-serial> `
  -InstallPeripersonal
```

## ChainLink Numbered-Plan Stress

Discover and dry-run every launchable scenario APK in the kit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\stress-chainlink-scenario-batch.ps1 `
  -DryRun `
  -PictographicRepeats 2
```

Dry-run the exact ChainLink plan and command sequence without a headset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-chainlink-plan-validate.ps1 `
  -DryRun `
  -TargetApk .\apks\PeripersonalSpaceRight-device-base.apk `
  -PictographicRepeats 2
```

When the Quest appears in `adb devices -l` as `device`, run the same route on
the headset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-chainlink-plan-validate.ps1 `
  -Serial <quest-serial> `
  -TargetApk .\apks\PeripersonalSpaceRight-device-base.apk `
  -PictographicRepeats 2 `
  -SkipBuild
```

The script starts ChainLink, lets the baseline questionnaire auto-complete,
sends timestamped `nextBlock` intents as a Unity foreground hook stand-in,
pulls ChainLink state/events plus questionnaire exports, and checks append-only
baseline/pictographic output counts.

## Peripersonal Space Right Closed-APK Route

Use the wrapper/manual gate when the APK cannot be rebuilt. Start the plan and
pause after Peripersonal Space Right launches:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Start `
  -Serial <quest-serial> `
  -SkipBuild `
  -TargetPackage com.Viscereality.ViscerealityPeriPersonalSpaceRight `
  -TargetActivity com.unity3d.player.UnityPlayerGameActivity `
  -ChainPlanPath .\chain-plans\peripersonal-space-right-then-questionnaire.chain-plan.json
```

After the operator uses the Quest controller to reach the intended scenario
completion point, continue the broker:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Continue `
  -Serial <quest-serial> `
  -OutputRoot .\artifacts\qmanual\<run-id>
```

For automated smoke only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Full `
  -Serial <quest-serial> `
  -SkipBuild `
  -AutoContinueAfterSeconds 8
```

## Semantic Source-Hook Upgrade

For a scenario APK that can be rebuilt, add the Unity helper and call
`QuestExperimentChainHook.ContinueCurrentPlan()` from the real scenario end
event. That removes the manual witness and gives the orchestrator a semantic
completion signal.

For controller-triggered ChainLink blocks, attach
`unity\ChainLinkControllerHook.cs` to a GameObject in the foreground Unity
scene. It listens to the configured left-controller button and sends
`mq.command=nextBlock` to ChainLink with timestamped trigger metadata.

Validate the exported Unity hook files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-unity-chainlink-hook.ps1
```

Audit candidate Unity scenes/build profiles:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-unity-source-hook-candidates.ps1
```

Build a source-hook candidate APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-unity-source-hook-apk.ps1 `
  -ScenePath "Assets\Scenes\Main Questionnaire.unity" `
  -PackageId "com.Viscereality.ViscerealityPeriPersonalSpaceRight.SourceHook" `
  -ProductName "Viscereality Peripersonal Source Hook Candidate"
```

Use `chain-plans\peripersonal-source-hook-candidate-smoke.chain-plan.json` for a
short smoke route. It includes `mq.sourceAutoContinueDelayMs`; remove that extra
for real experiment execution.

## Data Safety

The questionnaire writes draft data during the run and final JSON/CSV exports
before returning to the orchestrator. Device path:

```text
/sdcard/Android/data/org.mesmerprism.viscereality.questionnaires2d/files/QuestionnaireExports
```

Each invocation uses a unique run id, participant-safe filename, and
`session-index.jsonl` entry.
"@
$readme | Set-Content -LiteralPath $readmePath -Encoding UTF8

$manifestPath = Join-Path $packageDir 'experiment-chain-kit-manifest.json'
$contentFiles = Get-ChildItem -LiteralPath $packageDir -File -Recurse |
    Where-Object { $_.FullName -ne $manifestPath } |
    Sort-Object FullName |
    ForEach-Object { Get-ManifestFile -Root $packageDir -Path $_.FullName }

$manifest = [ordered]@{
    schemaVersion = 'viscereality.experiment-chain-kit.v1'
    status = 'pass'
    runId = $RunId
    kitName = $KitName
    projectPath = $projectFull
    packageDir = $packageDir
    requiredApks = $requiredApks
    optionalApksPackaged = $packagedOptionalApks
    primaryClosedApkTarget = [ordered]@{
        package = 'com.Viscereality.ViscerealityPeriPersonalSpaceRight'
        activity = 'com.unity3d.player.UnityPlayerGameActivity'
        chainPlan = 'chain-plans\peripersonal-space-right-then-questionnaire.chain-plan.json'
        linkMode = 'wrapper-manual-gate'
    }
    recommendedCommands = [ordered]@{
        install = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\install-core-apks.ps1 -Serial <quest-serial> -InstallPeripersonal'
        peripersonalManualStart = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 -Mode Start -Serial <quest-serial> -SkipBuild -TargetPackage com.Viscereality.ViscerealityPeriPersonalSpaceRight -TargetActivity com.unity3d.player.UnityPlayerGameActivity -ChainPlanPath .\chain-plans\peripersonal-space-right-then-questionnaire.chain-plan.json'
        installedScenarioBatch = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-installed-scenario-batch-validate.ps1 -Serial <quest-serial> -MaxTargets 5 -Order Both -SkipBuild'
        liveChainLinkStress = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-live-chainlink-stress.ps1 -RestartServer -WaitSeconds 90 -SkipBuild'
        sourceHookAudit = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-unity-source-hook-candidates.ps1'
        sourceHookBuild = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-unity-source-hook-apk.ps1 -ScenePath "Assets\Scenes\Main Questionnaire.unity" -PackageId "com.Viscereality.ViscerealityPeriPersonalSpaceRight.SourceHook" -ProductName "Viscereality Peripersonal Source Hook Candidate"'
        lslBridge = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\lsl-chain-bridge.ps1 -Serial <quest-serial> -InstallDependencies'
    }
    evidence = $evidenceFiles
    files = $contentFiles
    createdAt = (Get-Date).ToString('o')
}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$zipPath = Join-Path $outputFull "$KitName.zip"
Assert-ChildPath -Child $zipPath -Parent $outputFull
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath $zipPath -Force

$summaryPath = Join-Path $outputFull "$KitName-package-summary.json"
$summary = [ordered]@{
    schemaVersion = 'viscereality.experiment-chain-kit-publish-summary.v1'
    status = 'pass'
    runId = $RunId
    packageDir = $packageDir
    zip = $zipPath
    zipBytes = (Get-Item -LiteralPath $zipPath).Length
    zipSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    manifest = $manifestPath
    requiredApks = $requiredApks
    optionalApksPackaged = $packagedOptionalApks
    evidenceCount = @($evidenceFiles).Count
    completedAt = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Experiment chain kit written to $packageDir"
Write-Host "Experiment chain kit ZIP: $zipPath"
Write-Host "Package summary: $summaryPath"
