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

    Write-Host "== Dependency status =="
    $dependency = Invoke-Json -Method GET -Uri "$baseUrl/api/dependency-status" -Headers $headers
    Add-Progress 'dependency-status-complete'
    if ($dependency.status -ne 'ok') {
        throw "Required local dependencies are missing. See companion summary."
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
    $generateBody = @{
        config = $handoffConfig
        runTests = $false
        renderPreview = -not $SkipRenderPreview
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

    $renderPreviewRequested = -not $SkipRenderPreview
    $summaryStatus = 'pass'
    $summary = [ordered]@{
        schemaVersion = 'my-questionnaire-2d.builder-companion-workflow.v1'
        status = $summaryStatus
        runId = $RunId
        artifactDir = $artifactDir
        baseUrl = $baseUrl
        authorization = [ordered]@{
            withoutTokenAuthorized = [bool]$statusNoToken.authorized
            withTokenAuthorized = [bool]$statusWithToken.authorized
            unauthorizedDependencyStatus = $unauthorizedDependencyStatus
        }
        dependency = $dependency
        builder = [ordered]@{
            outputDir = $builderOut
            handoffConfig = $handoffConfigPath
        }
        companion = [ordered]@{
            savedConfigPath = $save.configPath
            validateExitCode = $validate.exitCode
            generateRunId = $generate.runId
            generateSummaryPath = $generate.summaryPath
            apk = $generate.apk
            skipBuild = [bool]$SkipApkBuild
            renderPreview = $renderPreviewRequested
            workflowStatus = $workflow.workflowStatus
            workflowSummaryPath = $workflow.summaryPath
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
