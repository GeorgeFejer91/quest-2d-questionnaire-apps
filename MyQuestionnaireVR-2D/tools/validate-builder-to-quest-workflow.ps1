param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [string]$ProjectPath = "",
    [string]$RepoRoot = "",
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR",
    [string]$TemporalTracerPath = "",
    [string]$UnityDemoPath = "",
    [string]$QuestionnaireApk = "",
    [string]$TemporalTracerApk = "",
    [string]$UnityApk = "",
    [string]$Serial = "",
    [string]$RunId = "",
    [int]$QuestTrials = 10,
    [int]$WaitForReadySeconds = 30,
    [switch]$InvokedByCompanion,
    [switch]$SkipApkBuild,
    [switch]$SkipQuestionnaireRender,
    [switch]$SkipTemporalRender,
    [switch]$SkipTemporalApkBuild,
    [switch]$SkipUnityStatic,
    [switch]$RunQuestReadiness,
    [switch]$RunQuestDirectHandoff,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "builder-to-quest-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Split-Path -Parent $PSScriptRoot
}
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
}
if ([string]::IsNullOrWhiteSpace($TemporalTracerPath)) {
    $TemporalTracerPath = Join-Path $RepoRoot 'TemporalExperienceTracerVR-2D'
}
if ([string]::IsNullOrWhiteSpace($UnityDemoPath)) {
    $UnityDemoPath = Join-Path $RepoRoot 'AweGreatDictatorUnity'
}
if ([string]::IsNullOrWhiteSpace($TemporalTracerApk)) {
    $TemporalTracerApk = Join-Path $TemporalTracerPath 'Builds\TemporalExperienceTracerVR-2D.apk'
}
if ([string]::IsNullOrWhiteSpace($UnityApk)) {
    $UnityApk = Join-Path $UnityDemoPath 'Builds\QuestionnaireStimulusBuilderDemo.apk'
}

$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$artifactRoot = Join-Path $ProjectPath ("artifacts\builder-to-quest-workflow\" + $RunId)
$logsDir = Join-Path $artifactRoot 'logs'
$staticDir = Join-Path $artifactRoot 'static'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
New-Item -ItemType Directory -Force -Path $staticDir | Out-Null

$steps = New-Object 'System.Collections.Generic.List[object]'
$requirements = New-Object 'System.Collections.Generic.List[object]'

function ConvertTo-SafeName {
    param([string]$Value, [string]$Fallback = "value")

    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return $Fallback
    }
    return $safe
}

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 14)

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonIfExists {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Get-FileEvidence {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{ exists = $false; path = $Path }
    }
    $exists = Test-Path -LiteralPath $Path
    $evidence = [ordered]@{
        exists = $exists
        path = $Path
    }
    if ($exists -and -not (Get-Item -LiteralPath $Path).PSIsContainer) {
        $item = Get-Item -LiteralPath $Path
        $evidence.bytes = $item.Length
        $evidence.sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        $evidence.lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
    }
    return $evidence
}

function Get-RenderEvidence {
    param([string]$SummaryPath)

    $summary = Read-JsonIfExists -Path $SummaryPath
    if ($null -eq $summary) {
        return [ordered]@{
            exists = $false
            summaryPath = $SummaryPath
        }
    }

    $renders = @($summary.renders)
    $pngs = @($renders | ForEach-Object { $_.png } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    return [ordered]@{
        exists = $true
        summaryPath = $SummaryPath
        schemaVersion = $summary.schemaVersion
        status = if ($summary.PSObject.Properties.Name -contains 'status') { $summary.status } else { '' }
        renderer = if ($summary.PSObject.Properties.Name -contains 'renderer') { $summary.renderer } else { '' }
        renderCount = $renders.Count
        passCount = @($renders | Where-Object { $_.status -eq 'pass' }).Count
        warnCount = @($renders | Where-Object { $_.status -eq 'warn' }).Count
        failCount = @($renders | Where-Object { $_.status -eq 'fail' }).Count
        pngCount = $pngs.Count
        stages = @($renders | ForEach-Object { $_.stageName } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        sizes = @($renders | ForEach-Object { "$($_.widthDp)x$($_.heightDp)" } | Where-Object { $_ -notmatch '^x$' } | Select-Object -Unique)
        languages = @($renders | ForEach-Object { $_.language } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        samplePngs = @($pngs | Select-Object -First 3)
    }
}

function Get-DirectPreflightEvidence {
    param([string]$SummaryPath)

    $summary = Read-JsonIfExists -Path $SummaryPath
    if ($null -eq $summary) {
        return [ordered]@{
            exists = $false
            summaryPath = $SummaryPath
        }
    }
    $preflight = $summary.preflight
    return [ordered]@{
        exists = $true
        summaryPath = $SummaryPath
        status = $summary.status
        preflightStatus = if ($preflight) { $preflight.status } else { '' }
        issueCount = if ($preflight) { @($preflight.issues).Count } else { 0 }
        questionnaire = if ($preflight) { $preflight.apkInfo.questionnaire } else { $null }
        temporalTracer = if ($preflight) { $preflight.apkInfo.temporalTracer } else { $null }
        unity = if ($preflight) { $preflight.apkInfo.unity } else { $null }
        triggerCount = if ($preflight -and $preflight.triggerCatalog) { @($preflight.triggerCatalog.triggers).Count } else { 0 }
    }
}

function Get-QuestAdbEvidence {
    param([string]$SummaryPath)

    $summary = Read-JsonIfExists -Path $SummaryPath
    if ($null -eq $summary) {
        return [ordered]@{
            exists = $false
            summaryPath = $SummaryPath
        }
    }
    return [ordered]@{
        exists = $true
        summaryPath = $SummaryPath
        status = $summary.status
        readiness = $summary.readiness
        targetSerial = $summary.targetSerial
        onlineCount = $summary.onlineCount
        unauthorizedCount = $summary.unauthorizedCount
        offlineCount = $summary.offlineCount
        offlineEmulatorCount = $summary.offlineEmulatorCount
        productPathStatus = if ($summary.PSObject.Properties.Name -contains 'productPathStatus') { $summary.productPathStatus } else { 'not-probed' }
        productPathReady = if ($summary.PSObject.Properties.Name -contains 'productPathReady') { [bool]$summary.productPathReady } else { $false }
        productPathBlockedReasons = if ($summary.PSObject.Properties.Name -contains 'productPath' -and $summary.productPath -and $summary.productPath.PSObject.Properties.Name -contains 'blockedReasons') { @($summary.productPath.blockedReasons) } else { @() }
        model = $summary.deviceProps.model
        androidRelease = $summary.deviceProps.androidRelease
        wmSize = $summary.deviceProps.wmSize
        wmDensity = $summary.deviceProps.wmDensity
        recommendations = $summary.recommendations
    }
}

function Invoke-ToolStep {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$SummaryPath = "",
        [ValidateSet('fail', 'warn', 'blocked')]
        [string]$NonZeroStatus = 'fail'
    )

    $safeName = ConvertTo-SafeName -Value $Name -Fallback 'step'
    $logPath = Join-Path $script:logsDir ($safeName + '.txt')
    $started = (Get-Date).ToUniversalTime()
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell @Arguments 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    }
    finally {
        $ErrorActionPreference = $previous
    }
    @($output) | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath $logPath -Encoding UTF8
    $status = if ($exitCode -eq 0) { 'pass' } else { $NonZeroStatus }
    $summary = if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) { Read-JsonIfExists -Path $SummaryPath } else { $null }
    $step = [ordered]@{
        name = $Name
        status = $status
        exitCode = $exitCode
        started = $started.ToString('o')
        completed = (Get-Date).ToUniversalTime().ToString('o')
        log = $logPath
        summaryPath = if ([string]::IsNullOrWhiteSpace($SummaryPath)) { $null } else { $SummaryPath }
        summary = $summary
    }
    $script:steps.Add($step) | Out-Null
    return $step
}

function Add-Requirement {
    param(
        [string]$Id,
        [string]$Requirement,
        [string]$Status,
        [string]$Evidence,
        [string]$Notes = "",
        [object]$Facts = $null
    )

    $row = [ordered]@{
        id = $Id
        requirement = $Requirement
        status = $Status
        evidence = $Evidence
        notes = $Notes
    }
    if ($null -ne $Facts) {
        $row.facts = $Facts
    }
    $script:requirements.Add($row) | Out-Null
}

function Get-StepStatus {
    param([object]$Step)

    if ($null -eq $Step) {
        return 'pending'
    }
    return [string]$Step.status
}

function Test-UnityDirectHandoffBridge {
    param([string]$OutputDir)

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $bridgePath = Join-Path $ProjectPath 'tools\unity\QuestQuestionnaireChainBridge.cs'
    $checks = New-Object 'System.Collections.Generic.List[object]'

    function Add-Check {
        param([string]$Name, [bool]$Pass, [string]$Detail)
        $checks.Add([ordered]@{
            name = $Name
            pass = $Pass
            detail = $Detail
        }) | Out-Null
    }

    function Test-Text {
        param([string]$Text, [string]$Pattern)
        return [bool]([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline))
    }

    Add-Check -Name 'bridge file exists' -Pass (Test-Path -LiteralPath $bridgePath) -Detail $bridgePath
    $bridgeText = if (Test-Path -LiteralPath $bridgePath) { Get-Content -LiteralPath $bridgePath -Raw } else { '' }
    Add-Check -Name 'handoff schema constant' -Pass (Test-Text $bridgeText 'HandoffSchemaV1\s*=\s*"mq\.handoff\.v1"') -Detail 'Bridge writes mq.handoff.v1.'
    Add-Check -Name 'return PendingIntent extra' -Pass (Test-Text $bridgeText 'ReturnPendingIntentExtra\s*=\s*"mq\.returnPendingIntent"') -Detail 'Bridge declares mq.returnPendingIntent.'
    Add-Check -Name 'PendingIntent.getActivity return token' -Pass (Test-Text $bridgeText 'PendingIntent.*?getActivity') -Detail 'Bridge creates caller-owned return token.'
    Add-Check -Name 'return flags include reorder singleTop newTask' -Pass (Test-Text $bridgeText 'FlagActivityReorderToFront\s*\|\s*FlagActivitySingleTop\s*\|\s*FlagActivityNewTask') -Detail 'Return target uses required Activity flags.'
    Add-Check -Name 'panel launch includes return token' -Pass (Test-Text $bridgeText 'putExtra"\s*,\s*ReturnPendingIntentExtra\s*,\s*returnPendingIntent') -Detail 'Panel launch carries PendingIntent Parcelable.'
    Add-Check -Name 'panel launch starts explicit activity' -Pass (Test-Text $bridgeText 'setClassName"\s*,\s*packageName\s*,\s*activityName.*?startActivity"\s*,\s*intent') -Detail 'Questionnaire/tracer are explicit component launches.'
    Add-Check -Name 'result extras reader' -Pass (Test-Text $bridgeText 'mq\.resultStatus.*?mq\.exportJsonPath.*?mq\.exportCsvPath.*?mq\.exportSvgPath') -Detail 'Unity can read completion/export result extras.'

    $checkArray = @($checks.ToArray())
    $failed = @($checkArray | Where-Object { -not $_.pass })
    $summary = [ordered]@{
        schemaVersion = 'mq.unity_direct_handoff_bridge_static.v1'
        status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
        bridge = $bridgePath
        checkCount = $checkArray.Count
        failedCount = $failed.Count
        checks = $checkArray
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $summaryPath = Join-Path $OutputDir 'unity-direct-handoff-bridge-static-summary.json'
    Write-Json -Value $summary -Path $summaryPath -Depth 10
    return [pscustomobject]@{
        Status = $summary.status
        SummaryPath = $summaryPath
        Summary = $summary
    }
}

$config = Get-Content -LiteralPath $ConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json
$questionnaireId = ConvertTo-SafeName -Value $config.questionnaireId -Fallback 'questionnaire'
$questionnaireVersion = ConvertTo-SafeName -Value $config.questionnaireVersion -Fallback '0.0.0'

Add-Requirement `
    -Id 'gui-local-companion-boundary' `
    -Requirement 'The website GUI must hand trusted actions to local PC software instead of doing builds in browser JavaScript.' `
    -Status ($(if ($InvokedByCompanion) { 'pass' } else { 'not-applicable' })) `
    -Evidence ($(if ($InvokedByCompanion) { 'Companion invoked this validator through /api/validate-workflow.' } else { 'Run through CLI; companion boundary is covered by validate-builder-companion-workflow.ps1.' }))

$validateSummaryPath = Join-Path $artifactRoot 'validate-config-summary.expected.json'
$validateStep = Invoke-ToolStep `
    -Name 'validate-config' `
    -Arguments @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $ProjectPath 'tools\validate-questionnaire-config.ps1'),
        '-ConfigPath',
        $ConfigPath,
        '-ReferenceProjectPath',
        $ReferenceProjectPath
    )
Add-Requirement `
    -Id 'questionnaire-config-valid' `
    -Requirement 'The GUI-generated questionnaire config must pass schema, item-count, and handoff validation.' `
    -Status (Get-StepStatus $validateStep) `
    -Evidence $validateStep.log

$generatorRunId = "$RunId-generator"
$generatorSummaryPath = Join-Path $ProjectPath "artifacts\apk-generator\$generatorRunId\generator-summary.json"
$generatorArgs = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $ProjectPath 'tools\generate-questionnaire-apk.ps1'),
    '-ConfigPath',
    $ConfigPath,
    '-ReferenceProjectPath',
    $ReferenceProjectPath,
    '-RunId',
    $generatorRunId
)
if ($SkipApkBuild) {
    $generatorArgs += '-SkipBuild'
}
if ($SkipQuestionnaireRender) {
    $generatorArgs += '-SkipTests'
} else {
    $generatorArgs += '-RenderPreview'
}
$generatorStep = Invoke-ToolStep -Name 'generate-questionnaire-apk-and-render' -Arguments $generatorArgs -SummaryPath $generatorSummaryPath
$generatorSummary = Read-JsonIfExists -Path $generatorSummaryPath
if ([string]::IsNullOrWhiteSpace($QuestionnaireApk) -and $null -ne $generatorSummary -and $generatorSummary.apk) {
    $QuestionnaireApk = [string]$generatorSummary.apk
}
if ([string]::IsNullOrWhiteSpace($QuestionnaireApk)) {
    $candidateApk = Join-Path $ProjectPath ("Builds\$questionnaireId-$questionnaireVersion.apk")
    if (Test-Path -LiteralPath $candidateApk) {
        $QuestionnaireApk = $candidateApk
    }
}

$apkEvidence = if (-not [string]::IsNullOrWhiteSpace($QuestionnaireApk)) { $QuestionnaireApk } else { $generatorStep.log }
$apkStatus = if ($SkipApkBuild -and [string]::IsNullOrWhiteSpace($QuestionnaireApk)) { 'skipped' } else { Get-StepStatus $generatorStep }
$questionnaireApkFacts = Get-FileEvidence -Path $QuestionnaireApk
Add-Requirement `
    -Id 'pc-software-generates-questionnaire-apk' `
    -Requirement 'Local PC software must generate the questionnaire APK requested by the GUI config.' `
    -Status $apkStatus `
    -Evidence $apkEvidence `
    -Notes ($(if ($SkipApkBuild) { 'APK build was skipped for this run.' } else { '' })) `
    -Facts ([ordered]@{
        apk = $questionnaireApkFacts
        generatorSummary = $generatorSummaryPath
        generatorStatus = if ($generatorSummary) { $generatorSummary.status } else { '' }
        skippedBuild = [bool]$SkipApkBuild
    })

$renderStatus = 'skipped'
$renderEvidence = ''
$questionnaireRenderFacts = $null
if (-not $SkipQuestionnaireRender -and $null -ne $generatorSummary -and $generatorSummary.renderSummary) {
    $renderEvidence = [string]$generatorSummary.renderSummary
    $questionnaireRenderFacts = Get-RenderEvidence -SummaryPath $renderEvidence
    $renderStatus = if ($questionnaireRenderFacts.exists) { 'pass' } else { 'fail' }
}
Add-Requirement `
    -Id 'questionnaire-local-render-pack' `
    -Requirement 'The generated questionnaire must have local Android-fidelity render evidence before headset screenshots.' `
    -Status $renderStatus `
    -Evidence $renderEvidence `
    -Facts $questionnaireRenderFacts

$temporalAssetStep = Invoke-ToolStep `
    -Name 'temporal-tracer-assets' `
    -Arguments @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $TemporalTracerPath 'tools\validate-temporal-tracer-assets.ps1')
    )
Add-Requirement `
    -Id 'temporal-tracer-assets-valid' `
    -Requirement 'Temporal tracer assets/config must validate before a tracer block is assigned to trigger 2.' `
    -Status (Get-StepStatus $temporalAssetStep) `
    -Evidence $temporalAssetStep.log

$temporalRenderSummaryPath = $null
$temporalRenderStep = $null
if (-not $SkipTemporalRender) {
    $temporalRenderRoot = Join-Path $artifactRoot 'temporal-render'
    $temporalRenderSummaryPath = Join-Path $temporalRenderRoot 'render-summary.json'
    $temporalRenderStep = Invoke-ToolStep `
        -Name 'temporal-tracer-local-render' `
        -Arguments @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            (Join-Path $TemporalTracerPath 'tools\render-temporal-tracer-visuals.ps1'),
            '-OutputRoot',
            $temporalRenderRoot,
            '-RunId',
            'render',
            '-Sizes',
            '1280x800,900x800'
        ) `
        -SummaryPath $temporalRenderSummaryPath
}
$temporalRenderFacts = if ($temporalRenderSummaryPath) { Get-RenderEvidence -SummaryPath $temporalRenderSummaryPath } else { $null }
Add-Requirement `
    -Id 'temporal-tracer-local-render-pack' `
    -Requirement 'Temporal tracer blocks must have local render evidence for layout, labels, and start/end gates.' `
    -Status ($(if ($SkipTemporalRender) { 'skipped' } else { Get-StepStatus $temporalRenderStep })) `
    -Evidence ($(if ($temporalRenderSummaryPath) { $temporalRenderSummaryPath } else { '' })) `
    -Facts $temporalRenderFacts

$temporalBuildStep = $null
if (-not $SkipTemporalApkBuild -and -not $SkipApkBuild) {
    $temporalBuildStep = Invoke-ToolStep `
        -Name 'temporal-tracer-apk-build' `
        -Arguments @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            (Join-Path $TemporalTracerPath 'tools\build-apk.ps1')
        )
}
if (Test-Path -LiteralPath $TemporalTracerApk) {
    Add-Requirement `
        -Id 'temporal-tracer-apk-available' `
        -Requirement 'The reusable temporal tracer APK must be available for Quest handoff preflight.' `
        -Status 'pass' `
        -Evidence $TemporalTracerApk `
        -Facts (Get-FileEvidence -Path $TemporalTracerApk)
} else {
    Add-Requirement `
        -Id 'temporal-tracer-apk-available' `
        -Requirement 'The reusable temporal tracer APK must be available for Quest handoff preflight.' `
        -Status ($(if ($SkipApkBuild -or $SkipTemporalApkBuild) { 'skipped' } else { Get-StepStatus $temporalBuildStep })) `
        -Evidence ($(if ($temporalBuildStep) { $temporalBuildStep.log } else { $TemporalTracerApk })) `
        -Facts (Get-FileEvidence -Path $TemporalTracerApk)
}

$unityStatic = $null
if (-not $SkipUnityStatic) {
    $unityStatic = Test-UnityDirectHandoffBridge -OutputDir $staticDir
    $steps.Add([ordered]@{
        name = 'unity-direct-handoff-bridge-static'
        status = [string]$unityStatic.Status
        exitCode = if ($unityStatic.Status -eq 'pass') { 0 } else { 1 }
        started = $null
        completed = (Get-Date).ToUniversalTime().ToString('o')
        log = $null
        summaryPath = $unityStatic.SummaryPath
        summary = $unityStatic.Summary
    }) | Out-Null
}
Add-Requirement `
    -Id 'unity-bridge-pendingintent-contract' `
    -Requirement 'The Unity bridge must create mq.returnPendingIntent and read completion/export extras.' `
    -Status ($(if ($SkipUnityStatic) { 'skipped' } else { [string]$unityStatic.Status })) `
    -Evidence ($(if ($unityStatic) { $unityStatic.SummaryPath } else { '' }))

$dryRunSummaryPath = Join-Path $artifactRoot 'quest-direct-handoff-dry-run\quest-direct-handoff-validation-summary.json'
$dryRunStatus = 'skipped'
$dryRunEvidence = ''
$dryRunFacts = $null
if (-not [string]::IsNullOrWhiteSpace($QuestionnaireApk) -and (Test-Path -LiteralPath $QuestionnaireApk)) {
    $dryRunOutputRoot = Join-Path $artifactRoot 'quest-direct-handoff-dry-run'
    $dryRunStep = Invoke-ToolStep `
        -Name 'quest-direct-handoff-apk-preflight-dry-run' `
        -Arguments @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            (Join-Path $ProjectPath 'tools\quest-direct-handoff-validate.ps1'),
            '-QuestionnaireApk',
            $QuestionnaireApk,
            '-TemporalTracerApk',
            $TemporalTracerApk,
            '-UnityApk',
            $UnityApk,
            '-OutputRoot',
            $dryRunOutputRoot,
            '-FastVideoForValidation',
            '-AutoTraceForValidation',
            '-DryRun'
        ) `
        -SummaryPath $dryRunSummaryPath
    $dryRunStatus = Get-StepStatus $dryRunStep
    $dryRunEvidence = $dryRunSummaryPath
    $dryRunFacts = Get-DirectPreflightEvidence -SummaryPath $dryRunSummaryPath
} else {
    $dryRunEvidence = 'Questionnaire APK is missing; dry-run preflight requires a built APK.'
}
Add-Requirement `
    -Id 'direct-handoff-apk-preflight' `
    -Requirement 'Questionnaire, tracer, and Unity APK package/activity/catalog identities must agree before headset trials.' `
    -Status $dryRunStatus `
    -Evidence $dryRunEvidence `
    -Facts $dryRunFacts

$questAdbStep = $null
$questAdbFacts = $null
if ($RunQuestReadiness -or $RunQuestDirectHandoff) {
    $questReadinessRoot = Join-Path $artifactRoot 'quest-adb-readiness'
    $questAdbArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $ProjectPath 'tools\quest-adb-readiness.ps1'),
        '-ProjectPath',
        $ProjectPath,
        '-OutputRoot',
        $questReadinessRoot,
        '-WaitSeconds',
        '0'
    )
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $questAdbArgs += @('-ExpectedSerial', $Serial)
    }
    $questAdbStep = Invoke-ToolStep `
        -Name 'quest-adb-readiness' `
        -Arguments $questAdbArgs `
        -SummaryPath (Join-Path $questReadinessRoot 'quest-adb-readiness-summary.json') `
        -NonZeroStatus 'warn'
    $questAdbFacts = Get-QuestAdbEvidence -SummaryPath $questAdbStep.summaryPath
}
Add-Requirement `
    -Id 'quest-adb-transport' `
    -Requirement 'Quest ADB transport must be online before install/launch stress validation.' `
    -Status ($(if ($RunQuestReadiness -or $RunQuestDirectHandoff) { Get-StepStatus $questAdbStep } else { 'pending' })) `
    -Evidence ($(if ($questAdbStep) { $questAdbStep.summaryPath } else { 'Quest check was not requested.' })) `
    -Facts $questAdbFacts

$directQuestStatus = 'pending'
$directQuestEvidence = 'Direct Quest handoff trials were not requested.'
$directQuestSummary = $null
$directQuestFacts = $null
if ($RunQuestDirectHandoff) {
    if ([string]::IsNullOrWhiteSpace($Serial)) {
        $directQuestStatus = 'blocked'
        $directQuestEvidence = 'RunQuestDirectHandoff requires -Serial.'
    } elseif ([string]::IsNullOrWhiteSpace($QuestionnaireApk) -or -not (Test-Path -LiteralPath $QuestionnaireApk)) {
        $directQuestStatus = 'blocked'
        $directQuestEvidence = 'RunQuestDirectHandoff requires a built questionnaire APK.'
    } else {
        $directQuestRoot = Join-Path $artifactRoot 'quest-direct-handoff'
        $directArgs = @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            (Join-Path $ProjectPath 'tools\quest-direct-handoff-validate.ps1'),
            '-Serial',
            $Serial,
            '-QuestionnaireApk',
            $QuestionnaireApk,
            '-TemporalTracerApk',
            $TemporalTracerApk,
            '-UnityApk',
            $UnityApk,
            '-OutputRoot',
            $directQuestRoot,
            '-TrialCount',
            "$QuestTrials",
            '-WaitForReadySeconds',
            "$WaitForReadySeconds",
            '-FastVideoForValidation',
            '-AutoTraceForValidation'
        )
        if ($SkipInstall) {
            $directArgs += '-SkipInstall'
        }
        $directStep = Invoke-ToolStep `
            -Name 'quest-direct-pendingintent-handoff' `
            -Arguments $directArgs `
            -SummaryPath (Join-Path $directQuestRoot 'quest-direct-handoff-validation-summary.json') `
            -NonZeroStatus 'blocked'
        $directQuestSummary = $directStep.summary
        if ($null -ne $directQuestSummary) {
            $directQuestStatus = [string]$directQuestSummary.status
            $directQuestEvidence = $directStep.summaryPath
            $directQuestFacts = [ordered]@{
                status = $directQuestSummary.status
                passCount = $directQuestSummary.passCount
                warnCount = $directQuestSummary.warnCount
                blockedCount = $directQuestSummary.blockedCount
                failCount = $directQuestSummary.failCount
                decisionGate = $directQuestSummary.decisionGate
            }
        } else {
            $directQuestStatus = Get-StepStatus $directStep
            $directQuestEvidence = $directStep.log
        }
    }
}
Add-Requirement `
    -Id 'direct-pendingintent-quest-trials' `
    -Requirement "Direct XR -> 2D panel -> same XR PendingIntent handoff must pass $QuestTrials/$QuestTrials Quest trials without shell foreground switching after initial launch." `
    -Status $directQuestStatus `
    -Evidence $directQuestEvidence `
    -Notes 'This remains the decisive Candidate A gate.' `
    -Facts $directQuestFacts

$requirementArray = @($requirements.ToArray())
$stepArray = @($steps.ToArray())
$failedCount = @($requirementArray | Where-Object { $_.status -eq 'fail' }).Count
$blockedCount = @($requirementArray | Where-Object { $_.status -eq 'blocked' }).Count
$pendingCount = @($requirementArray | Where-Object { $_.status -eq 'pending' }).Count
$warnCount = @($requirementArray | Where-Object { $_.status -eq 'warn' }).Count
$skippedCount = @($requirementArray | Where-Object { $_.status -eq 'skipped' }).Count

$overallStatus = 'pass'
if ($failedCount -gt 0) {
    $overallStatus = 'fail'
} elseif ($blockedCount -gt 0) {
    $overallStatus = 'blocked'
} elseif ($pendingCount -gt 0 -or $warnCount -gt 0 -or $skippedCount -gt 0) {
    $overallStatus = 'warn'
}

$summary = [ordered]@{
    schemaVersion = 'mq.builder_to_quest.workflow_validation.v1'
    status = $overallStatus
    runId = $RunId
    invokedByCompanion = [bool]$InvokedByCompanion
    artifactRoot = $artifactRoot
    projectPath = $ProjectPath
    repoRoot = $RepoRoot
    configPath = $ConfigPath
    questionnaireApk = $QuestionnaireApk
    temporalTracerApk = $TemporalTracerApk
    unityApk = $UnityApk
    serial = $Serial
    evidence = [ordered]@{
        questionnaireApk = Get-FileEvidence -Path $QuestionnaireApk
        temporalTracerApk = Get-FileEvidence -Path $TemporalTracerApk
        unityApk = Get-FileEvidence -Path $UnityApk
        questionnaireRender = $questionnaireRenderFacts
        temporalTracerRender = $temporalRenderFacts
        directHandoffPreflight = $dryRunFacts
        questAdb = $questAdbFacts
        directQuestHandoff = $directQuestFacts
    }
    counts = [ordered]@{
        requirements = $requirementArray.Count
        failed = $failedCount
        blocked = $blockedCount
        pending = $pendingCount
        warn = $warnCount
        skipped = $skippedCount
    }
    requirements = $requirementArray
    steps = $stepArray
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $artifactRoot 'builder-to-quest-workflow-summary.json'
Write-Json -Value $summary -Path $summaryPath -Depth 18

[pscustomobject]@{
    Status = $overallStatus
    Failed = $failedCount
    Blocked = $blockedCount
    Pending = $pendingCount
    Warn = $warnCount
    Skipped = $skippedCount
    Summary = $summaryPath
}
