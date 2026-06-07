param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR",
    [string]$RunId = "",
    [int]$Port = 0,
    [switch]$SkipApkBuild,
    [switch]$SkipRenderPreview
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "builder-companion-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$ReferenceProjectPath = [System.IO.Path]::GetFullPath($ReferenceProjectPath)
$artifactDir = Join-Path $ProjectPath ("artifacts\builder-companion-workflow\" + $RunId)
$builderOut = Join-Path $artifactDir 'builder'
$serverOut = Join-Path $artifactDir 'companion-stdout.txt'
$serverErr = Join-Path $artifactDir 'companion-stderr.txt'
$progressLog = Join-Path $artifactDir 'validator-progress.txt'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

function Add-Progress {
    param([string]$Message)

    $line = "$(Get-Date -Format o) $Message"
    Add-Content -LiteralPath $progressLog -Value $line -Encoding UTF8
    Write-Host $Message
}

function Get-FreeLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return [int]$listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function New-Token {
    $bytes = New-Object byte[] 18
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Invoke-Json {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body = $null,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 30
    )

    $arguments = @{
        Method = $Method
        Uri = $Uri
        Headers = $Headers
        TimeoutSec = $TimeoutSec
    }
    if ($null -ne $Body) {
        $arguments.ContentType = 'application/json'
        $arguments.Body = ($Body | ConvertTo-Json -Depth 100)
    }
    return Invoke-RestMethod @arguments
}

function Read-JsonIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Get-FileEvidence {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            exists = $false
            path = $Path
        }
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
            passesArtifactGate = $false
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

function Get-HttpErrorStatusCode {
    param([System.Exception]$Exception)

    if ($Exception.Response -and $Exception.Response.StatusCode) {
        return [int]$Exception.Response.StatusCode
    }
    if ($Exception.InnerException -and $Exception.InnerException.Response -and $Exception.InnerException.Response.StatusCode) {
        return [int]$Exception.InnerException.Response.StatusCode
    }
    return $null
}

function Wait-Companion {
    param([string]$BaseUrl)

    for ($attempt = 1; $attempt -le 60; $attempt++) {
        try {
            return Invoke-Json -Method GET -Uri "$BaseUrl/api/status"
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "Companion did not respond at $BaseUrl"
}

function Wait-WorkflowJob {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$RunId,
        [int]$TimeoutSec = 1800
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $encodedRunId = [System.Uri]::EscapeDataString($RunId)
    while ((Get-Date) -lt $deadline) {
        $job = Invoke-Json -Method GET -Uri "$BaseUrl/api/workflow-job?runId=$encodedRunId" -Headers $Headers -TimeoutSec 30
        if ($job.jobStatus -ne 'running') {
            return $job
        }
        Start-Sleep -Seconds 2
    }
    throw "Workflow job did not finish before timeout: $RunId"
}

function Wait-InstallApkJob {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$RunId,
        [int]$TimeoutSec = 600
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $encodedRunId = [System.Uri]::EscapeDataString($RunId)
    while ((Get-Date) -lt $deadline) {
        $job = Invoke-Json -Method GET -Uri "$BaseUrl/api/install-apk-job?runId=$encodedRunId" -Headers $Headers -TimeoutSec 30
        if ($job.jobStatus -ne 'running') {
            return $job
        }
        Start-Sleep -Seconds 2
    }
    throw "Install APK job did not finish before timeout: $RunId"
}

function Wait-QuestReplayJob {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$RunId,
        [int]$TimeoutSec = 900
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $encodedRunId = [System.Uri]::EscapeDataString($RunId)
    while ((Get-Date) -lt $deadline) {
        $job = Invoke-Json -Method GET -Uri "$BaseUrl/api/quest-replay-job?runId=$encodedRunId" -Headers $Headers -TimeoutSec 30
        if ($job.jobStatus -ne 'running') {
            return $job
        }
        Start-Sleep -Seconds 2
    }
    throw "Quest replay/export job did not finish before timeout: $RunId"
}

function Wait-DirectHandoffJob {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$RunId,
        [int]$TimeoutSec = 900
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $encodedRunId = [System.Uri]::EscapeDataString($RunId)
    while ((Get-Date) -lt $deadline) {
        $job = Invoke-Json -Method GET -Uri "$BaseUrl/api/direct-handoff-job?runId=$encodedRunId" -Headers $Headers -TimeoutSec 30
        if ($job.jobStatus -ne 'running') {
            return $job
        }
        Start-Sleep -Seconds 2
    }
    throw "Direct handoff job did not finish before timeout: $RunId"
}

if ($Port -le 0) {
    $Port = Get-FreeLoopbackPort
}
$baseUrl = "http://127.0.0.1:$Port"
$token = New-Token
$headers = @{ 'X-MQ-Builder-Token' = $token }

Write-Host "== Builder smoke output =="
Add-Progress 'builder-smoke-start'
& powershell -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $ProjectPath 'tools\validate-questionnaire-builder.ps1') `
    -ProjectPath $ProjectPath `
    -OutputDir $builderOut
if ($LASTEXITCODE -ne 0) {
    throw "Builder smoke output failed with exit code $LASTEXITCODE"
}
Add-Progress 'builder-smoke-complete'

$handoffConfigPath = Join-Path $builderOut 'awe-great-dictator-handoff.config.json'
if (-not (Test-Path -LiteralPath $handoffConfigPath)) {
    throw "Expected handoff config not found: $handoffConfigPath"
}
$handoffConfig = Get-Content -LiteralPath $handoffConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json

$companionScript = Join-Path $ProjectPath 'tools\start-questionnaire-builder-app.ps1'
$processArgs = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $companionScript,
    '-Port',
    $Port,
    '-ProjectPath',
    $ProjectPath,
    '-ReferenceProjectPath',
    $ReferenceProjectPath,
    '-Mode',
    'OnlineConnector',
    '-PairingToken',
    $token,
    '-NoOpen'
)

$process = $null
try {
    Add-Progress 'companion-start'
    $process = Start-Process -FilePath 'powershell' -ArgumentList $processArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $serverOut -RedirectStandardError $serverErr
    Add-Progress "companion-process-id=$($process.Id)"
    $statusNoToken = Wait-Companion -BaseUrl $baseUrl
    Add-Progress 'status-without-token-complete'
    $statusWithToken = Invoke-Json -Method GET -Uri "$baseUrl/api/status" -Headers $headers
    Add-Progress 'status-with-token-complete'
    if (-not $statusWithToken.authorized) {
        throw "Companion status did not accept the pairing token."
    }

    $unauthorizedDependencyStatus = $null
    $unauthorizedQuestReadinessStatus = $null
    $unauthorizedInstallApkStatus = $null
    $unauthorizedQuestReplayStatus = $null
    $unauthorizedDirectHandoffStatus = $null
    try {
        Invoke-Json -Method GET -Uri "$baseUrl/api/dependency-status" | Out-Null
        throw "Unauthorized dependency-status call unexpectedly succeeded."
    }
    catch {
        $unauthorizedDependencyStatus = Get-HttpErrorStatusCode -Exception $_.Exception
        if ($unauthorizedDependencyStatus -ne 401) {
            throw "Unauthorized dependency-status expected 401, got $unauthorizedDependencyStatus"
        }
    }
    try {
        Invoke-Json -Method POST -Uri "$baseUrl/api/quest-readiness" -Body @{ waitSeconds = 0 } | Out-Null
        throw "Unauthorized quest-readiness call unexpectedly succeeded."
    }
    catch {
        $unauthorizedQuestReadinessStatus = Get-HttpErrorStatusCode -Exception $_.Exception
        if ($unauthorizedQuestReadinessStatus -ne 401) {
            throw "Unauthorized quest-readiness expected 401, got $unauthorizedQuestReadinessStatus"
        }
    }
    try {
        Invoke-Json -Method POST -Uri "$baseUrl/api/install-apk" -Body @{ apk = "missing.apk"; dryRun = $true } | Out-Null
        throw "Unauthorized install-apk call unexpectedly succeeded."
    }
    catch {
        $unauthorizedInstallApkStatus = Get-HttpErrorStatusCode -Exception $_.Exception
        if ($unauthorizedInstallApkStatus -ne 401) {
            throw "Unauthorized install-apk expected 401, got $unauthorizedInstallApkStatus"
        }
    }
    try {
        Invoke-Json -Method POST -Uri "$baseUrl/api/quest-replay" -Body @{ apk = "missing.apk"; dryRun = $true } | Out-Null
        throw "Unauthorized quest-replay call unexpectedly succeeded."
    }
    catch {
        $unauthorizedQuestReplayStatus = Get-HttpErrorStatusCode -Exception $_.Exception
        if ($unauthorizedQuestReplayStatus -ne 401) {
            throw "Unauthorized quest-replay expected 401, got $unauthorizedQuestReplayStatus"
        }
    }
    try {
        Invoke-Json -Method POST -Uri "$baseUrl/api/direct-handoff" -Body @{ questionnaireApk = "missing.apk"; dryRun = $true } | Out-Null
        throw "Unauthorized direct-handoff call unexpectedly succeeded."
    }
    catch {
        $unauthorizedDirectHandoffStatus = Get-HttpErrorStatusCode -Exception $_.Exception
        if ($unauthorizedDirectHandoffStatus -ne 401) {
            throw "Unauthorized direct-handoff expected 401, got $unauthorizedDirectHandoffStatus"
        }
    }

    Write-Host "== Dependency status =="
    $dependency = Invoke-Json -Method GET -Uri "$baseUrl/api/dependency-status" -Headers $headers
    Add-Progress 'dependency-status-complete'
    if ($dependency.status -ne 'ok') {
        throw "Required local dependencies are missing. See companion summary."
    }

    Write-Host "== Quest readiness through companion =="
    $questReadiness = Invoke-Json -Method POST -Uri "$baseUrl/api/quest-readiness" -Headers $headers -Body @{ waitSeconds = 0 } -TimeoutSec 120
    Add-Progress "quest-readiness-complete readiness=$($questReadiness.readiness) status=$($questReadiness.readinessStatus) productPath=$($questReadiness.productPathStatus)"
    if ($questReadiness.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$questReadiness.summaryPath) -or -not (Test-Path -LiteralPath $questReadiness.summaryPath)) {
        throw "Companion quest-readiness did not produce a usable readiness summary."
    }

    Write-Host "== Install APK dry run through companion =="
    $installDryRunApk = Join-Path $artifactDir 'install-dry-run-placeholder.apk'
    Set-Content -LiteralPath $installDryRunApk -Value 'dry-run placeholder for companion install endpoint validation' -Encoding UTF8
    $installStart = Invoke-Json -Method POST -Uri "$baseUrl/api/install-apk" -Headers $headers -Body @{
        apk = $installDryRunApk
        questSerial = [string]$questReadiness.targetSerial
        waitSeconds = 0
        dryRun = $true
    } -TimeoutSec 60
    Add-Progress "install-apk-started=$($installStart.runId)"
    if ($installStart.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$installStart.runId)) {
        throw "Companion install-apk did not start an install job."
    }
    $installApk = if ($installStart.jobStatus -eq 'running') {
        Wait-InstallApkJob -BaseUrl $baseUrl -Headers $headers -RunId $installStart.runId -TimeoutSec 600
    }
    else {
        $installStart
    }
    Add-Progress "install-apk-complete jobStatus=$($installApk.jobStatus) installStatus=$($installApk.installStatus)"
    if ($installApk.installStatus -eq 'fail' -or [string]::IsNullOrWhiteSpace([string]$installApk.summaryPath) -or -not (Test-Path -LiteralPath $installApk.summaryPath)) {
        throw "Companion install-apk dry run did not produce a usable install summary."
    }

    Write-Host "== Quest replay/export dry run through companion =="
    $replayDryRunApk = Join-Path $artifactDir 'replay-dry-run-placeholder.apk'
    Set-Content -LiteralPath $replayDryRunApk -Value 'dry-run placeholder for companion quest replay endpoint validation' -Encoding UTF8
    $replayStart = Invoke-Json -Method POST -Uri "$baseUrl/api/quest-replay" -Headers $headers -Body @{
        apk = $replayDryRunApk
        questSerial = [string]$questReadiness.targetSerial
        waitSeconds = 1
        dryRun = $true
    } -TimeoutSec 60
    Add-Progress "quest-replay-started=$($replayStart.runId)"
    if ($replayStart.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$replayStart.runId)) {
        throw "Companion quest-replay did not start a replay/export job."
    }
    $questReplay = if ($replayStart.jobStatus -eq 'running') {
        Wait-QuestReplayJob -BaseUrl $baseUrl -Headers $headers -RunId $replayStart.runId -TimeoutSec 900
    }
    else {
        $replayStart
    }
    Add-Progress "quest-replay-complete jobStatus=$($questReplay.jobStatus) replayStatus=$($questReplay.replayStatus)"
    if ($questReplay.replayStatus -eq 'fail' -or [string]::IsNullOrWhiteSpace([string]$questReplay.summaryPath) -or -not (Test-Path -LiteralPath $questReplay.summaryPath)) {
        throw "Companion quest-replay dry run did not produce a usable replay summary."
    }

    Write-Host "== Direct PendingIntent handoff dry run through companion =="
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
    $questionnaireApkForDirect = Join-Path $ProjectPath 'Builds\viscereality-maia2-1.0.0.apk'
    if (-not (Test-Path -LiteralPath $questionnaireApkForDirect)) {
        $questionnaireApkForDirect = Join-Path $ProjectPath 'Builds\MyQuestionnaireVR-2D.apk'
    }
    $temporalTracerApkForDirect = Join-Path $repoRoot 'TemporalExperienceTracerVR-2D\Builds\TemporalExperienceTracerVR-2D.apk'
    $unityApkForDirect = Join-Path $repoRoot 'AweGreatDictatorUnity\Builds\QuestionnaireStimulusBuilderDemo.apk'
    $directHandoffRequiredApks = @($questionnaireApkForDirect, $temporalTracerApkForDirect, $unityApkForDirect)
    $missingDirectHandoffApks = @($directHandoffRequiredApks | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missingDirectHandoffApks.Count -gt 0) {
        throw "Direct handoff dry run needs real APKs for aapt preflight. Missing: $($missingDirectHandoffApks -join ', ')"
    }
    $directHandoffStart = Invoke-Json -Method POST -Uri "$baseUrl/api/direct-handoff" -Headers $headers -Body @{
        questionnaireApk = $questionnaireApkForDirect
        temporalTracerApk = $temporalTracerApkForDirect
        unityApk = $unityApkForDirect
        questSerial = [string]$questReadiness.targetSerial
        trialCount = 1
        waitForReadySeconds = 0
        waitSeconds = 1
        dryRun = $true
        skipInstall = $true
    } -TimeoutSec 60
    Add-Progress "direct-handoff-started=$($directHandoffStart.runId)"
    if ($directHandoffStart.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$directHandoffStart.runId)) {
        throw "Companion direct-handoff did not start a handoff job."
    }
    $directHandoff = if ($directHandoffStart.jobStatus -eq 'running') {
        Wait-DirectHandoffJob -BaseUrl $baseUrl -Headers $headers -RunId $directHandoffStart.runId -TimeoutSec 900
    }
    else {
        $directHandoffStart
    }
    Add-Progress "direct-handoff-complete jobStatus=$($directHandoff.jobStatus) handoffStatus=$($directHandoff.handoffStatus)"
    if ($directHandoff.handoffStatus -eq 'fail' -or $directHandoff.handoffStatus -eq 'error' -or [string]::IsNullOrWhiteSpace([string]$directHandoff.summaryPath) -or -not (Test-Path -LiteralPath $directHandoff.summaryPath)) {
        throw "Companion direct-handoff dry run did not produce a usable handoff summary."
    }

    Write-Host "== Direct handoff clamp dry run through companion =="
    $directHandoffClampStart = Invoke-Json -Method POST -Uri "$baseUrl/api/direct-handoff" -Headers $headers -Body @{
        questionnaireApk = $questionnaireApkForDirect
        temporalTracerApk = $temporalTracerApkForDirect
        unityApk = $unityApkForDirect
        questSerial = [string]$questReadiness.targetSerial
        trialCount = 999
        waitForReadySeconds = 999999
        waitSeconds = 1
        dryRun = $true
        skipInstall = $true
    } -TimeoutSec 60
    Add-Progress "direct-handoff-clamp-started=$($directHandoffClampStart.runId)"
    if ($directHandoffClampStart.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$directHandoffClampStart.runId)) {
        throw "Companion direct-handoff clamp check did not start a handoff job."
    }
    $directHandoffClamp = if ($directHandoffClampStart.jobStatus -eq 'running') {
        Wait-DirectHandoffJob -BaseUrl $baseUrl -Headers $headers -RunId $directHandoffClampStart.runId -TimeoutSec 900
    }
    else {
        $directHandoffClampStart
    }
    Add-Progress "direct-handoff-clamp-complete jobStatus=$($directHandoffClamp.jobStatus) trialCount=$($directHandoffClamp.trialCount) waitForReadySeconds=$($directHandoffClamp.waitForReadySeconds)"
    if ($directHandoffClamp.handoffStatus -eq 'fail' -or $directHandoffClamp.handoffStatus -eq 'error' -or [string]::IsNullOrWhiteSpace([string]$directHandoffClamp.summaryPath) -or -not (Test-Path -LiteralPath $directHandoffClamp.summaryPath)) {
        throw "Companion direct-handoff clamp dry run did not produce a usable handoff summary."
    }
    if ([int]$directHandoffClamp.trialCount -ne 10 -or [int]$directHandoffClamp.waitForReadySeconds -ne 28800) {
        throw "Companion direct-handoff clamp mismatch. Expected trialCount=10 and waitForReadySeconds=28800, got trialCount=$($directHandoffClamp.trialCount), waitForReadySeconds=$($directHandoffClamp.waitForReadySeconds)."
    }

    Write-Host "== Save config through companion =="
    $save = Invoke-Json -Method POST -Uri "$baseUrl/api/save-config" -Headers $headers -Body @{ config = $handoffConfig }
    Add-Progress 'save-config-complete'
    if ($save.status -ne 'ok' -or -not (Test-Path -LiteralPath $save.configPath)) {
        throw "Companion save-config failed."
    }

    Write-Host "== Validate config through companion =="
    $validate = Invoke-Json -Method POST -Uri "$baseUrl/api/validate-config" -Headers $headers -Body @{ config = $handoffConfig }
    Add-Progress 'validate-config-complete'
    if ($validate.status -ne 'ok') {
        throw "Companion validate-config failed."
    }

    Write-Host "== Generate APK through companion =="
    $renderPreviewRequested = -not $SkipRenderPreview
    $generateBody = @{
        config = $handoffConfig
        runTests = $false
        renderPreview = $renderPreviewRequested
        skipBuild = [bool]$SkipApkBuild
    }
    $generate = Invoke-Json -Method POST -Uri "$baseUrl/api/generate-apk" -Headers $headers -Body $generateBody -TimeoutSec 1800
    Add-Progress 'generate-apk-complete'
    if ($generate.status -ne 'ok') {
        throw "Companion generate-apk failed."
    }
    if (-not $SkipApkBuild -and ([string]::IsNullOrWhiteSpace([string]$generate.apk) -or -not (Test-Path -LiteralPath $generate.apk))) {
        throw "Companion generate-apk did not produce an APK path."
    }
    if ($generate.summaryPath -and -not (Test-Path -LiteralPath $generate.summaryPath)) {
        throw "Companion generator summary was not written: $($generate.summaryPath)"
    }
    $generateSummary = Read-JsonIfExists -Path ([string]$generate.summaryPath)
    if ($null -eq $generateSummary) {
        throw "Companion generator summary could not be read: $($generate.summaryPath)"
    }
    $generatedApkEvidence = Get-FileEvidence -Path ([string]$generate.apk)
    if (-not $SkipApkBuild) {
        if (-not $generatedApkEvidence.exists) {
            throw "Companion generate-apk reported a missing APK: $($generate.apk)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$generateSummary.apkSha256) -or [string]$generatedApkEvidence.sha256 -ne [string]$generateSummary.apkSha256) {
            throw "Companion generated APK hash mismatch. Summary=$($generateSummary.apkSha256) actual=$($generatedApkEvidence.sha256)"
        }
    }
    $generateRenderSummaryPath = if ($generateSummary -and $generateSummary.PSObject.Properties.Name -contains 'renderSummary') { [string]$generateSummary.renderSummary } else { "" }
    $generateRenderEvidence = if (-not [string]::IsNullOrWhiteSpace($generateRenderSummaryPath)) { Get-RenderEvidence -SummaryPath $generateRenderSummaryPath } else { $null }
    if ($renderPreviewRequested -and ($null -eq $generateRenderEvidence -or -not $generateRenderEvidence.exists -or -not $generateRenderEvidence.passesArtifactGate)) {
        throw "Companion generate-apk render preview did not produce a usable render artifact gate."
    }

    Write-Host "== Validate builder-to-Quest workflow through companion =="
    $workflowBody = @{
        config = $handoffConfig
        skipBuild = $true
        skipQuestionnaireRender = $false
        skipTemporalRender = $false
        runQuestReadiness = $false
        runQuestDirectHandoff = $false
    }
    $workflowStart = Invoke-Json -Method POST -Uri "$baseUrl/api/validate-workflow" -Headers $headers -Body $workflowBody -TimeoutSec 60
    Add-Progress "validate-workflow-started=$($workflowStart.runId)"
    if ($workflowStart.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$workflowStart.runId)) {
        throw "Companion validate-workflow did not start a workflow job."
    }
    $workflow = if ($workflowStart.jobStatus -eq 'running') {
        Wait-WorkflowJob -BaseUrl $baseUrl -Headers $headers -RunId $workflowStart.runId -TimeoutSec 1800
    }
    else {
        $workflowStart
    }
    Add-Progress "validate-workflow-complete jobStatus=$($workflow.jobStatus) workflowStatus=$($workflow.workflowStatus)"
    if ($workflow.workflowStatus -eq 'fail' -or [string]::IsNullOrWhiteSpace([string]$workflow.summaryPath) -or -not (Test-Path -LiteralPath $workflow.summaryPath)) {
        throw "Companion validate-workflow did not produce a usable workflow summary."
    }

    Write-Host "== Validate workflow direct handoff clamp dry run through companion =="
    $workflowClampBody = @{
        config = $handoffConfig
        skipBuild = $true
        skipQuestionnaireRender = $true
        skipTemporalRender = $true
        runQuestReadiness = $false
        runQuestDirectHandoff = $true
        dryRunQuestDirectHandoff = $true
        skipInstall = $true
        questSerial = [string]$questReadiness.targetSerial
        questTrials = 999
        waitForReadySeconds = 999999
    }
    $workflowClampStart = Invoke-Json -Method POST -Uri "$baseUrl/api/validate-workflow" -Headers $headers -Body $workflowClampBody -TimeoutSec 60
    Add-Progress "validate-workflow-clamp-started=$($workflowClampStart.runId)"
    if ($workflowClampStart.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$workflowClampStart.runId)) {
        throw "Companion validate-workflow clamp check did not start a workflow job."
    }
    if ([int]$workflowClampStart.questTrials -ne 10 -or [int]$workflowClampStart.waitForReadySeconds -ne 28800 -or -not [bool]$workflowClampStart.dryRunQuestDirectHandoff) {
        throw "Companion validate-workflow start clamp mismatch. Expected questTrials=10, waitForReadySeconds=28800, dryRunQuestDirectHandoff=true; got questTrials=$($workflowClampStart.questTrials), waitForReadySeconds=$($workflowClampStart.waitForReadySeconds), dryRunQuestDirectHandoff=$($workflowClampStart.dryRunQuestDirectHandoff)."
    }
    $workflowClamp = if ($workflowClampStart.jobStatus -eq 'running') {
        Wait-WorkflowJob -BaseUrl $baseUrl -Headers $headers -RunId $workflowClampStart.runId -TimeoutSec 1800
    }
    else {
        $workflowClampStart
    }
    Add-Progress "validate-workflow-clamp-complete jobStatus=$($workflowClamp.jobStatus) workflowStatus=$($workflowClamp.workflowStatus) questTrials=$($workflowClamp.questTrials) waitForReadySeconds=$($workflowClamp.waitForReadySeconds)"
    if ($workflowClamp.workflowStatus -eq 'fail' -or [string]::IsNullOrWhiteSpace([string]$workflowClamp.summaryPath) -or -not (Test-Path -LiteralPath $workflowClamp.summaryPath)) {
        throw "Companion validate-workflow clamp dry run did not produce a usable workflow summary."
    }
    if ([int]$workflowClamp.questTrials -ne 10 -or [int]$workflowClamp.waitForReadySeconds -ne 28800 -or -not [bool]$workflowClamp.dryRunQuestDirectHandoff) {
        throw "Companion validate-workflow final clamp mismatch. Expected questTrials=10, waitForReadySeconds=28800, dryRunQuestDirectHandoff=true; got questTrials=$($workflowClamp.questTrials), waitForReadySeconds=$($workflowClamp.waitForReadySeconds), dryRunQuestDirectHandoff=$($workflowClamp.dryRunQuestDirectHandoff)."
    }
    $workflowClampSummary = Get-Content -LiteralPath $workflowClamp.summaryPath -Raw | ConvertFrom-Json
    $workflowClampDirectFacts = $workflowClampSummary.evidence.directQuestHandoff
    if (-not $workflowClampDirectFacts -or -not [bool]$workflowClampDirectFacts.dryRun -or [int]$workflowClampDirectFacts.requestedQuestTrials -ne 10 -or [int]$workflowClampDirectFacts.requestedWaitForReadySeconds -ne 28800) {
        throw "Companion validate-workflow clamp summary missing dry-run direct handoff facts."
    }

    $workflowSummary = Read-JsonIfExists -Path ([string]$workflow.summaryPath)
    $workflowCounts = if ($workflowSummary -and $workflowSummary.PSObject.Properties.Name -contains 'counts') { $workflowSummary.counts } else { $null }
    $authorizationPass = (
        -not [bool]$statusNoToken.authorized -and
        [bool]$statusWithToken.authorized -and
        $unauthorizedDependencyStatus -eq 401 -and
        $unauthorizedQuestReadinessStatus -eq 401 -and
        $unauthorizedInstallApkStatus -eq 401 -and
        $unauthorizedQuestReplayStatus -eq 401 -and
        $unauthorizedDirectHandoffStatus -eq 401
    )
    $saveValidatePass = (
        [string]$save.status -eq 'ok' -and
        (Test-Path -LiteralPath $save.configPath) -and
        [string]$validate.status -eq 'ok' -and
        [int]$validate.exitCode -eq 0
    )
    $generatedApkHashPass = (
        -not [bool]$SkipApkBuild -and
        [bool]$generatedApkEvidence.exists -and
        -not [string]::IsNullOrWhiteSpace([string]$generateSummary.apkSha256) -and
        [string]$generatedApkEvidence.sha256 -eq [string]$generateSummary.apkSha256
    )
    $renderPreviewPass = (
        $renderPreviewRequested -and
        $generateRenderEvidence -and
        [bool]$generateRenderEvidence.exists -and
        [bool]$generateRenderEvidence.passesArtifactGate
    )
    $workflowMatrixInspectable = (
        $workflowSummary -and
        $workflowCounts -and
        [int]$workflowCounts.failed -eq 0 -and
        [int]$workflowCounts.blocked -eq 0
    )
    $directHandoffDryRunGatePass = (
        [string]$directHandoff.handoffStatus -eq 'pass' -and
        $directHandoff.decisionGate -and
        [string]$directHandoff.decisionGate.candidateAStatus -eq 'dry-run-only' -and
        -not [bool]$directHandoff.decisionGate.defaultDirectPendingIntentApproved
    )
    $directHandoffClampGatePass = (
        [int]$directHandoffClamp.trialCount -eq 10 -and
        [int]$directHandoffClamp.waitForReadySeconds -eq 28800 -and
        $directHandoffClamp.decisionGate -and
        [string]$directHandoffClamp.decisionGate.candidateAStatus -eq 'dry-run-only' -and
        -not [bool]$directHandoffClamp.decisionGate.defaultDirectPendingIntentApproved
    )
    $workflowClampGatePass = (
        $workflowClampDirectFacts -and
        [bool]$workflowClampDirectFacts.dryRun -and
        [int]$workflowClampDirectFacts.requestedQuestTrials -eq 10 -and
        [int]$workflowClampDirectFacts.requestedWaitForReadySeconds -eq 28800 -and
        $workflowClampDirectFacts.decisionGate -and
        [string]$workflowClampDirectFacts.decisionGate.candidateAStatus -eq 'dry-run-only' -and
        -not [bool]$workflowClampDirectFacts.decisionGate.defaultDirectPendingIntentApproved
    )
    $offlineWorkflowReady = (
        $authorizationPass -and
        [string]$dependency.status -eq 'ok' -and
        $saveValidatePass -and
        $generatedApkHashPass -and
        $renderPreviewPass -and
        $workflowMatrixInspectable -and
        [string]$installApk.installStatus -eq 'pass' -and
        [string]$questReplay.replayStatus -ne 'fail' -and
        $directHandoffDryRunGatePass -and
        $directHandoffClampGatePass -and
        $workflowClampGatePass
    )
    $skippedEvidence = [ordered]@{
        apkBuild = [bool]$SkipApkBuild
        renderPreview = (-not $renderPreviewRequested)
    }
    $nonSkippedReceiptChecksPass = (
        $authorizationPass -and
        [string]$dependency.status -eq 'ok' -and
        $saveValidatePass -and
        $workflowMatrixInspectable -and
        [string]$installApk.installStatus -eq 'pass' -and
        [string]$questReplay.replayStatus -ne 'fail' -and
        $directHandoffDryRunGatePass -and
        $directHandoffClampGatePass -and
        $workflowClampGatePass
    )
    $receiptStatus = 'fail'
    if ($offlineWorkflowReady) {
        $receiptStatus = 'pass-with-physical-pending'
    } elseif ($nonSkippedReceiptChecksPass -and ([bool]$SkipApkBuild -or -not $renderPreviewRequested)) {
        $receiptStatus = 'partial-skipped-evidence'
    }
    $endToEndReceipt = [ordered]@{
        schemaVersion = 'my-questionnaire-2d.end_to_end_workflow_receipt.v1'
        status = $receiptStatus
        offlineWorkflowReady = $offlineWorkflowReady
        skippedEvidence = $skippedEvidence
        physicalQuestProductPathPending = $true
        proofBoundary = 'Direct PendingIntent cannot become the production default until 10 clean real Quest trials plus one manual headset pass prove the product path.'
        checks = [ordered]@{
            guiSmokeProducedHandoffConfig = (Test-Path -LiteralPath $handoffConfigPath)
            companionTokenAuthorization = $authorizationPass
            dependencyStatusOk = ([string]$dependency.status -eq 'ok')
            questReadinessProbed = (-not [string]::IsNullOrWhiteSpace([string]$questReadiness.summaryPath) -and (Test-Path -LiteralPath $questReadiness.summaryPath))
            installEndpointDryRunPass = ([string]$installApk.installStatus -eq 'pass')
            replayEndpointDryRunContractPass = ([string]$questReplay.replayStatus -ne 'fail')
            directHandoffDryRunContractPass = $directHandoffDryRunGatePass
            directHandoffClampContractPass = $directHandoffClampGatePass
            saveAndValidateConfigPass = $saveValidatePass
            generateApkHashPass = $generatedApkHashPass
            renderPreviewArtifactGatePass = $renderPreviewPass
            workflowMatrixInspectable = $workflowMatrixInspectable
            workflowDirectHandoffClampGatePass = $workflowClampGatePass
        }
        artifacts = [ordered]@{
            generatedConfigPath = $save.configPath
            generatedApk = $generatedApkEvidence
            generateSummaryPath = $generate.summaryPath
            renderSummaryPath = $generateRenderSummaryPath
            renderEvidence = $generateRenderEvidence
            workflowSummaryPath = $workflow.summaryPath
            workflowCounts = $workflowCounts
            directHandoffSummaryPath = $directHandoff.summaryPath
            workflowClampSummaryPath = $workflowClamp.summaryPath
        }
        physicalEvidenceStillNeeded = [ordered]@{
            directPendingIntentQuestTrials = '10 clean product-path trials'
            manualHeadsetPass = 'pending'
            currentTransportReadiness = $questReadiness.readiness
            currentProductPathStatus = $questReadiness.productPathStatus
            currentProductPathReady = [bool]$questReadiness.productPathReady
            blockedReasons = if ($questReadiness.productPath -and $questReadiness.productPath.PSObject.Properties.Name -contains 'blockedReasons') { @($questReadiness.productPath.blockedReasons) } else { @() }
            defaultDirectPendingIntentApproved = $false
        }
    }

    $summaryStatus = 'pass'
    $summary = [ordered]@{
        schemaVersion = 'my-questionnaire-2d.builder-companion-workflow.v1'
        status = $summaryStatus
        runId = $RunId
        artifactDir = $artifactDir
        endToEndReceipt = $endToEndReceipt
        baseUrl = $baseUrl
        authorization = [ordered]@{
            withoutTokenAuthorized = [bool]$statusNoToken.authorized
            withTokenAuthorized = [bool]$statusWithToken.authorized
            unauthorizedDependencyStatus = $unauthorizedDependencyStatus
            unauthorizedQuestReadinessStatus = $unauthorizedQuestReadinessStatus
            unauthorizedInstallApkStatus = $unauthorizedInstallApkStatus
            unauthorizedQuestReplayStatus = $unauthorizedQuestReplayStatus
            unauthorizedDirectHandoffStatus = $unauthorizedDirectHandoffStatus
        }
        dependency = $dependency
        questReadiness = [ordered]@{
            status = $questReadiness.readinessStatus
            readiness = $questReadiness.readiness
            productPathStatus = $questReadiness.productPathStatus
            productPathReady = [bool]$questReadiness.productPathReady
            productPathBlockedReasons = if ($questReadiness.productPath -and $questReadiness.productPath.PSObject.Properties.Name -contains 'blockedReasons') { @($questReadiness.productPath.blockedReasons) } else { @() }
            targetSerial = $questReadiness.targetSerial
            onlineCount = $questReadiness.onlineCount
            summaryPath = $questReadiness.summaryPath
        }
        installApkDryRun = [ordered]@{
            jobStatus = $installApk.jobStatus
            installStatus = $installApk.installStatus
            runId = $installApk.runId
            summaryPath = $installApk.summaryPath
        }
        questReplayDryRun = [ordered]@{
            jobStatus = $questReplay.jobStatus
            replayStatus = $questReplay.replayStatus
            productPathStatus = $questReplay.productPathStatus
            productPathBlockedReasons = if ($questReplay.PSObject.Properties.Name -contains 'productPathBlockedReasons') { @($questReplay.productPathBlockedReasons) } else { @() }
            runId = $questReplay.runId
            summaryPath = $questReplay.summaryPath
        }
        directHandoffDryRun = [ordered]@{
            jobStatus = $directHandoff.jobStatus
            handoffStatus = $directHandoff.handoffStatus
            passCount = $directHandoff.passCount
            warnCount = $directHandoff.warnCount
            blockedCount = $directHandoff.blockedCount
            failCount = $directHandoff.failCount
            runId = $directHandoff.runId
            summaryPath = $directHandoff.summaryPath
            questionnaireApk = $questionnaireApkForDirect
            temporalTracerApk = $temporalTracerApkForDirect
            unityApk = $unityApkForDirect
            decisionGate = $directHandoff.decisionGate
        }
        directHandoffClampDryRun = [ordered]@{
            jobStatus = $directHandoffClamp.jobStatus
            handoffStatus = $directHandoffClamp.handoffStatus
            requestedTrialCount = 999
            requestedWaitForReadySeconds = 999999
            trialCount = $directHandoffClamp.trialCount
            waitForReadySeconds = $directHandoffClamp.waitForReadySeconds
            waitSeconds = $directHandoffClamp.waitSeconds
            runId = $directHandoffClamp.runId
            summaryPath = $directHandoffClamp.summaryPath
            decisionGate = $directHandoffClamp.decisionGate
        }
        builder = [ordered]@{
            outputDir = $builderOut
            handoffConfig = $handoffConfigPath
        }
        companion = [ordered]@{
            savedConfigPath = $save.configPath
            validateExitCode = $validate.exitCode
            generateRunId = $generate.runId
            generateSummaryPath = $generate.summaryPath
            generateStatus = if ($generateSummary) { $generateSummary.status } else { '' }
            apk = $generate.apk
            apkEvidence = $generatedApkEvidence
            skipBuild = [bool]$SkipApkBuild
            renderPreview = $renderPreviewRequested
            renderSummaryPath = $generateRenderSummaryPath
            renderEvidence = $generateRenderEvidence
            workflowStatus = $workflow.workflowStatus
            workflowSummaryPath = $workflow.summaryPath
        }
        workflowDirectHandoffClampDryRun = [ordered]@{
            jobStatus = $workflowClamp.jobStatus
            workflowStatus = $workflowClamp.workflowStatus
            requestedQuestTrials = 999
            requestedWaitForReadySeconds = 999999
            questTrials = $workflowClamp.questTrials
            waitForReadySeconds = $workflowClamp.waitForReadySeconds
            dryRunQuestDirectHandoff = [bool]$workflowClamp.dryRunQuestDirectHandoff
            runId = $workflowClamp.runId
            summaryPath = $workflowClamp.summaryPath
            directQuestHandoff = $workflowClampDirectFacts
        }
        completedAt = (Get-Date).ToString('o')
    }

    $summaryPath = Join-Path $artifactDir 'builder-companion-workflow-summary.json'
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Add-Progress "summary-written=$summaryPath"
    Write-Host "Builder companion workflow summary: $summaryPath"
}
catch {
    Add-Progress ("error=" + $_.Exception.Message)
    throw
}
finally {
    if ($process -and -not $process.HasExited -and $process.Id -ne $PID) {
        Add-Progress "companion-stop=$($process.Id)"
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(5000) | Out-Null
    }
}
