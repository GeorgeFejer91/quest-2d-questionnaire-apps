param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [switch]$SkipValidation
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

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath 'Builds'
}
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "builder-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

$projectFull = Get-SafeFullPath $ProjectPath
$sourceDir = Join-Path $projectFull 'tools\questionnaire-config-editor'
$sourceHtml = Join-Path $sourceDir 'index.html'
$validateScript = Join-Path $projectFull 'tools\validate-questionnaire-builder.ps1'
if (-not (Test-Path -LiteralPath $sourceHtml)) {
    throw "Questionnaire builder HTML not found: $sourceHtml"
}
if (-not (Test-Path -LiteralPath $validateScript)) {
    throw "Questionnaire builder validator not found: $validateScript"
}

if (-not $SkipValidation) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validateScript -ProjectPath $projectFull | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Builder validation failed with exit code $LASTEXITCODE"
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$outputFull = Get-SafeFullPath $OutputRoot
$packageDir = Join-Path $outputFull 'QuestionnaireBuilder'
Assert-ChildPath -Child $packageDir -Parent $outputFull
if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}

$examplesDir = Join-Path $packageDir 'examples'
$schemasDir = Join-Path $packageDir 'schemas'
$unityDir = Join-Path $packageDir 'unity'
$toolsDir = Join-Path $packageDir 'tools'
New-Item -ItemType Directory -Force -Path $examplesDir | Out-Null
New-Item -ItemType Directory -Force -Path $schemasDir | Out-Null
New-Item -ItemType Directory -Force -Path $unityDir | Out-Null
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

Copy-Item -LiteralPath $sourceHtml -Destination (Join-Path $packageDir 'index.html') -Force

$launcherFiles = @(
    (Join-Path $projectFull 'Start-QuestionnaireBuilderApp.cmd'),
    (Join-Path $projectFull 'Start-QuestionnaireBuilderOnlineConnector.cmd')
)
foreach ($launcherFile in $launcherFiles) {
    if (Test-Path -LiteralPath $launcherFile) {
        Copy-Item -LiteralPath $launcherFile -Destination (Join-Path $packageDir ([System.IO.Path]::GetFileName($launcherFile))) -Force
    }
}

$exampleFiles = @(
    (Join-Path $projectFull 'QuestionnaireConfigs\quest-questionnaire-maia2.config.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\custom-presence-check.config.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\two-item-slider-template.csv'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\chain-plan.example.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\questionnaire-then-peripersonal-space-right.chain-plan.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\peripersonal-source-hook-candidate-smoke.chain-plan.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\sussex-polar-controller-then-questionnaire.chain-plan.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\source-hook-stub-then-questionnaire.chain-plan.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\lsl-start-questionnaire.example.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\examples\scenario-trigger-catalog.example.json')
)
foreach ($example in $exampleFiles) {
    if (Test-Path -LiteralPath $example) {
        Copy-Item -LiteralPath $example -Destination (Join-Path $examplesDir ([System.IO.Path]::GetFileName($example))) -Force
    }
}

$schemaFiles = @(
    (Join-Path $projectFull 'QuestionnaireConfigs\chain-plan.schema.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\lsl-chain-command.schema.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\trigger-catalog.schema.json'),
    (Join-Path $projectFull 'QuestionnaireConfigs\trigger-questionnaire-mapping.schema.json')
)
foreach ($schema in $schemaFiles) {
    if (Test-Path -LiteralPath $schema) {
        Copy-Item -LiteralPath $schema -Destination (Join-Path $schemasDir ([System.IO.Path]::GetFileName($schema))) -Force
    }
}

$unityFiles = @(
    (Join-Path $projectFull 'tools\unity\QuestQuestionnaireChainBridge.cs'),
    (Join-Path $projectFull 'tools\unity\ChainLinkControllerHook.cs'),
    (Join-Path $projectFull 'tools\unity\ChainLinkTimedTrigger.cs'),
    (Join-Path $projectFull 'tools\unity\README.md')
)
foreach ($unityFile in $unityFiles) {
    if (Test-Path -LiteralPath $unityFile) {
        Copy-Item -LiteralPath $unityFile -Destination (Join-Path $unityDir ([System.IO.Path]::GetFileName($unityFile))) -Force
    }
}

$toolFiles = @(
    (Join-Path $projectFull 'tools\get-apk-launch-info.ps1'),
    (Join-Path $projectFull 'tools\start-questionnaire-builder-app.ps1'),
    (Join-Path $projectFull 'tools\generate-questionnaire-apk.ps1'),
    (Join-Path $projectFull 'tools\validate-questionnaire-config.ps1'),
    (Join-Path $projectFull 'tools\apply-questionnaire-config.ps1'),
    (Join-Path $projectFull 'tools\quest-adb-readiness.ps1'),
    (Join-Path $projectFull 'tools\run-live-chainlink-stress.ps1'),
    (Join-Path $projectFull 'tools\validate-experiment-setup.ps1'),
    (Join-Path $projectFull 'tools\stress-chainlink-scenario-batch.ps1'),
    (Join-Path $projectFull 'tools\new-chainlink-plan.ps1'),
    (Join-Path $projectFull 'tools\new-wrapper-chain-plan.ps1'),
    (Join-Path $projectFull 'tools\audit-unity-source-hook-candidates.ps1'),
    (Join-Path $projectFull 'tools\build-unity-source-hook-apk.ps1'),
    (Join-Path $projectFull 'tools\build-chainlink-apk.ps1'),
    (Join-Path $projectFull 'tools\build-hook-wrapper-apk.ps1'),
    (Join-Path $projectFull 'tools\build-orchestrator-apk.ps1'),
    (Join-Path $projectFull 'tools\build-source-hook-stub-apk.ps1'),
    (Join-Path $projectFull 'tools\publish-experiment-chain-kit.ps1'),
    (Join-Path $projectFull 'tools\unity-source-hook-preflight.ps1'),
    (Join-Path $projectFull 'tools\validate-unity-chainlink-hook.ps1'),
    (Join-Path $projectFull 'tools\quest-installed-scenario-batch-validate.ps1'),
    (Join-Path $projectFull 'tools\quest-wrapper-chain-validate.ps1'),
    (Join-Path $projectFull 'tools\quest-wrapper-manual-gate-validate.ps1'),
    (Join-Path $projectFull 'tools\quest-orchestrator-wrapper-chain-validate.ps1'),
    (Join-Path $projectFull 'tools\quest-orchestrator-chain-validate.ps1'),
    (Join-Path $projectFull 'tools\quest-source-hook-chain-validate.ps1'),
    (Join-Path $projectFull 'tools\quest-chainlink-plan-validate.ps1'),
    (Join-Path $projectFull 'tools\lsl-chain-bridge.ps1'),
    (Join-Path $projectFull 'tools\lsl-chain-bridge.py'),
    (Join-Path $projectFull 'tools\lsl-send-command.py'),
    (Join-Path $projectFull 'tools\publish-questionnaire-builder-github-pages.ps1')
)
foreach ($toolFile in $toolFiles) {
    if (Test-Path -LiteralPath $toolFile) {
        Copy-Item -LiteralPath $toolFile -Destination (Join-Path $toolsDir ([System.IO.Path]::GetFileName($toolFile))) -Force
    }
}

$readmePath = Join-Path $packageDir 'README.txt'
$readme = @"
Quest 2D Panel Questionnaire Builder
====================================

Open index.html in a browser, edit or import questionnaire items, then download
the generated *.config.json file. Also download the matching
*.quality-report.json file and keep it beside the config as study-design
evidence.

For the desktop app flow, double-click Start-QuestionnaireBuilderApp.cmd. It
starts a localhost companion and opens this same HTML GUI in the local browser.
For the online GitHub Pages flow, double-click
Start-QuestionnaireBuilderOnlineConnector.cmd, open the hosted page, and enter
the pairing token printed by the local companion. The hosted page is static; it
only talks to the local companion API on 127.0.0.1.

The builder runs local quality guardrails for headset questionnaire use:
language item-count parity, participant burden, duplicate items, long wording,
multiple negations, double-barreled wording, and neutral punctuation.

Normal handoff:
1. Put the downloaded config in the Android project QuestionnaireConfigs folder.
2. Run tools\generate-questionnaire-apk.ps1 with that config.
3. Run tools\validate-questionnaire-pipeline.ps1 to build, render, and validate
   the generated Meta Horizon OS 2D panel app.
4. For multi-APK experiments, install the standalone on-headset orchestrator
   or ChainLink APK and use examples\chain-plan.example.json plus the Unity
   helper files under unity\. `ChainLinkControllerHook.cs` is the drop-in
   foreground left-controller trigger; `QuestQuestionnaireChainBridge.cs` is
   the Android intent bridge it calls.
5. To run the whole host-side setup gate, use
   tools\validate-experiment-setup.ps1. It combines ADB readiness, APK builds,
   ChainLink tests, Unity hook validation, Android render preview, builder
   smoke, and ChainLink scenario dry-runs into one evidence index.
6. Before live headset stress, run tools\quest-adb-readiness.ps1 with
   -RequireOnline. It records ADB devices, Windows USB inventory, headset
   properties when online, and concrete repair hints when the headset is not
   visible.
   For repeated plug-in sessions, use tools\run-live-chainlink-stress.ps1; it
   waits for a Quest, runs ChainLink dry-runs, and starts live headset stress
   only after a physical Quest serial is online.
7. For compiled scenario APKs without source hooks, use
   tools\new-wrapper-chain-plan.ps1 to generate a wrapper chain plan from the
   APK package/activity, then validate it with
   tools\quest-orchestrator-wrapper-chain-validate.ps1.
   For controller-confirmed closed APK links such as Peripersonal Space Right,
   use tools\quest-wrapper-manual-gate-validate.ps1 so the orchestrator waits
   until the operator sends an explicit continue command.
   To stress-test multiple installed legacy APKs, use
   tools\quest-installed-scenario-batch-validate.ps1.
8. For rebuilt Unity scenario APKs that expose the chain action directly, use
   the same tool with -HookMode Source and call
   QuestExperimentChainHook.ContinueCurrentPlan() at the scenario completion
   point. Before rebuilding, run tools\unity-source-hook-preflight.ps1 so missing
   Unity package dependencies are caught before device testing. Use
   tools\audit-unity-source-hook-candidates.ps1 to identify source scenes/build
   profiles and tools\build-unity-source-hook-apk.ps1 to build a source-hook
   candidate APK. Run tools\validate-unity-chainlink-hook.ps1 before sharing a
   kit so the ChainLink controller hook contract is present.
9. To stress a folder of APK targets, use
   tools\stress-chainlink-scenario-batch.ps1. It discovers launchable
   non-core APKs, dry-runs each through ChainLink, and can switch to device mode
   with -Serial.
10. To stress ChainLink numbered plans directly, use
   tools\quest-chainlink-plan-validate.ps1. Its -DryRun mode validates the plan
   and command sequence without a headset; device mode installs ChainLink,
   sends simulated Unity-hook nextBlock commands, and validates append-only
   questionnaire exports.
11. LSL can optionally start or continue an on-headset broker plan using
   examples\lsl-start-questionnaire.example.json.

This package is static HTML: it has no server-side storage, no analytics, and no
network requirement. The examples folder contains a full baseline config, a
custom six-item config, a compact CSV import template, brokered chain-plan
examples, compiled-APK wrapper examples, and an LSL command example.
"@
$readme | Set-Content -LiteralPath $readmePath -Encoding UTF8

$manifestPath = Join-Path $packageDir 'builder-package-manifest.json'
$contentFiles = Get-ChildItem -LiteralPath $packageDir -File -Recurse |
    Where-Object { $_.FullName -ne $manifestPath } |
    Sort-Object FullName |
    ForEach-Object { Get-ManifestFile -Root $packageDir -Path $_.FullName }

$manifest = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.builder-package.v1'
    status = 'pass'
    runId = $RunId
    title = 'Quest 2D Panel Questionnaire Builder'
    entrypoint = 'index.html'
    sourceHtml = $sourceHtml
    packageDir = $packageDir
    examples = @(
        'examples\quest-questionnaire-maia2.config.json',
        'examples\custom-presence-check.config.json',
        'examples\two-item-slider-template.csv',
        'examples\chain-plan.example.json',
        'examples\peripersonal-space-right-then-questionnaire.chain-plan.json',
        'examples\questionnaire-then-peripersonal-space-right.chain-plan.json',
        'examples\peripersonal-source-hook-candidate-smoke.chain-plan.json',
        'examples\sussex-polar-controller-then-questionnaire.chain-plan.json',
        'examples\source-hook-stub-then-questionnaire.chain-plan.json',
        'examples\lsl-start-questionnaire.example.json',
        'examples\scenario-trigger-catalog.example.json',
        'schemas\chain-plan.schema.json',
        'schemas\lsl-chain-command.schema.json',
        'schemas\trigger-catalog.schema.json',
        'schemas\trigger-questionnaire-mapping.schema.json',
        'Start-QuestionnaireBuilderApp.cmd',
        'Start-QuestionnaireBuilderOnlineConnector.cmd',
        'unity\QuestQuestionnaireChainBridge.cs',
        'unity\ChainLinkControllerHook.cs',
        'unity\ChainLinkTimedTrigger.cs',
        'unity\README.md',
        'tools\get-apk-launch-info.ps1',
        'tools\start-questionnaire-builder-app.ps1',
        'tools\generate-questionnaire-apk.ps1',
        'tools\validate-questionnaire-config.ps1',
        'tools\apply-questionnaire-config.ps1',
        'tools\quest-adb-readiness.ps1',
        'tools\run-live-chainlink-stress.ps1',
        'tools\validate-experiment-setup.ps1',
        'tools\stress-chainlink-scenario-batch.ps1',
        'tools\new-chainlink-plan.ps1',
        'tools\new-wrapper-chain-plan.ps1',
        'tools\audit-unity-source-hook-candidates.ps1',
        'tools\build-unity-source-hook-apk.ps1',
        'tools\build-chainlink-apk.ps1',
        'tools\build-hook-wrapper-apk.ps1',
        'tools\build-orchestrator-apk.ps1',
        'tools\build-source-hook-stub-apk.ps1',
        'tools\publish-experiment-chain-kit.ps1',
        'tools\validate-unity-chainlink-hook.ps1',
        'tools\quest-installed-scenario-batch-validate.ps1',
        'tools\quest-wrapper-chain-validate.ps1',
        'tools\quest-wrapper-manual-gate-validate.ps1',
        'tools\quest-orchestrator-wrapper-chain-validate.ps1',
        'tools\quest-orchestrator-chain-validate.ps1',
        'tools\quest-source-hook-chain-validate.ps1',
        'tools\quest-chainlink-plan-validate.ps1',
        'tools\lsl-chain-bridge.ps1',
        'tools\lsl-chain-bridge.py',
        'tools\lsl-send-command.py',
        'tools\publish-questionnaire-builder-github-pages.ps1'
    )
    recommendedCommands = [ordered]@{
        offlineDesktopApp = 'Start-QuestionnaireBuilderApp.cmd'
        onlineConnector = 'Start-QuestionnaireBuilderOnlineConnector.cmd'
        generateApk = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\generate-questionnaire-apk.ps1 -ConfigPath .\QuestionnaireConfigs\<downloaded-config>.config.json -RenderPreview'
        fullPipeline = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-pipeline.ps1 -ConfigPath .\QuestionnaireConfigs\<downloaded-config>.config.json -Serial <quest-serial>'
        generateWrapperChainPlan = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-wrapper-chain-plan.ps1 -TargetApk <scenario.apk> -ScenarioId <scenario-id> -HookMode Wrapper -OutputPath .\QuestionnaireConfigs\examples\<scenario-id>.chain-plan.json'
        generateSourceHookChainPlan = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-wrapper-chain-plan.ps1 -TargetApk <rebuilt-scenario.apk> -ScenarioId <scenario-id> -HookMode Source -OutputPath .\QuestionnaireConfigs\examples\<scenario-id>-source-hook.chain-plan.json'
        sourceHookCandidateAudit = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-unity-source-hook-candidates.ps1'
        sourceHookCandidateBuild = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-unity-source-hook-apk.ps1 -ScenePath "Assets\Scenes\Main Questionnaire.unity" -PackageId "org.questquestionnaire.stimulusdemo.sourcehook" -ProductName "Quest Questionnaire Stimulus Source Hook Candidate"'
        installedScenarioBatchValidation = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-installed-scenario-batch-validate.ps1 -Serial <quest-serial> -MaxTargets 3 -Order Both -SkipBuild'
        liveChainLinkStress = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-live-chainlink-stress.ps1 -RestartServer -WaitSeconds 90 -SkipBuild'
        orchestratorWrapperValidation = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-orchestrator-wrapper-chain-validate.ps1 -Serial <quest-serial> -TargetPackage <scenario-package> -TargetActivity <scenario-activity> -ChainPlanPath .\QuestionnaireConfigs\examples\<scenario-id>.chain-plan.json -SkipBuild'
        orchestratorSourceHookValidation = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-orchestrator-chain-validate.ps1 -Serial <quest-serial> -SkipBuild'
        sourceHookStubValidation = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-source-hook-chain-validate.ps1 -Serial <quest-serial> -SkipBuild'
        brokerChainValidation = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-broker-chain-validate.ps1 -Serial <quest-serial> -Apk .\Builds\MyQuestionnaireVR-2D.apk -SkipBuild'
        lslBridge = 'powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\lsl-chain-bridge.ps1 -Serial <quest-serial> -InstallDependencies'
    }
    files = $contentFiles
    createdAt = (Get-Date).ToString('o')
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$zipPath = Join-Path $outputFull 'QuestionnaireBuilder.zip'
Assert-ChildPath -Child $zipPath -Parent $outputFull
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath $zipPath -Force

$summaryPath = Join-Path $outputFull 'QuestionnaireBuilder-package-summary.json'
$summary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.builder-publish-summary.v1'
    status = 'pass'
    runId = $RunId
    packageDir = $packageDir
    entrypoint = Join-Path $packageDir 'index.html'
    zip = $zipPath
    zipBytes = (Get-Item -LiteralPath $zipPath).Length
    zipSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    manifest = $manifestPath
    html = Join-Path $packageDir 'index.html'
    validation = if ($SkipValidation) { 'skipped' } else { 'pass' }
    completedAt = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Questionnaire builder package written to $packageDir"
Write-Host "Questionnaire builder ZIP: $zipPath"
Write-Host "Package summary: $summaryPath"
