param(
    [string]$ProjectPath = "",
    [string]$RepoRoot = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Split-Path -Parent $PSScriptRoot
}
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
}
else {
    $RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
}

$gradle = Join-Path $ProjectPath 'gradlew.bat'
if (-not (Test-Path -LiteralPath $gradle)) {
    throw "Gradle wrapper not found: $gradle"
}

Push-Location $ProjectPath
try {
    & $gradle ':scenarioexamples:assembleDebug' '--no-daemon'
    if ($LASTEXITCODE -ne 0) {
        throw "Scenario example APK Gradle build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$variantMap = @(
    [ordered]@{
        variant = 'oneTrigger'
        source = 'scenarioexamples-oneTrigger-debug.apk'
        copies = @(
            'example-scenario-apk\apk\aesthetic-chills-1-trigger-demo.apk',
            'example-scenario-apk\aesthetic-chills-1-trigger-demo.apk'
        )
    },
    [ordered]@{
        variant = 'twoTrigger'
        source = 'scenarioexamples-twoTrigger-debug.apk'
        copies = @(
            'example-scenario-apk\apk\passive-2-trigger-demo.apk',
            'example-scenario-apk\multi-trigger-demos\2-triggers\quest-questionnaire-stimulus-demo-2-triggers.apk',
            'example-scenario-apk\multi-trigger-demos\2-triggers\QuestQuestionnaireStimulusDemo2Triggers.apk'
        )
    },
    [ordered]@{
        variant = 'threeCircle'
        source = 'scenarioexamples-threeCircle-debug.apk'
        copies = @(
            'example-scenario-apk\apk\three-circle-3-trigger-demo.apk'
        )
    }
)

$results = @()
foreach ($entry in $variantMap) {
    $sourceApk = Join-Path $ProjectPath ("scenarioexamples\build\outputs\apk\$($entry.variant)\debug\$($entry.source)")
    if (-not (Test-Path -LiteralPath $sourceApk)) {
        throw "Expected scenario example APK was not built: $sourceApk"
    }
    $hash = (Get-FileHash -LiteralPath $sourceApk -Algorithm SHA256).Hash
    $copyResults = @()
    foreach ($relativeDestination in $entry.copies) {
        $destination = Join-Path $RepoRoot $relativeDestination
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $sourceApk -Destination $destination -Force
        $copyResults += [ordered]@{
            path = $destination
            bytes = (Get-Item -LiteralPath $destination).Length
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        }
    }
    $results += [ordered]@{
        variant = $entry.variant
        sourceApk = $sourceApk
        bytes = (Get-Item -LiteralPath $sourceApk).Length
        sha256 = $hash
        copies = $copyResults
    }
}

$summaryDir = Join-Path $ProjectPath 'artifacts\example-scenario-apks'
New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
$summaryPath = Join-Path $summaryDir 'example-scenario-apks-summary.json'
$summary = [ordered]@{
    schemaVersion = 'questquestionnaire.example-scenario-apks.v1'
    status = 'pass'
    generatedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    repoRoot = $RepoRoot
    results = $results
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 20
