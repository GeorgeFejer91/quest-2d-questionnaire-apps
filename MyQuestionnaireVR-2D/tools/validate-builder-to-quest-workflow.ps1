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
    [switch]$DryRunQuestDirectHandoff,
    [switch]$WakeBeforeReadiness,
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

. (Join-Path $PSScriptRoot 'source-asset-snapshot.ps1')

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

function ConvertFrom-PngBigEndianUInt32 {
    param([byte[]]$Bytes, [int]$Offset)

    return (
        ([uint32]$Bytes[$Offset] -shl 24) -bor
        ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
        ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
        [uint32]$Bytes[$Offset + 3]
    )
}

function Get-PngEvidence {
    param([string]$Path, [object]$Render = $null)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            exists = $false
            path = $Path
            validPng = $false
        }
    }

    $evidence = Get-FileEvidence -Path $Path
    $evidence.validPng = $false
    $evidence.width = 0
    $evidence.height = 0

    if (-not $evidence.exists) {
        return $evidence
    }

    try {
        $buffer = New-Object byte[] 24
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $read = $stream.Read($buffer, 0, $buffer.Length)
        } finally {
            $stream.Dispose()
        }
        $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
        $signatureMatches = $read -ge 24
        for ($i = 0; $i -lt $signature.Length -and $signatureMatches; $i++) {
            if ($buffer[$i] -ne $signature[$i]) {
                $signatureMatches = $false
            }
        }
        if ($signatureMatches) {
            $evidence.validPng = $true
            $evidence.width = [int](ConvertFrom-PngBigEndianUInt32 -Bytes $buffer -Offset 16)
            $evidence.height = [int](ConvertFrom-PngBigEndianUInt32 -Bytes $buffer -Offset 20)
        }
    } catch {
        $evidence.pngReadError = $_.Exception.Message
    }

    if ($null -ne $Render) {
        $expectedBytes = if ($Render.PSObject.Properties.Name -contains 'byteLength') { [int64]$Render.byteLength } else { 0 }
        $expectedHash = if ($Render.PSObject.Properties.Name -contains 'sha256') { [string]$Render.sha256 } else { "" }
        $expectedWidth = if ($Render.PSObject.Properties.Name -contains 'widthDp') { [int]$Render.widthDp } else { 0 }
        $expectedHeight = if ($Render.PSObject.Properties.Name -contains 'heightDp') { [int]$Render.heightDp } else { 0 }

        $evidence.matchesSummaryByteLength = ($expectedBytes -le 0 -or [int64]$evidence.bytes -eq $expectedBytes)
        $evidence.matchesSummarySha256 = ([string]::IsNullOrWhiteSpace($expectedHash) -or [string]$evidence.sha256 -eq $expectedHash)
        $evidence.matchesRenderDimensions = (
            ($expectedWidth -le 0 -or [int]$evidence.width -eq $expectedWidth) -and
            ($expectedHeight -le 0 -or [int]$evidence.height -eq $expectedHeight)
        )
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
    $pngFiles = @($renders | ForEach-Object {
        $pngEvidence = Get-PngEvidence -Path ([string]$_.png) -Render $_
        [pscustomobject][ordered]@{
            stageName = [string]$_.stageName
            language = [string]$_.language
            size = "$($_.widthDp)x$($_.heightDp)"
            status = [string]$_.status
            png = $pngEvidence
        }
    })
    $missingPngs = @($pngFiles | Where-Object { -not $_.png.exists })
    $invalidPngs = @($pngFiles | Where-Object { $_.png.exists -and -not $_.png.validPng })
    $zeroBytePngs = @($pngFiles | Where-Object { $_.png.exists -and [int64]$_.png.bytes -le 0 })
    $dimensionMismatches = @($pngFiles | Where-Object { $_.png.exists -and ($_.png.PSObject.Properties.Name -contains 'matchesRenderDimensions') -and -not $_.png.matchesRenderDimensions })
    $byteMismatches = @($pngFiles | Where-Object { $_.png.exists -and ($_.png.PSObject.Properties.Name -contains 'matchesSummaryByteLength') -and -not $_.png.matchesSummaryByteLength })
    $hashMismatches = @($pngFiles | Where-Object { $_.png.exists -and ($_.png.PSObject.Properties.Name -contains 'matchesSummarySha256') -and -not $_.png.matchesSummarySha256 })
    $artifactGatePass = (
        $renders.Count -gt 0 -and
        $pngs.Count -gt 0 -and
        @($renders | Where-Object { $_.status -eq 'fail' }).Count -eq 0 -and
        $missingPngs.Count -eq 0 -and
        $invalidPngs.Count -eq 0 -and
        $zeroBytePngs.Count -eq 0 -and
        $dimensionMismatches.Count -eq 0 -and
        $byteMismatches.Count -eq 0 -and
        $hashMismatches.Count -eq 0
    )

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
        pngFileCount = @($pngFiles | Where-Object { $_.png.exists }).Count
        missingPngCount = $missingPngs.Count
        invalidPngCount = $invalidPngs.Count
        zeroBytePngCount = $zeroBytePngs.Count
        dimensionMismatchCount = $dimensionMismatches.Count
        byteLengthMismatchCount = $byteMismatches.Count
        sha256MismatchCount = $hashMismatches.Count
        uniquePngHashes = @($pngFiles | Where-Object { $_.png.exists -and $_.png.sha256 } | ForEach-Object { $_.png.sha256 } | Select-Object -Unique).Count
        passesArtifactGate = $artifactGatePass
        stages = @($renders | ForEach-Object { $_.stageName } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        sizes = @($renders | ForEach-Object { "$($_.widthDp)x$($_.heightDp)" } | Where-Object { $_ -notmatch '^x$' } | Select-Object -Unique)
        languages = @($renders | ForEach-Object { $_.language } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        samplePngs = @($pngs | Select-Object -First 3)
        samplePngEvidence = @($pngFiles | Select-Object -First 3)
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
    Add-Check -Name 'handled result clear method' -Pass (Test-Text $bridgeText 'ClearQuestionnaireResult\s*\(.*?setIntent') -Detail 'Unity can clear consumed completion extras to avoid stale panel results.'
    Add-Check -Name 'PendingIntent request key includes trigger block identity' -Pass ((Test-Text $bridgeText 'requestKey.*?mq\.triggerId.*?mq\.chainStepId.*?mq\.blockId') -and (Test-Text $bridgeText 'mq\.pendingIntentRequestKey') -and (Test-Text $bridgeText 'GetHashCode\s*\(\s*\)')) -Detail 'Return PendingIntent request codes vary by trigger/chain step/block.'

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

function Test-PanelReturnContracts {
    param([string]$OutputDir)

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $checks = New-Object 'System.Collections.Generic.List[object]'

    function Add-Check {
        param([string]$Name, [bool]$Pass, [string]$Detail)
        $checks.Add([ordered]@{
            name = $Name
            pass = $Pass
            detail = $Detail
        }) | Out-Null
    }

    function Get-Text {
        param([string]$Path)
        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw
        }
        return ''
    }

    function Test-Text {
        param([string]$Text, [string]$Pattern)
        return [bool]([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline))
    }

    function Test-Order {
        param([string]$Text, [string]$FirstPattern, [string]$SecondPattern)
        $first = [regex]::Match($Text, $FirstPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $second = [regex]::Match($Text, $SecondPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        return $first.Success -and $second.Success -and $first.Index -lt $second.Index
    }

    $questionnaireManifestPath = Join-Path $ProjectPath 'app\src\main\AndroidManifest.xml'
    $questionnaireContextPath = Join-Path $ProjectPath 'app\src\main\java\org\viscereality\questionnaires2d\QuestionnaireLaunchContext.java'
    $questionnaireMainPath = Join-Path $ProjectPath 'app\src\main\java\org\viscereality\questionnaires2d\MainActivity.java'
    $tracerManifestPath = Join-Path $TemporalTracerPath 'app\src\main\AndroidManifest.xml'
    $tracerContextPath = Join-Path $TemporalTracerPath 'app\src\main\java\org\viscereality\temporaltracer2d\TemporalTracerLaunchContext.java'
    $tracerMainPath = Join-Path $TemporalTracerPath 'app\src\main\java\org\viscereality\temporaltracer2d\MainActivity.java'

    $questionnaireManifest = Get-Text -Path $questionnaireManifestPath
    $questionnaireContext = Get-Text -Path $questionnaireContextPath
    $questionnaireMain = Get-Text -Path $questionnaireMainPath
    $tracerManifest = Get-Text -Path $tracerManifestPath
    $tracerContext = Get-Text -Path $tracerContextPath
    $tracerMain = Get-Text -Path $tracerMainPath

    Add-Check -Name 'questionnaire manifest panel activity' -Pass (Test-Text $questionnaireManifest 'android:name="\.MainActivity".*?android:exported="true".*?android:launchMode="singleTop".*?android:resizeableActivity="true".*?org\.viscereality\.questionnaires2d\.RUN') -Detail $questionnaireManifestPath
    Add-Check -Name 'questionnaire return extra and pending intent extraction' -Pass (Test-Text $questionnaireContext 'EXTRA_RETURN_PENDING_INTENT\s*=\s*"mq\.returnPendingIntent".*?pendingIntentExtra\(intent,\s*EXTRA_RETURN_PENDING_INTENT\)') -Detail $questionnaireContextPath
    Add-Check -Name 'questionnaire completion result extras' -Pass (Test-Text $questionnaireContext 'EXTRA_RESULT_STATUS.*?EXTRA_EXPORT_JSON_PATH.*?EXTRA_EXPORT_CSV_PATH.*?EXTRA_QUESTIONNAIRE_CONFIG_ID') -Detail 'Questionnaire completion extras include status, exports, and config id.'
    Add-Check -Name 'questionnaire sends return token' -Pass (Test-Text $questionnaireContext 'void\s+sendReturnPendingIntent.*?addCompletionExtras\(fillIn,\s*export,\s*record\).*?returnPendingIntent\.send\(context,\s*0,\s*fillIn\)') -Detail 'Questionnaire fills result extras before sending PendingIntent.'
    Add-Check -Name 'questionnaire exports before post-export return' -Pass (Test-Text $questionnaireMain 'QuestionnaireData\.SessionRecord\s+record\s*=\s*buildSessionRecord\(\).*?QuestionnaireExporter\.writeSession\(this,\s*record\).*?showSavedConfirmation\(export\).*?handlePostExport\(export,\s*record\)') -Detail $questionnaireMainPath
    Add-Check -Name 'questionnaire tries PendingIntent before fallback' -Pass (Test-Order $questionnaireMain 'launchContext\.sendReturnPendingIntent\(this,\s*export,\s*record\)' 'launchContext\.completionIntent\(this,\s*export,\s*record\)') -Detail 'Questionnaire return token is attempted before explicit caller fallback.'
    Add-Check -Name 'questionnaire pending intent log marker' -Pass (Test-Text $questionnaireMain 'MYQUESTIONNAIRE_CHAIN_RETURN_PENDING_INTENT') -Detail 'Direct validator can observe questionnaire PendingIntent return.'

    Add-Check -Name 'temporal tracer manifest panel activity' -Pass (Test-Text $tracerManifest 'android:name="\.MainActivity".*?android:exported="true".*?android:launchMode="singleTop".*?android:resizeableActivity="true".*?org\.viscereality\.temporaltracer2d\.RUN') -Detail $tracerManifestPath
    Add-Check -Name 'temporal tracer return extra and pending intent extraction' -Pass (Test-Text $tracerContext 'EXTRA_RETURN_PENDING_INTENT\s*=\s*"mq\.returnPendingIntent".*?pendingIntentExtra\(intent,\s*EXTRA_RETURN_PENDING_INTENT\)') -Detail $tracerContextPath
    Add-Check -Name 'temporal tracer completion result extras' -Pass (Test-Text $tracerContext 'EXTRA_RESULT_STATUS.*?EXTRA_EXPORT_JSON_PATH.*?EXTRA_EXPORT_CSV_PATH.*?EXTRA_EXPORT_SVG_PATH.*?EXTRA_TRACER_CONFIG_ID') -Detail 'Tracer completion extras include status, JSON/CSV/SVG exports, and config id.'
    Add-Check -Name 'temporal tracer sends return token' -Pass (Test-Text $tracerContext 'void\s+sendReturnPendingIntent.*?addCompletionExtras\(fillIn,\s*lastExport,\s*config\).*?returnPendingIntent\.send\(context,\s*0,\s*fillIn\)') -Detail 'Tracer fills result extras before sending PendingIntent.'
    Add-Check -Name 'temporal tracer exports before saved return screen' -Pass (Test-Text $tracerMain 'lastExport\s*=\s*exporter\.exportTrace\(.*?exporter\.writeDraft\(launch,\s*config,\s*language,\s*participantId,\s*participantName,\s*traceIndex,\s*completedTraceCount\).*?exporter\.markDraftComplete\(launch\).*?showSaved\("SVG:') -Detail $tracerMainPath
    Add-Check -Name 'temporal tracer tries PendingIntent before fallback' -Pass (Test-Order $tracerMain 'launch\.sendReturnPendingIntent\(this,\s*lastExport,\s*config\)' 'launch\.completionIntent\(this,\s*lastExport,\s*config\)') -Detail 'Tracer return token is attempted before explicit caller fallback.'
    Add-Check -Name 'temporal tracer pending intent log marker' -Pass (Test-Text $tracerMain 'TEMPORAL_TRACER_RETURN_PENDING_INTENT') -Detail 'Direct validator can observe tracer PendingIntent return.'

    $checkArray = @($checks.ToArray())
    $failed = @($checkArray | Where-Object { -not $_.pass })
    $summary = [ordered]@{
        schemaVersion = 'mq.panel_return_contracts_static.v1'
        status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
        checkCount = $checkArray.Count
        failedCount = $failed.Count
        checks = $checkArray
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $summaryPath = Join-Path $OutputDir 'panel-return-contracts-static-summary.json'
    Write-Json -Value $summary -Path $summaryPath -Depth 10
    return [pscustomobject]@{
        Status = $summary.status
        SummaryPath = $summaryPath
        Summary = $summary
    }
}

function Test-TriggerBlockMapping {
    param([object]$Config, [string]$OutputDir)

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $checks = New-Object 'System.Collections.Generic.List[object]'

    function Add-Check {
        param([string]$Name, [bool]$Pass, [string]$Detail)
        $checks.Add([ordered]@{
            name = $Name
            pass = $Pass
            detail = $Detail
        }) | Out-Null
    }

    function Get-Prop {
        param([object]$Object, [string]$Name, [object]$Default = $null)
        if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
            return $Object.PSObject.Properties[$Name].Value
        }
        return $Default
    }

    function Test-Unique {
        param([object[]]$Values)
        $usable = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        return $usable.Count -gt 0 -and @($usable | Select-Object -Unique).Count -eq $usable.Count
    }

    $mapping = Get-Prop -Object $Config -Name 'triggerQuestionnaireMapping'
    $registry = Get-Prop -Object $Config -Name 'experimentBlockRegistry'
    $mappingTriggers = if ($mapping) { @($mapping.triggers) } else { @() }
    $enabledMappings = @($mappingTriggers | Where-Object { [bool]$_.enabled -and [string]$_.questionnaireMode -ne 'none' })
    $registryBlocks = if ($registry) { @($registry.blocks) } else { @() }
    $sourceCatalog = if ($registry) { Get-Prop -Object $registry -Name 'sourceTriggerCatalog' } else { $null }
    $scenario = if ($registry) { Get-Prop -Object $registry -Name 'scenario' } else { $null }

    Add-Check -Name 'trigger mapping present' -Pass ($null -ne $mapping) -Detail 'Config must include triggerQuestionnaireMapping from the APK trigger catalog.'
    Add-Check -Name 'trigger mapping schema' -Pass ([string](Get-Prop $mapping 'schemaVersion') -eq 'mq.quest_questionnaire_trigger_mapping.v1') -Detail 'triggerQuestionnaireMapping.schemaVersion'
    Add-Check -Name 'trigger mapping has enabled blocks' -Pass ($enabledMappings.Count -gt 0) -Detail "enabledTriggerCount=$($enabledMappings.Count)"
    Add-Check -Name 'trigger ids unique' -Pass (Test-Unique -Values @($mappingTriggers | ForEach-Object { $_.triggerId })) -Detail 'Each manifest trigger id must map once.'
    Add-Check -Name 'block numbers unique and three digit' -Pass ((Test-Unique -Values @($enabledMappings | ForEach-Object { $_.blockNumber })) -and @($enabledMappings | Where-Object { [string]$_.blockNumber -notmatch '^\d{3}$' }).Count -eq 0) -Detail 'Each enabled trigger must have a unique 001-style block number.'
    Add-Check -Name 'block ids unique' -Pass (Test-Unique -Values @($enabledMappings | ForEach-Object { $_.blockId })) -Detail 'Each enabled trigger must have a stable block id.'
    Add-Check -Name 'registry has one block per enabled trigger' -Pass ($registryBlocks.Count -eq $enabledMappings.Count) -Detail "registryBlocks=$($registryBlocks.Count); enabledTriggers=$($enabledMappings.Count)"
    Add-Check -Name 'source catalog count matches mapping' -Pass ($null -ne $sourceCatalog -and [int](Get-Prop $sourceCatalog 'triggerCount' 0) -eq $mappingTriggers.Count) -Detail 'experimentBlockRegistry.sourceTriggerCatalog.triggerCount'
    Add-Check -Name 'scenario package/activity propagated' -Pass (
        -not [string]::IsNullOrWhiteSpace([string](Get-Prop $mapping 'scenarioPackage')) -and
        [string](Get-Prop $mapping 'scenarioPackage') -eq [string](Get-Prop $scenario 'package') -and
        [string](Get-Prop $mapping 'scenarioActivity') -eq [string](Get-Prop $scenario 'activity')
    ) -Detail 'Scenario package/activity must be shared by mapping, registry, and caller return extras.'

    foreach ($trigger in $enabledMappings) {
        $triggerId = [string]$trigger.triggerId
        $mode = [string]$trigger.questionnaireMode
        $block = @($registryBlocks | Where-Object { [string]$_.id -eq [string]$trigger.blockId } | Select-Object -First 1)
        $block = if ($block.Count -gt 0) { $block[0] } else { $null }
        Add-Check -Name "block exists for $triggerId" -Pass ($null -ne $block) -Detail "blockId=$($trigger.blockId)"
        if ($null -eq $block) {
            continue
        }

        $expectedPackage = if ($mode -eq 'temporalTracer') { 'org.viscereality.temporaltracer2d' } else { 'org.viscereality.questionnaires2d' }
        $expectedAction = if ($mode -eq 'temporalTracer') { 'org.viscereality.temporaltracer2d.RUN' } else { 'org.viscereality.questionnaires2d.RUN' }
        $expectedActivity = if ($mode -eq 'temporalTracer') { 'org.viscereality.temporaltracer2d.MainActivity' } else { 'org.viscereality.questionnaires2d.MainActivity' }
        $expectedType = if ($mode -eq 'temporalTracer') { 'temporalTracer' } else { 'questionnaire' }
        $extras = Get-Prop -Object $block -Name 'extras'

        Add-Check -Name "block number/id match $triggerId" -Pass ([string]$block.number -eq [string]$trigger.blockNumber -and [string]$block.id -eq [string]$trigger.blockId) -Detail "block=$($block.number)/$($block.id); trigger=$($trigger.blockNumber)/$($trigger.blockId)"
        Add-Check -Name "block trigger id match $triggerId" -Pass ([string](Get-Prop $block.trigger 'triggerId') -eq $triggerId) -Detail "blockTrigger=$((Get-Prop $block.trigger 'triggerId'))"
        Add-Check -Name "block panel target match $triggerId" -Pass ([string]$block.type -eq $expectedType -and [string]$block.package -eq $expectedPackage -and [string]$block.activity -eq $expectedActivity -and [string]$block.action -eq $expectedAction) -Detail "mode=$mode package=$($block.package) action=$($block.action)"
        Add-Check -Name "block mode match $triggerId" -Pass ([string]$block.questionnaireMode -eq $mode) -Detail "mode=$mode"
        Add-Check -Name "handoff extras match $triggerId" -Pass (
            [string](Get-Prop $extras 'mq.handoffSchema') -eq 'mq.handoff.v1' -and
            [string](Get-Prop $extras 'mq.triggerId') -eq $triggerId -and
            [string](Get-Prop $extras 'mq.finishBehavior') -eq 'resumeCaller' -and
            [string](Get-Prop $extras 'mq.callerPackage') -eq [string](Get-Prop $mapping 'scenarioPackage') -and
            [string](Get-Prop $extras 'mq.callerActivity') -eq [string](Get-Prop $mapping 'scenarioActivity')
        ) -Detail 'Blocks must carry mq.handoff.v1 trigger and caller-return extras.'
    }

    $exampleCatalogPath = Join-Path $RepoRoot 'example-scenario-apk\questionnaire-trigger-catalog.json'
    $exampleCatalog = Read-JsonIfExists -Path $exampleCatalogPath
    if ($null -ne $exampleCatalog -and [string](Get-Prop $mapping 'scenarioId') -eq [string]$exampleCatalog.scenarioId) {
        $exampleTriggers = @($exampleCatalog.triggers)
        Add-Check -Name 'example catalog trigger count match' -Pass ($exampleTriggers.Count -eq $mappingTriggers.Count) -Detail $exampleCatalogPath
        foreach ($exampleTrigger in $exampleTriggers) {
            $mapped = @($mappingTriggers | Where-Object { [string]$_.triggerId -eq [string]$exampleTrigger.triggerId } | Select-Object -First 1)
            $mapped = if ($mapped.Count -gt 0) { $mapped[0] } else { $null }
            Add-Check -Name "example trigger mapped $($exampleTrigger.triggerId)" -Pass ($null -ne $mapped -and [string]$mapped.questionnaireMode -eq [string]$exampleTrigger.recommendedMode) -Detail "recommendedMode=$($exampleTrigger.recommendedMode)"
        }
    } else {
        Add-Check -Name 'example catalog available for comparison' -Pass ($null -ne $exampleCatalog) -Detail $exampleCatalogPath
    }

    $checkArray = @($checks.ToArray())
    $failed = @($checkArray | Where-Object { -not $_.pass })
    $summary = [ordered]@{
        schemaVersion = 'mq.trigger_block_mapping_static.v1'
        status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
        checkCount = $checkArray.Count
        failedCount = $failed.Count
        scenarioId = if ($mapping) { Get-Prop $mapping 'scenarioId' } else { '' }
        sourceApkName = if ($mapping) { Get-Prop $mapping 'sourceApkName' } else { '' }
        enabledTriggerCount = $enabledMappings.Count
        registryBlockCount = $registryBlocks.Count
        checks = $checkArray
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $summaryPath = Join-Path $OutputDir 'trigger-block-mapping-static-summary.json'
    Write-Json -Value $summary -Path $summaryPath -Depth 12
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

$triggerBlockMapping = Test-TriggerBlockMapping -Config $config -OutputDir $staticDir
$steps.Add([ordered]@{
    name = 'trigger-block-mapping-static'
    status = [string]$triggerBlockMapping.Status
    exitCode = if ($triggerBlockMapping.Status -eq 'pass') { 0 } else { 1 }
    started = $null
    completed = (Get-Date).ToUniversalTime().ToString('o')
    log = $null
    summaryPath = $triggerBlockMapping.SummaryPath
    summary = $triggerBlockMapping.Summary
}) | Out-Null
Add-Requirement `
    -Id 'trigger-block-mapping-contract' `
    -Requirement 'The APK trigger catalog must compile into one enabled block per trigger, with stable block ids/numbers, correct questionnaire or tracer targets, and mq.handoff.v1 caller-return extras.' `
    -Status ([string]$triggerBlockMapping.Status) `
    -Evidence $triggerBlockMapping.SummaryPath

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
$questionnaireAssetRoot = Join-Path $ProjectPath 'app\src\main\assets\questionnaire'
$questionnaireAssetSnapshotSummaryPath = Join-Path $artifactRoot 'questionnaire-source-assets-snapshot.json'
$questionnaireAssetRestoreSummaryPath = Join-Path $artifactRoot 'questionnaire-source-assets-restore.json'
$questionnaireAssetSnapshot = New-SourceAssetDirectorySnapshot `
    -SourceRoot $questionnaireAssetRoot `
    -SnapshotRoot (Join-Path $artifactRoot 'questionnaire-source-assets-snapshot') `
    -SummaryPath $questionnaireAssetSnapshotSummaryPath
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
$questionnaireAssetRestore = Restore-SourceAssetDirectorySnapshot -Snapshot $questionnaireAssetSnapshot -SourceRoot $questionnaireAssetRoot
Write-Json -Value $questionnaireAssetRestore -Path $questionnaireAssetRestoreSummaryPath -Depth 8
Add-Requirement `
    -Id 'workflow-preserves-source-assets' `
    -Requirement 'Workflow validation must restore packaged questionnaire source assets after temporary APK generation and render checks.' `
    -Status ([string]$questionnaireAssetRestore.status) `
    -Evidence $questionnaireAssetRestoreSummaryPath `
    -Facts $questionnaireAssetRestore
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
    $renderStatus = if ($questionnaireRenderFacts.exists -and $questionnaireRenderFacts.passesArtifactGate) { 'pass' } else { 'fail' }
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
    -Status ($(if ($SkipTemporalRender) { 'skipped' } elseif ($temporalRenderFacts -and $temporalRenderFacts.exists -and $temporalRenderFacts.passesArtifactGate) { Get-StepStatus $temporalRenderStep } else { 'fail' })) `
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

$panelReturnContracts = Test-PanelReturnContracts -OutputDir $staticDir
$steps.Add([ordered]@{
    name = 'panel-return-contracts-static'
    status = [string]$panelReturnContracts.Status
    exitCode = if ($panelReturnContracts.Status -eq 'pass') { 0 } else { 1 }
    started = $null
    completed = (Get-Date).ToUniversalTime().ToString('o')
    log = $null
    summaryPath = $panelReturnContracts.SummaryPath
    summary = $panelReturnContracts.Summary
}) | Out-Null
Add-Requirement `
    -Id 'panel-return-pendingintent-contract' `
    -Requirement 'The questionnaire and temporal tracer panels must save exports before returning, send mq.returnPendingIntent first, and keep caller package/activity fallback support.' `
    -Status ([string]$panelReturnContracts.Status) `
    -Evidence $panelReturnContracts.SummaryPath

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
$effectiveWakeBeforeReadiness = ([bool]$WakeBeforeReadiness -and -not [bool]$DryRunQuestDirectHandoff)
if ($RunQuestDirectHandoff) {
    if ([string]::IsNullOrWhiteSpace($Serial) -and -not $DryRunQuestDirectHandoff) {
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
        if (-not [string]::IsNullOrWhiteSpace($Serial)) {
            $directArgs += @('-Serial', $Serial)
        }
        if ($SkipInstall) {
            $directArgs += '-SkipInstall'
        }
        if ($DryRunQuestDirectHandoff) {
            $directArgs += '-DryRun'
        }
        if ($effectiveWakeBeforeReadiness) {
            $directArgs += '-WakeBeforeReadiness'
        }
        $directStep = Invoke-ToolStep `
            -Name 'quest-direct-pendingintent-handoff' `
            -Arguments $directArgs `
            -SummaryPath (Join-Path $directQuestRoot 'quest-direct-handoff-validation-summary.json') `
            -NonZeroStatus 'blocked'
        $directQuestSummary = $directStep.summary
        if ($null -ne $directQuestSummary) {
            $directQuestStatus = if ($DryRunQuestDirectHandoff -and [string]$directQuestSummary.status -eq 'pass') { 'warn' } else { [string]$directQuestSummary.status }
            $directQuestEvidence = $directStep.summaryPath
            $directQuestFacts = [ordered]@{
                status = $directQuestSummary.status
                dryRun = [bool]$DryRunQuestDirectHandoff
                wakeBeforeReadiness = [bool]$effectiveWakeBeforeReadiness
                requestedQuestTrials = $QuestTrials
                requestedWaitForReadySeconds = $WaitForReadySeconds
                trialCount = if ($directQuestSummary.PSObject.Properties.Name -contains 'trialCount') { $directQuestSummary.trialCount } else { $null }
                attemptedTrialCount = if ($directQuestSummary.PSObject.Properties.Name -contains 'attemptedTrialCount') { $directQuestSummary.attemptedTrialCount } else { $null }
                waitForReadySeconds = if ($directQuestSummary.PSObject.Properties.Name -contains 'waitForReadySeconds') { $directQuestSummary.waitForReadySeconds } else { $null }
                summaryWakeBeforeReadiness = if ($directQuestSummary.PSObject.Properties.Name -contains 'wakeBeforeReadiness') { $directQuestSummary.wakeBeforeReadiness } else { $null }
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
    -Notes ($(if ($DryRunQuestDirectHandoff) { 'Dry-run preflight only; this does not replace physical Quest trials.' } else { 'This remains the decisive Candidate A gate.' })) `
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
        questionnaireSourceAssets = [ordered]@{
            snapshot = $questionnaireAssetSnapshotSummaryPath
            restore = $questionnaireAssetRestore
        }
        triggerBlockMapping = $triggerBlockMapping.Summary
        panelReturnContracts = $panelReturnContracts.Summary
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
