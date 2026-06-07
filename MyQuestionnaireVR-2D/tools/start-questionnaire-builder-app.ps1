param(
    [int]$Port = 8765,
    [string]$ProjectPath = "",
    [string]$ReferenceProjectPath = "",
    [ValidateSet('Offline', 'OnlineConnector')]
    [string]$Mode = 'Offline',
    [string]$OnlinePageUrl = "https://georgefejer91.github.io/quest-2d-questionnaire-apps/questionnaire-builder/",
    [string[]]$AllowedOrigins = @(),
    [string]$PairingToken = "",
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Split-Path -Parent $PSScriptRoot
}
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)

if ([string]::IsNullOrWhiteSpace($ReferenceProjectPath)) {
    $siblingReference = Join-Path (Split-Path -Parent $ProjectPath) 'MyQuestionnaireVR'
    if (Test-Path -LiteralPath $siblingReference) {
        $ReferenceProjectPath = [System.IO.Path]::GetFullPath($siblingReference)
    }
    else {
        $ReferenceProjectPath = $ProjectPath
    }
}
else {
    $ReferenceProjectPath = [System.IO.Path]::GetFullPath($ReferenceProjectPath)
}

$originCandidates = @(
    "http://127.0.0.1:$Port",
    "http://localhost:$Port"
)
try {
    $onlineUri = [System.Uri]$OnlinePageUrl
    if ($onlineUri.Scheme -and $onlineUri.Host) {
        $originCandidates += $onlineUri.GetLeftPart([System.UriPartial]::Authority)
    }
}
catch {
    Write-Warning "Could not parse online page URL for CORS origin: $OnlinePageUrl"
}
$originCandidates += $AllowedOrigins
$EffectiveAllowedOrigins = @($originCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

$EditorPath = Join-Path $ProjectPath 'tools\questionnaire-config-editor\index.html'
if (-not (Test-Path -LiteralPath $EditorPath)) {
    throw "Questionnaire builder HTML not found: $EditorPath"
}

if ([string]::IsNullOrWhiteSpace($PairingToken)) {
    $bytes = New-Object byte[] 18
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    $PairingToken = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

$script:WorkflowJobs = @{}
$script:WorkflowJobOrder = New-Object 'System.Collections.Generic.List[string]'
$script:InstallApkJobs = @{}
$script:InstallApkJobOrder = New-Object 'System.Collections.Generic.List[string]'
$script:QuestReplayJobs = @{}
$script:QuestReplayJobOrder = New-Object 'System.Collections.Generic.List[string]'

function New-Utf8NoBomEncoding {
    return [System.Text.UTF8Encoding]::new($false)
}

function Get-SafeName {
    param([string]$Value)

    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'questionnaire'
    }
    return $safe
}

function Get-RequestBody {
    param([System.Net.HttpListenerRequest]$Request)

    if (-not $Request.HasEntityBody) {
        return ''
    }
    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Test-OriginAllowed {
    param([string]$Origin)

    if ([string]::IsNullOrWhiteSpace($Origin)) {
        return $true
    }
    foreach ($allowed in $EffectiveAllowedOrigins) {
        if ($Origin.Equals($allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Set-CorsHeaders {
    param([System.Net.HttpListenerContext]$Context)

    $origin = [string]$Context.Request.Headers['Origin']
    if (-not [string]::IsNullOrWhiteSpace($origin) -and (Test-OriginAllowed -Origin $origin)) {
        $Context.Response.Headers['Access-Control-Allow-Origin'] = $origin
        $Context.Response.Headers['Vary'] = 'Origin'
        $Context.Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        $Context.Response.Headers['Access-Control-Allow-Headers'] = 'Content-Type, X-MQ-Builder-Token'
        $Context.Response.Headers['Access-Control-Max-Age'] = '600'
        $Context.Response.Headers['Access-Control-Allow-Private-Network'] = 'true'
    }
}

function Write-Response {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Body
    )

    Set-CorsHeaders -Context $Context
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.Headers['Cache-Control'] = 'no-store'
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [object]$Value
    )

    Write-Response -Context $Context -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -Body (($Value | ConvertTo-Json -Depth 60) + "`n")
}

function Write-EmptyResponse {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode = 204
    )

    Set-CorsHeaders -Context $Context
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentLength64 = 0
    $Context.Response.OutputStream.Close()
}

function Get-RequestToken {
    param([System.Net.HttpListenerRequest]$Request)

    $header = [string]$Request.Headers['X-MQ-Builder-Token']
    if (-not [string]::IsNullOrWhiteSpace($header)) {
        return $header.Trim()
    }
    $query = [string]$Request.QueryString['token']
    if (-not [string]::IsNullOrWhiteSpace($query)) {
        return $query.Trim()
    }
    return ''
}

function Test-Authorized {
    param([System.Net.HttpListenerRequest]$Request)

    $token = Get-RequestToken -Request $Request
    return -not [string]::IsNullOrWhiteSpace($token) -and $token.Equals($PairingToken, [System.StringComparison]::Ordinal)
}

function Assert-OriginAndToken {
    param([System.Net.HttpListenerRequest]$Request)

    $origin = [string]$Request.Headers['Origin']
    if (-not (Test-OriginAllowed -Origin $origin)) {
        throw "Origin is not allowed: $origin"
    }
    if (-not (Test-Authorized -Request $Request)) {
        throw "Missing or invalid pairing token."
    }
}

function Save-ConfigPayload {
    param([object]$Payload)

    $config = $Payload
    if ($null -ne $Payload -and $Payload.PSObject.Properties.Name -contains 'config') {
        $config = $Payload.config
    }
    if ($null -eq $config) {
        throw 'Request did not contain a config object.'
    }

    $id = if ($config.PSObject.Properties.Name -contains 'questionnaireId') { [string]$config.questionnaireId } else { 'questionnaire' }
    $fileName = Get-SafeName $id
    $configDir = Join-Path $ProjectPath 'QuestionnaireConfigs\generated'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $configPath = Join-Path $configDir ($fileName + '.config.json')
    $json = $config | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, (New-Utf8NoBomEncoding))
    return $configPath
}

function Invoke-ProjectPowerShell {
    param([string[]]$Arguments)

    Push-Location $ProjectPath
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell @Arguments 2>&1 | ForEach-Object { $_.ToString() } | Out-String
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        return [ordered]@{
            exitCode = $exitCode
            output = $output.TrimEnd()
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }
}

function Read-JsonFileIfExists {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Read-TextFileIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-TailText {
    param(
        [string]$Path,
        [int]$MaxChars = 6000
    )

    $text = Read-TextFileIfExists -Path $Path
    if ($text.Length -le $MaxChars) {
        return $text
    }
    return "[trimmed to last $MaxChars chars]`n" + $text.Substring($text.Length - $MaxChars)
}

function New-WorkflowValidationArguments {
    param(
        [object]$Payload,
        [string]$ConfigPath,
        [string]$RunId
    )

    $script = Join-Path $ProjectPath 'tools\validate-builder-to-quest-workflow.ps1'
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ConfigPath',
        $ConfigPath,
        '-ProjectPath',
        $ProjectPath,
        '-ReferenceProjectPath',
        $ReferenceProjectPath,
        '-RunId',
        $RunId,
        '-InvokedByCompanion'
    )

    if ($Payload.PSObject.Properties.Name -contains 'skipBuild' -and [bool]$Payload.skipBuild) {
        $arguments += '-SkipApkBuild'
    }
    if ($Payload.PSObject.Properties.Name -contains 'skipQuestionnaireRender' -and [bool]$Payload.skipQuestionnaireRender) {
        $arguments += '-SkipQuestionnaireRender'
    }
    if ($Payload.PSObject.Properties.Name -contains 'skipTemporalRender' -and [bool]$Payload.skipTemporalRender) {
        $arguments += '-SkipTemporalRender'
    }
    if ($Payload.PSObject.Properties.Name -contains 'runQuestReadiness' -and [bool]$Payload.runQuestReadiness) {
        $arguments += '-RunQuestReadiness'
    }
    if ($Payload.PSObject.Properties.Name -contains 'runQuestDirectHandoff' -and [bool]$Payload.runQuestDirectHandoff) {
        $arguments += '-RunQuestDirectHandoff'
    }
    if ($Payload.PSObject.Properties.Name -contains 'skipInstall' -and [bool]$Payload.skipInstall) {
        $arguments += '-SkipInstall'
    }
    if ($Payload.PSObject.Properties.Name -contains 'questSerial' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questSerial)) {
        $arguments += @('-Serial', [string]$Payload.questSerial)
    }
    if ($Payload.PSObject.Properties.Name -contains 'questTrials' -and [int]$Payload.questTrials -gt 0) {
        $arguments += @('-QuestTrials', [string][int]$Payload.questTrials)
    }
    if ($Payload.PSObject.Properties.Name -contains 'waitForReadySeconds' -and [int]$Payload.waitForReadySeconds -ge 0) {
        $arguments += @('-WaitForReadySeconds', [string][int]$Payload.waitForReadySeconds)
    }

    return $arguments
}

function Get-WorkflowJobStatus {
    param([string]$RunId)

    if ([string]::IsNullOrWhiteSpace($RunId) -or -not $script:WorkflowJobs.ContainsKey($RunId)) {
        return $null
    }

    $job = $script:WorkflowJobs[$RunId]
    $process = $job['process']
    $hasExited = $false
    $exitCode = $null
    $processError = ''

    if ($null -ne $process) {
        try {
            $process.Refresh()
            $hasExited = [bool]$process.HasExited
            if ($hasExited) {
                $exitCode = [int]$process.ExitCode
                if ([string]::IsNullOrWhiteSpace([string]$job['completedAt'])) {
                    $job['completedAt'] = (Get-Date).ToString('o')
                }
            }
        }
        catch {
            $hasExited = $true
            $processError = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace([string]$job['completedAt'])) {
                $job['completedAt'] = (Get-Date).ToString('o')
            }
        }
    }

    $summary = Read-JsonFileIfExists -Path ([string]$job['summaryPath'])
    $jobStatus = 'running'
    $workflowStatus = 'running'
    if ($hasExited) {
        if ($null -ne $exitCode -and $exitCode -eq 0) {
            $jobStatus = 'completed'
        }
        else {
            $jobStatus = 'failed'
        }
        if ($summary) {
            $workflowStatus = [string]$summary.status
        }
        elseif ($jobStatus -eq 'completed') {
            $workflowStatus = 'missing-summary'
        }
        else {
            $workflowStatus = 'error'
        }
    }
    elseif ($summary -and $summary.PSObject.Properties.Name -contains 'status') {
        $workflowStatus = [string]$summary.status
    }

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        workflowStatus = $workflowStatus
        exitCode = $exitCode
        processError = $processError
        configPath = $job['configPath']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        summary = $summary
        startedAt = $job['startedAt']
        completedAt = $job['completedAt']
    }
}

function Start-WorkflowValidationJob {
    param([object]$Payload)

    $configPath = Save-ConfigPayload -Payload $Payload
    $runId = 'builder-workflow-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $jobDir = Join-Path $ProjectPath ("artifacts\builder-app-jobs\$runId")
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

    $stdoutPath = Join-Path $jobDir 'workflow-stdout.txt'
    $stderrPath = Join-Path $jobDir 'workflow-stderr.txt'
    $summaryPath = Join-Path $ProjectPath ("artifacts\builder-to-quest-workflow\$runId\builder-to-quest-workflow-summary.json")
    $arguments = New-WorkflowValidationArguments -Payload $Payload -ConfigPath $configPath -RunId $runId

    $process = Start-Process `
        -FilePath 'powershell' `
        -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $script:WorkflowJobs[$runId] = [ordered]@{
        process = $process
        runId = $runId
        configPath = $configPath
        artifactDir = $jobDir
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        summaryPath = $summaryPath
        startedAt = (Get-Date).ToString('o')
        completedAt = ''
    }
    $script:WorkflowJobOrder.Add($runId) | Out-Null

    while ($script:WorkflowJobOrder.Count -gt 20) {
        $oldest = $script:WorkflowJobOrder[0]
        $script:WorkflowJobOrder.RemoveAt(0)
        if ($script:WorkflowJobs.ContainsKey($oldest)) {
            $oldJob = $script:WorkflowJobs[$oldest]
            $oldProcess = $oldJob['process']
            if ($oldProcess -and $oldProcess.HasExited) {
                $script:WorkflowJobs.Remove($oldest)
            }
        }
    }

    return Get-WorkflowJobStatus -RunId $runId
}

function Invoke-QuestReadinessCheck {
    param([object]$Payload)

    $runId = 'builder-quest-readiness-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $outputRoot = Join-Path $ProjectPath ("artifacts\builder-app-quest-readiness\$runId")
    $script = Join-Path $ProjectPath 'tools\quest-adb-readiness.ps1'
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ProjectPath',
        $ProjectPath,
        '-OutputRoot',
        $outputRoot,
        '-RunId',
        $runId
    )

    if ($Payload.PSObject.Properties.Name -contains 'questSerial' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questSerial)) {
        $arguments += @('-ExpectedSerial', [string]$Payload.questSerial)
    }
    if ($Payload.PSObject.Properties.Name -contains 'waitSeconds' -and [int]$Payload.waitSeconds -gt 0) {
        $arguments += @('-WaitSeconds', [string][int]$Payload.waitSeconds)
    }

    $result = Invoke-ProjectPowerShell -Arguments $arguments
    $summaryPath = Join-Path $outputRoot 'quest-adb-readiness-summary.json'
    $summary = Read-JsonFileIfExists -Path $summaryPath
    return [ordered]@{
        status = if ($result.exitCode -eq 0 -and $summary) { 'ok' } else { 'error' }
        readinessStatus = if ($summary) { $summary.status } else { 'missing-summary' }
        readiness = if ($summary) { $summary.readiness } else { '' }
        runId = $runId
        exitCode = $result.exitCode
        targetSerial = if ($summary) { $summary.targetSerial } else { '' }
        onlineCount = if ($summary) { $summary.onlineCount } else { 0 }
        unauthorizedCount = if ($summary) { $summary.unauthorizedCount } else { 0 }
        offlineCount = if ($summary) { $summary.offlineCount } else { 0 }
        offlineEmulatorCount = if ($summary) { $summary.offlineEmulatorCount } else { 0 }
        model = if ($summary) { $summary.deviceProps.model } else { '' }
        androidRelease = if ($summary) { $summary.deviceProps.androidRelease } else { '' }
        wmSize = if ($summary) { $summary.deviceProps.wmSize } else { '' }
        wmDensity = if ($summary) { $summary.deviceProps.wmDensity } else { '' }
        recommendations = if ($summary) { @($summary.recommendations) } else { @() }
        summaryPath = $summaryPath
        summary = $summary
        output = $result.output
    }
}

function Get-InstallApkJobStatus {
    param([string]$RunId)

    if ([string]::IsNullOrWhiteSpace($RunId) -or -not $script:InstallApkJobs.ContainsKey($RunId)) {
        return $null
    }

    $job = $script:InstallApkJobs[$RunId]
    $process = $job['process']
    $hasExited = $false
    $exitCode = $null
    $processError = ''
    if ($null -ne $process) {
        try {
            $process.Refresh()
            $hasExited = [bool]$process.HasExited
            if ($hasExited) {
                $exitCode = [int]$process.ExitCode
                if ([string]::IsNullOrWhiteSpace([string]$job['completedAt'])) {
                    $job['completedAt'] = (Get-Date).ToString('o')
                }
            }
        }
        catch {
            $hasExited = $true
            $processError = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace([string]$job['completedAt'])) {
                $job['completedAt'] = (Get-Date).ToString('o')
            }
        }
    }

    $summary = Read-JsonFileIfExists -Path ([string]$job['summaryPath'])
    $jobStatus = 'running'
    $installStatus = 'running'
    if ($hasExited) {
        $jobStatus = if ($null -ne $exitCode -and $exitCode -eq 0) { 'completed' } else { 'failed' }
        if ($summary) {
            $installStatus = [string]$summary.status
        }
        elseif ($jobStatus -eq 'completed') {
            $installStatus = 'missing-summary'
        }
        else {
            $installStatus = 'error'
        }
    }
    elseif ($summary -and $summary.PSObject.Properties.Name -contains 'status') {
        $installStatus = [string]$summary.status
    }

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        installStatus = $installStatus
        exitCode = $exitCode
        processError = $processError
        apk = $job['apk']
        questSerial = $job['questSerial']
        dryRun = [bool]$job['dryRun']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        summary = $summary
        startedAt = $job['startedAt']
        completedAt = $job['completedAt']
    }
}

function Start-InstallApkJob {
    param([object]$Payload)

    $runId = 'builder-install-apk-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $jobDir = Join-Path $ProjectPath ("artifacts\builder-app-install-apk\$runId")
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

    $apk = if ($Payload.PSObject.Properties.Name -contains 'apk') { [string]$Payload.apk } else { '' }
    $serial = if ($Payload.PSObject.Properties.Name -contains 'questSerial') { [string]$Payload.questSerial } else { '' }
    $dryRun = ($Payload.PSObject.Properties.Name -contains 'dryRun' -and [bool]$Payload.dryRun)
    $waitSeconds = if ($Payload.PSObject.Properties.Name -contains 'waitSeconds') { [int]$Payload.waitSeconds } else { 0 }

    $stdoutPath = Join-Path $jobDir 'install-stdout.txt'
    $stderrPath = Join-Path $jobDir 'install-stderr.txt'
    $summaryPath = Join-Path $jobDir 'install-questionnaire-apk-summary.json'
    $script = Join-Path $ProjectPath 'tools\install-questionnaire-apk-on-quest.ps1'
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ProjectPath',
        $ProjectPath,
        '-OutputRoot',
        $jobDir,
        '-RunId',
        $runId,
        '-WaitSeconds',
        [string][Math]::Max(0, $waitSeconds)
    )
    if (-not [string]::IsNullOrWhiteSpace($apk)) {
        $arguments += @('-Apk', $apk)
    }
    if (-not [string]::IsNullOrWhiteSpace($serial)) {
        $arguments += @('-Serial', $serial)
    }
    if ($dryRun) {
        $arguments += '-DryRun'
    }

    $process = Start-Process `
        -FilePath 'powershell' `
        -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $script:InstallApkJobs[$runId] = [ordered]@{
        process = $process
        runId = $runId
        apk = $apk
        questSerial = $serial
        dryRun = [bool]$dryRun
        artifactDir = $jobDir
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        summaryPath = $summaryPath
        startedAt = (Get-Date).ToString('o')
        completedAt = ''
    }
    $script:InstallApkJobOrder.Add($runId) | Out-Null

    while ($script:InstallApkJobOrder.Count -gt 20) {
        $oldest = $script:InstallApkJobOrder[0]
        $script:InstallApkJobOrder.RemoveAt(0)
        if ($script:InstallApkJobs.ContainsKey($oldest)) {
            $oldJob = $script:InstallApkJobs[$oldest]
            $oldProcess = $oldJob['process']
            if ($oldProcess -and $oldProcess.HasExited) {
                $script:InstallApkJobs.Remove($oldest)
            }
        }
    }

    return Get-InstallApkJobStatus -RunId $runId
}

function Get-QuestReplayJobStatus {
    param([string]$RunId)

    if ([string]::IsNullOrWhiteSpace($RunId) -or -not $script:QuestReplayJobs.ContainsKey($RunId)) {
        return $null
    }

    $job = $script:QuestReplayJobs[$RunId]
    $process = $job['process']
    $hasExited = $false
    $exitCode = $null
    $processError = ''
    if ($null -ne $process) {
        try {
            $process.Refresh()
            $hasExited = [bool]$process.HasExited
            if ($hasExited) {
                $exitCode = [int]$process.ExitCode
                if ([string]::IsNullOrWhiteSpace([string]$job['completedAt'])) {
                    $job['completedAt'] = (Get-Date).ToString('o')
                }
            }
        }
        catch {
            $hasExited = $true
            $processError = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace([string]$job['completedAt'])) {
                $job['completedAt'] = (Get-Date).ToString('o')
            }
        }
    }

    $summary = Read-JsonFileIfExists -Path ([string]$job['summaryPath'])
    $jobStatus = 'running'
    $replayStatus = 'running'
    if ($hasExited) {
        $jobStatus = if ($null -ne $exitCode -and $exitCode -eq 0) { 'completed' } else { 'failed' }
        if ($summary) {
            $replayStatus = [string]$summary.status
        }
        elseif ($jobStatus -eq 'completed') {
            $replayStatus = 'missing-summary'
        }
        else {
            $replayStatus = 'error'
        }
    }
    elseif ($summary -and $summary.PSObject.Properties.Name -contains 'status') {
        $replayStatus = [string]$summary.status
    }

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        replayStatus = $replayStatus
        exitCode = $exitCode
        processError = $processError
        apk = $job['apk']
        questSerial = $job['questSerial']
        dryRun = [bool]$job['dryRun']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        summary = $summary
        startedAt = $job['startedAt']
        completedAt = $job['completedAt']
    }
}

function Start-QuestReplayJob {
    param([object]$Payload)

    $runId = 'builder-quest-replay-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $jobDir = Join-Path $ProjectPath ("artifacts\builder-app-quest-replay\$runId")
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

    $apk = if ($Payload.PSObject.Properties.Name -contains 'apk') { [string]$Payload.apk } else { '' }
    $serial = if ($Payload.PSObject.Properties.Name -contains 'questSerial') { [string]$Payload.questSerial } else { '' }
    $dryRun = ($Payload.PSObject.Properties.Name -contains 'dryRun' -and [bool]$Payload.dryRun)
    $waitSeconds = if ($Payload.PSObject.Properties.Name -contains 'waitSeconds') { [int]$Payload.waitSeconds } else { 20 }

    $stdoutPath = Join-Path $jobDir 'replay-stdout.txt'
    $stderrPath = Join-Path $jobDir 'replay-stderr.txt'
    $summaryPath = Join-Path $jobDir 'quest-replay-export-summary.json'
    $script = Join-Path $ProjectPath 'tools\run-questionnaire-replay-on-quest.ps1'
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ProjectPath',
        $ProjectPath,
        '-OutputRoot',
        $jobDir,
        '-RunId',
        $runId,
        '-WaitSeconds',
        [string][Math]::Max(1, $waitSeconds)
    )
    if (-not [string]::IsNullOrWhiteSpace($apk)) {
        $arguments += @('-Apk', $apk)
    }
    if (-not [string]::IsNullOrWhiteSpace($serial)) {
        $arguments += @('-Serial', $serial)
    }
    if ($dryRun) {
        $arguments += '-DryRun'
    }
    if ($Payload.PSObject.Properties.Name -contains 'leaveForeground' -and [bool]$Payload.leaveForeground) {
        $arguments += '-LeaveForeground'
    }
    if ($Payload.PSObject.Properties.Name -contains 'stopLegacyUnityApp' -and [bool]$Payload.stopLegacyUnityApp) {
        $arguments += '-StopLegacyUnityApp'
    }

    $process = Start-Process `
        -FilePath 'powershell' `
        -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $script:QuestReplayJobs[$runId] = [ordered]@{
        process = $process
        runId = $runId
        apk = $apk
        questSerial = $serial
        dryRun = [bool]$dryRun
        artifactDir = $jobDir
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        summaryPath = $summaryPath
        startedAt = (Get-Date).ToString('o')
        completedAt = ''
    }
    $script:QuestReplayJobOrder.Add($runId) | Out-Null

    while ($script:QuestReplayJobOrder.Count -gt 20) {
        $oldest = $script:QuestReplayJobOrder[0]
        $script:QuestReplayJobOrder.RemoveAt(0)
        if ($script:QuestReplayJobs.ContainsKey($oldest)) {
            $oldJob = $script:QuestReplayJobs[$oldest]
            $oldProcess = $oldJob['process']
            if ($oldProcess -and $oldProcess.HasExited) {
                $script:QuestReplayJobs.Remove($oldest)
            }
        }
    }

    return Get-QuestReplayJobStatus -RunId $runId
}

function Receive-JsonPayload {
    param([System.Net.HttpListenerRequest]$Request)

    $body = Get-RequestBody -Request $Request
    if ([string]::IsNullOrWhiteSpace($body)) {
        return [pscustomobject]@{}
    }
    return $body | ConvertFrom-Json
}

function Resolve-NodeCandidate {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $command = Get-Command node -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates.Add($command.Source) | Out-Null
    }
    $candidates.Add((Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')) | Out-Null
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return ''
}

function Test-UnityAndroidRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return (Test-Path -LiteralPath (Join-Path $Path 'OpenJDK\bin\java.exe')) -and
        (Test-Path -LiteralPath (Join-Path $Path 'SDK'))
}

function Resolve-UnityAndroidRoot {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($env:UNITY_ANDROID_ROOT)) {
        $candidates.Add($env:UNITY_ANDROID_ROOT) | Out-Null
    }

    $editorRoots = @(
        (Join-Path $env:USERPROFILE 'Unity\Hub\Editor'),
        (Join-Path $env:ProgramFiles 'Unity\Hub\Editor'),
        (Join-Path ${env:ProgramFiles(x86)} 'Unity\Hub\Editor')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($editorRoot in $editorRoots) {
        if (Test-Path -LiteralPath $editorRoot) {
            Get-ChildItem -LiteralPath $editorRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object {
                    $candidates.Add((Join-Path $_.FullName 'Editor\Data\PlaybackEngines\AndroidPlayer')) | Out-Null
                }
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-UnityAndroidRoot -Path $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return ''
}

function Get-DependencyStatus {
    $unityAndroidRoot = Resolve-UnityAndroidRoot
    $java = if ($unityAndroidRoot) { Join-Path $unityAndroidRoot 'OpenJDK\bin\java.exe' } else { '' }
    $sdk = if ($unityAndroidRoot) { Join-Path $unityAndroidRoot 'SDK' } else { '' }
    $adbCandidates = @("C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe")
    if ($sdk) {
        $adbCandidates += (Join-Path $sdk 'platform-tools\adb.exe')
    }
    $adb = ($adbCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    $gradle = Join-Path $ProjectPath 'gradlew.bat'
    $node = Resolve-NodeCandidate

    $items = @(
        [ordered]@{ id = 'powershell'; label = 'Windows PowerShell'; required = $true; path = (Get-Command powershell).Source; status = 'present' },
        [ordered]@{ id = 'gradleWrapper'; label = 'Project Gradle wrapper'; required = $true; path = $gradle; status = if (Test-Path -LiteralPath $gradle) { 'present' } else { 'missing' } },
        [ordered]@{ id = 'unityOpenJdk'; label = 'Unity Android OpenJDK'; required = $true; path = $java; status = if ($java -and (Test-Path -LiteralPath $java)) { 'present' } else { 'missing' } },
        [ordered]@{ id = 'unityAndroidSdk'; label = 'Unity Android SDK'; required = $true; path = $sdk; status = if ($sdk -and (Test-Path -LiteralPath $sdk)) { 'present' } else { 'missing' } },
        [ordered]@{ id = 'adb'; label = 'ADB'; required = $false; path = if ($adb) { $adb } else { '' }; status = if ($adb) { 'present' } else { 'missing' } },
        [ordered]@{ id = 'node'; label = 'Node.js for builder smoke test'; required = $false; path = $node; status = if ($node) { 'present' } else { 'missing' } }
    )
    $missingRequired = @($items | Where-Object { $_.required -and $_.status -ne 'present' })
    return [ordered]@{
        status = if ($missingRequired.Count -eq 0) { 'ok' } else { 'missing-required' }
        items = $items
        missingRequired = @($missingRequired | ForEach-Object { $_.id })
        notes = @(
            'The companion can prepare project/Gradle dependencies, but it cannot silently install Unity Hub, Unity Android Build Support, or Meta Quest Developer Hub.',
            'Install missing required components manually, then rerun dependency preparation.'
        )
    }
}

function Handle-DependencyInstall {
    $builderScript = Join-Path $ProjectPath 'tools\validate-questionnaire-builder.ps1'
    $buildScript = Join-Path $ProjectPath 'tools\build-apk.ps1'
    $builder = Invoke-ProjectPowerShell -Arguments @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $builderScript,
        '-ProjectPath',
        $ProjectPath
    )
    $build = Invoke-ProjectPowerShell -Arguments @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $buildScript,
        '-ProjectPath',
        $ProjectPath,
        '-SkipTests'
    )
    return [ordered]@{
        status = if ($builder.exitCode -eq 0 -and $build.exitCode -eq 0) { 'ok' } else { 'error' }
        dependencyStatus = Get-DependencyStatus
        steps = @(
            [ordered]@{ name = 'validate-questionnaire-builder'; exitCode = $builder.exitCode; output = $builder.output },
            [ordered]@{ name = 'build-apk-skip-tests'; exitCode = $build.exitCode; output = $build.output }
        )
    }
}

function New-StatusPayload {
    param([bool]$Authorized)

    $payload = [ordered]@{
        status = 'ok'
        schemaVersion = 'my-questionnaire-2d.builder-app.v1'
        mode = $Mode
        url = "http://127.0.0.1:$Port/"
        requiresToken = $true
        authorized = $Authorized
        allowedOrigins = $EffectiveAllowedOrigins
        onlinePageUrl = $OnlinePageUrl
        capabilities = @(
            'save-config',
            'validate-config',
            'generate-apk',
            'validate-workflow',
            'workflow-job-status',
            'quest-readiness',
            'install-apk',
            'install-apk-job-status',
            'quest-replay',
            'quest-replay-job-status',
            'dependency-status',
            'install-dependencies'
        )
    }
    if ($Authorized) {
        $payload.projectPath = $ProjectPath
        $payload.referenceProjectPath = $ReferenceProjectPath
        $payload.editorPath = $EditorPath
        $payload.generatedConfigFolder = Join-Path $ProjectPath 'QuestionnaireConfigs\generated'
        $payload.tools = [ordered]@{
            validateConfig = Join-Path $ProjectPath 'tools\validate-questionnaire-config.ps1'
            generateApk = Join-Path $ProjectPath 'tools\generate-questionnaire-apk.ps1'
            validateWorkflow = Join-Path $ProjectPath 'tools\validate-builder-to-quest-workflow.ps1'
        }
    }
    return $payload
}

function Handle-Request {
    param([System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $path = $request.Url.AbsolutePath.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = '/'
    }

    if (-not (Test-OriginAllowed -Origin ([string]$request.Headers['Origin']))) {
        Write-JsonResponse -Context $Context -StatusCode 403 -Value ([ordered]@{
            status = 'error'
            message = "Origin is not allowed: $($request.Headers['Origin'])"
        })
        return
    }

    if ($request.HttpMethod -eq 'OPTIONS') {
        Write-EmptyResponse -Context $Context
        return
    }

    if ($request.HttpMethod -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
        $html = [System.IO.File]::ReadAllText($EditorPath, [System.Text.Encoding]::UTF8)
        $injection = "<script>window.MQ_LOCAL_BACKEND_URL = 'http://127.0.0.1:$Port'; window.MQ_LOCAL_BACKEND_TOKEN = '$PairingToken'; window.MQ_LOCAL_BACKEND_MODE = '$Mode';</script>"
        $html = $html -replace '</head>', ($injection + "`n</head>")
        Write-Response -Context $Context -StatusCode 200 -ContentType 'text/html; charset=utf-8' -Body $html
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/status') {
        Write-JsonResponse -Context $Context -StatusCode 200 -Value (New-StatusPayload -Authorized (Test-Authorized -Request $request))
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/dependency-status') {
        Assert-OriginAndToken -Request $request
        Write-JsonResponse -Context $Context -StatusCode 200 -Value (Get-DependencyStatus)
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/workflow-job') {
        Assert-OriginAndToken -Request $request
        $runId = [string]$request.QueryString['runId']
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = [string]$request.QueryString['jobId']
        }
        $status = Get-WorkflowJobStatus -RunId $runId
        if ($null -eq $status) {
            Write-JsonResponse -Context $Context -StatusCode 404 -Value ([ordered]@{
                status = 'error'
                message = "Unknown workflow job: $runId"
            })
            return
        }
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $status
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/install-apk-job') {
        Assert-OriginAndToken -Request $request
        $runId = [string]$request.QueryString['runId']
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = [string]$request.QueryString['jobId']
        }
        $status = Get-InstallApkJobStatus -RunId $runId
        if ($null -eq $status) {
            Write-JsonResponse -Context $Context -StatusCode 404 -Value ([ordered]@{
                status = 'error'
                message = "Unknown install APK job: $runId"
            })
            return
        }
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $status
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/quest-replay-job') {
        Assert-OriginAndToken -Request $request
        $runId = [string]$request.QueryString['runId']
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = [string]$request.QueryString['jobId']
        }
        $status = Get-QuestReplayJobStatus -RunId $runId
        if ($null -eq $status) {
            Write-JsonResponse -Context $Context -StatusCode 404 -Value ([ordered]@{
                status = 'error'
                message = "Unknown Quest replay job: $runId"
            })
            return
        }
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $status
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/install-dependencies') {
        Assert-OriginAndToken -Request $request
        $result = Handle-DependencyInstall
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.status -eq 'ok') { 200 } else { 500 })) -Value $result
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/quest-readiness') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Invoke-QuestReadinessCheck -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.status -eq 'ok') { 200 } else { 500 })) -Value $result
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/install-apk') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $job = Start-InstallApkJob -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 202 -Value $job
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/quest-replay') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $job = Start-QuestReplayJob -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 202 -Value $job
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/save-config') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $configPath = Save-ConfigPayload -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 200 -Value ([ordered]@{
            status = 'ok'
            configPath = $configPath
        })
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/validate-config') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $configPath = Save-ConfigPayload -Payload $payload
        $script = Join-Path $ProjectPath 'tools\validate-questionnaire-config.ps1'
        $result = Invoke-ProjectPowerShell -Arguments @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $script,
            '-ConfigPath',
            $configPath,
            '-ReferenceProjectPath',
            $ReferenceProjectPath
        )
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.exitCode -eq 0) { 200 } else { 500 })) -Value ([ordered]@{
            status = if ($result.exitCode -eq 0) { 'ok' } else { 'error' }
            configPath = $configPath
            exitCode = $result.exitCode
            output = $result.output
        })
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/generate-apk') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $configPath = Save-ConfigPayload -Payload $payload
        $runId = 'builder-app-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
        $script = Join-Path $ProjectPath 'tools\generate-questionnaire-apk.ps1'
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $script,
            '-ConfigPath',
            $configPath,
            '-ReferenceProjectPath',
            $ReferenceProjectPath,
            '-RunId',
            $runId
        )
        $runTests = $true
        if ($payload.PSObject.Properties.Name -contains 'runTests') {
            $runTests = [bool]$payload.runTests
        }
        if (-not $runTests) {
            $arguments += '-SkipTests'
        }
        if ($payload.PSObject.Properties.Name -contains 'skipBuild' -and [bool]$payload.skipBuild) {
            $arguments += '-SkipBuild'
        }
        if ($payload.PSObject.Properties.Name -contains 'renderPreview' -and [bool]$payload.renderPreview) {
            $arguments += '-RenderPreview'
        }

        $result = Invoke-ProjectPowerShell -Arguments $arguments
        $summaryPath = Join-Path $ProjectPath ("artifacts\apk-generator\$runId\generator-summary.json")
        $summary = Read-JsonFileIfExists -Path $summaryPath
        $apk = if ($null -ne $summary) { $summary.apk } else { $null }
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.exitCode -eq 0) { 200 } else { 500 })) -Value ([ordered]@{
            status = if ($result.exitCode -eq 0) { 'ok' } else { 'error' }
            configPath = $configPath
            runId = $runId
            exitCode = $result.exitCode
            apk = $apk
            summaryPath = $summaryPath
            summary = $summary
            output = $result.output
        })
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/validate-workflow') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        if ($payload.PSObject.Properties.Name -contains 'synchronous' -and [bool]$payload.synchronous) {
            $configPath = Save-ConfigPayload -Payload $payload
            $runId = 'builder-workflow-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
            $arguments = New-WorkflowValidationArguments -Payload $payload -ConfigPath $configPath -RunId $runId
            $result = Invoke-ProjectPowerShell -Arguments $arguments
            $summaryPath = Join-Path $ProjectPath ("artifacts\builder-to-quest-workflow\$runId\builder-to-quest-workflow-summary.json")
            $summary = Read-JsonFileIfExists -Path $summaryPath
            Write-JsonResponse -Context $Context -StatusCode ($(if ($result.exitCode -eq 0) { 200 } else { 500 })) -Value ([ordered]@{
                status = if ($result.exitCode -eq 0) { 'ok' } else { 'error' }
                jobStatus = if ($result.exitCode -eq 0) { 'completed' } else { 'failed' }
                workflowStatus = if ($summary) { $summary.status } else { 'missing-summary' }
                configPath = $configPath
                runId = $runId
                jobId = $runId
                exitCode = $result.exitCode
                summaryPath = $summaryPath
                summary = $summary
                stdout = $result.output
                output = $result.output
            })
            return
        }

        $job = Start-WorkflowValidationJob -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 202 -Value $job
        return
    }

    Write-JsonResponse -Context $Context -StatusCode 404 -Value ([ordered]@{
        status = 'error'
        message = "Unknown endpoint: $($request.HttpMethod) $path"
    })
}

$listener = [System.Net.HttpListener]::new()
$url = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($url)

try {
    $listener.Start()
}
catch {
    throw "Could not start local builder app server on $url. Try a different -Port value. $($_.Exception.Message)"
}

Write-Host "Questionnaire builder companion running at $url"
Write-Host "Mode: $Mode"
Write-Host "Project: $ProjectPath"
Write-Host "Reference project: $ReferenceProjectPath"
Write-Host "Pairing token: $PairingToken"
Write-Host "Allowed origins: $($EffectiveAllowedOrigins -join ', ')"
Write-Host "Press Ctrl+C in this window to stop the backend."

if (-not $NoOpen) {
    if ($Mode -eq 'OnlineConnector') {
        Start-Process $OnlinePageUrl
    }
    else {
        Start-Process $url
    }
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            Handle-Request -Context $context
        }
        catch {
            $message = $_.Exception.Message
            $statusCode = 500
            if ($message -like 'Missing or invalid pairing token*') {
                $statusCode = 401
            }
            elseif ($message -like 'Origin is not allowed*') {
                $statusCode = 403
            }
            Write-JsonResponse -Context $context -StatusCode $statusCode -Value ([ordered]@{
                status = 'error'
                message = $message
            })
        }
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
