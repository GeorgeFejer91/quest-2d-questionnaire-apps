param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = "",
    [string]$RunId = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "unity-chainlink-hook-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath "artifacts\unity-chainlink-hook-validation\$RunId"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$unityDir = Join-Path $ProjectPath 'tools\unity'
if (-not (Test-Path -LiteralPath $unityDir)) {
    $packagedUnityDir = Join-Path $ProjectPath 'unity'
    if (Test-Path -LiteralPath $packagedUnityDir) {
        $unityDir = $packagedUnityDir
    }
}
$bridgePath = Join-Path $unityDir 'QuestQuestionnaireChainBridge.cs'
$hookPath = Join-Path $unityDir 'ChainLinkControllerHook.cs'
$readmePath = Join-Path $unityDir 'README.md'

$checks = @()

function Add-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Detail
    )

    $script:checks += [ordered]@{
        name = $Name
        pass = $Pass
        detail = $Detail
    }
}

function Test-Text {
    param(
        [string]$Text,
        [string]$Pattern
    )

    return [bool]([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline))
}

Add-Check -Name 'bridge file exists' -Pass (Test-Path -LiteralPath $bridgePath) -Detail $bridgePath
Add-Check -Name 'hook file exists' -Pass (Test-Path -LiteralPath $hookPath) -Detail $hookPath
Add-Check -Name 'README exists' -Pass (Test-Path -LiteralPath $readmePath) -Detail $readmePath

$bridgeText = if (Test-Path -LiteralPath $bridgePath) { Get-Content -LiteralPath $bridgePath -Raw } else { '' }
$hookText = if (Test-Path -LiteralPath $hookPath) { Get-Content -LiteralPath $hookPath -Raw } else { '' }
$readmeText = if (Test-Path -LiteralPath $readmePath) { Get-Content -LiteralPath $readmePath -Raw } else { '' }

Add-Check -Name 'ChainLink package constant' -Pass (Test-Text $bridgeText 'ChainLinkPackage\s*=\s*"org\.mesmerprism\.viscereality\.chainlink"') -Detail 'Bridge targets ChainLink package.'
Add-Check -Name 'ChainLink activity constant' -Pass (Test-Text $bridgeText 'ChainLinkActivity\s*=\s*"org\.mesmerprism\.viscereality\.chainlink\.ChainLinkActivity"') -Detail 'Bridge targets ChainLink activity.'
Add-Check -Name 'ChainLink command action' -Pass (Test-Text $bridgeText 'ChainLinkCommandAction\s*=\s*"org\.mesmerprism\.viscereality\.chainlink\.COMMAND"') -Detail 'Bridge uses command action.'
Add-Check -Name 'nextBlock command extra' -Pass (Test-Text $bridgeText 'ChainLinkCommandExtra\s*=\s*"mq\.command".*?ChainLinkNextBlockCommand\s*=\s*"nextBlock"') -Detail 'Bridge defines mq.command=nextBlock.'
Add-Check -Name 'direct ChainLink command method' -Pass (Test-Text $bridgeText 'SendChainLinkCommand\s*\(.*?setClassName"\s*,\s*ChainLinkPackage\s*,\s*ChainLinkActivity.*?putExtra"\s*,\s*ChainLinkCommandExtra') -Detail 'Bridge starts ChainLink explicitly.'
Add-Check -Name 'direct nextBlock helper' -Pass (Test-Text $bridgeText 'SendChainLinkNextBlock\s*\(.*?SendChainLinkCommand\s*\(\s*ChainLinkNextBlockCommand') -Detail 'Bridge exposes SendChainLinkNextBlock.'
Add-Check -Name 'recommended Android flags' -Pass (Test-Text $bridgeText '0x00020000\s*\|\s*0x20000000') -Detail 'Bridge uses REORDER_TO_FRONT and SINGLE_TOP flags.'

Add-Check -Name 'Unity XR left controller input' -Pass (Test-Text $hookText 'InputDevices\.GetDeviceAtXRNode\s*\(\s*XRNode\.LeftHand\s*\)') -Detail 'Hook reads left controller.'
Add-Check -Name 'Unity XR button usages' -Pass (Test-Text $hookText 'CommonUsages\.primaryButton.*?CommonUsages\.triggerButton.*?CommonUsages\.gripButton') -Detail 'Hook supports common Quest button features.'
Add-Check -Name 'rising-edge debounce' -Pass ((Test-Text $hookText 'risingEdge') -and (Test-Text $hookText 'debounceSeconds') -and (Test-Text $hookText 'nextAllowedSendTime')) -Detail 'Hook avoids repeated sends while held.'
Add-Check -Name 'timestamp extras' -Pass (Test-Text $hookText 'mq\.triggerTimestampUtc.*?mq\.triggerTimestampUnixMs') -Detail 'Hook stamps each trigger.'
Add-Check -Name 'metadata extras' -Pass (Test-Text $hookText 'mq\.experimentId.*?mq\.scenarioId.*?mq\.trialId.*?mq\.participantId') -Detail 'Hook forwards experiment metadata.'
Add-Check -Name 'hook calls ChainLink bridge' -Pass (Test-Text $hookText 'QuestQuestionnaireChainBridge\.SendChainLinkNextBlock') -Detail 'Hook sends ChainLink nextBlock.'

Add-Check -Name 'README documents hook files' -Pass ((Test-Text $readmeText 'ChainLinkControllerHook\.cs') -and (Test-Text $readmeText 'QuestQuestionnaireChainBridge\.cs')) -Detail 'README lists both Unity files.'
Add-Check -Name 'README documents command contract' -Pass (Test-Text $readmeText 'org\.mesmerprism\.viscereality\.chainlink\.COMMAND.*?mq\.command\s*=\s*nextBlock') -Detail 'README states ChainLink command contract.'

$failed = @($checks | Where-Object { -not $_.pass })
$summary = [ordered]@{
    schemaVersion = 'viscereality.unity-chainlink-hook-validation.v1'
    status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
    projectPath = $ProjectPath
    outputRoot = $OutputRoot
    bridge = $bridgePath
    hook = $hookPath
    readme = $readmePath
    checkCount = $checks.Count
    failedCount = $failed.Count
    checks = $checks
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'unity-chainlink-hook-validation-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]@{
    Status = $summary.status
    Checks = $checks.Count
    Failed = $failed.Count
    Summary = $summaryPath
}

if ($failed.Count -gt 0) {
    throw "Unity ChainLink hook validation failed. See $summaryPath"
}
