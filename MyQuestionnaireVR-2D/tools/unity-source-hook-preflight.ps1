param(
    [string]$UnityProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\Quest 2D Questionnaire\Quest 2D Questionnaire",
    [double]$MinimumFreeGb = 5.0,
    [string]$OutputPath = "",
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function New-Check {
    param(
        [string]$Name,
        [ValidateSet('pass','warn','fail')]
        [string]$Status,
        [string]$Detail,
        [string]$Path = ''
    )
    [pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        path = $Path
    }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-ManifestDependency {
    param(
        $Manifest,
        [string]$Name,
        [string]$Expected
    )
    if ($Manifest -and $Manifest.dependencies -and ($Manifest.dependencies.PSObject.Properties.Name -contains $Name)) {
        $value = [string]$Manifest.dependencies.$Name
        return New-Check "manifest:$Name" 'pass' "Present as $value." $manifestPath
    }
    return New-Check "manifest:$Name" 'fail' "Missing. Recommended entry: `"$Name`": `"$Expected`"." $manifestPath
}

$project = Resolve-Path -LiteralPath $UnityProjectPath -ErrorAction Stop
$projectPath = $project.Path
$manifestPath = Join-Path $projectPath 'Packages\manifest.json'
$projectVersionPath = Join-Path $projectPath 'ProjectSettings\ProjectVersion.txt'
$metaPackagePath = Join-Path $projectPath 'Packages\com.meta.xr.sdk.interaction'
$metaPackageJsonPath = Join-Path $metaPackagePath 'package.json'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $runId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $OutputPath = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) "artifacts\unity-source-hook-preflight\$runId") 'unity-source-hook-preflight.json'
}

$checks = New-Object System.Collections.Generic.List[object]

$root = [System.IO.Path]::GetPathRoot($projectPath)
$driveName = $root.TrimEnd('\').TrimEnd(':')
$drive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
if ($drive) {
    $freeGb = [math]::Round($drive.Free / 1GB, 2)
    if ($freeGb -ge $MinimumFreeGb) {
        $checks.Add((New-Check 'disk-free' 'pass' "Drive $root has $freeGb GB free." $projectPath))
    }
    else {
        $checks.Add((New-Check 'disk-free' 'fail' "Drive $root has only $freeGb GB free; Unity package restore/builds need at least $MinimumFreeGb GB for this workflow." $projectPath))
    }
}
else {
    $checks.Add((New-Check 'disk-free' 'warn' "Could not determine free space for project root $root." $projectPath))
}

if (Test-Path -LiteralPath $projectVersionPath) {
    $versionText = Get-Content -LiteralPath $projectVersionPath -Raw
    if ($versionText -match 'm_EditorVersion:\s*UnknownUnityVersion') {
        $checks.Add((New-Check 'project-version' 'fail' 'ProjectSettings/ProjectVersion.txt says UnknownUnityVersion; Unity package restore/builds are not reliable until this is corrected.' $projectVersionPath))
    }
    elseif ($versionText -match 'm_EditorVersion:\s*(.+)') {
        $checks.Add((New-Check 'project-version' 'pass' "Unity editor version is $($Matches[1].Trim())." $projectVersionPath))
    }
    else {
        $checks.Add((New-Check 'project-version' 'warn' 'ProjectVersion.txt exists but no m_EditorVersion line was detected.' $projectVersionPath))
    }
}
else {
    $checks.Add((New-Check 'project-version' 'fail' 'ProjectSettings/ProjectVersion.txt is missing.' $projectVersionPath))
}

$manifest = Read-JsonFile $manifestPath
if ($manifest) {
    $checks.Add((New-Check 'manifest' 'pass' 'Packages/manifest.json is readable JSON.' $manifestPath))
}
else {
    $checks.Add((New-Check 'manifest' 'fail' 'Packages/manifest.json is missing or unreadable.' $manifestPath))
}

$conflictScanRoots = @('Assets', 'Packages', 'ProjectSettings')
$conflictScanFiles = New-Object System.Collections.Generic.List[object]
foreach ($relativeRoot in $conflictScanRoots) {
    $scanRoot = Join-Path $projectPath $relativeRoot
    if (Test-Path -LiteralPath $scanRoot) {
        Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.asmdef', '.asmref', '.asset', '.cs', '.json', '.meta', '.prefab', '.unity', '.xml') } |
            ForEach-Object { $conflictScanFiles.Add($_) }
    }
}
$conflictMarkers = @()
if ($conflictScanFiles.Count -gt 0) {
    $conflictMarkers = @(Select-String -LiteralPath @($conflictScanFiles | ForEach-Object { $_.FullName }) -Pattern '^(<<<<<<<|=======|>>>>>>>)' -ErrorAction SilentlyContinue)
}
if (@($conflictMarkers).Count -gt 0) {
    $examples = @($conflictMarkers | Select-Object -First 4 | ForEach-Object { "$($_.Path):$($_.LineNumber)" })
    $checks.Add((New-Check 'source-conflict-markers' 'fail' "Unresolved conflict markers found. Examples: $($examples -join '; ')." $projectPath))
}
else {
    $checks.Add((New-Check 'source-conflict-markers' 'pass' 'No unresolved conflict markers found in Unity source/config text files.' $projectPath))
}

$visualScriptingReferences = @()
$assetsRoot = Join-Path $projectPath 'Assets'
if (Test-Path -LiteralPath $assetsRoot) {
    $csFiles = @(Get-ChildItem -LiteralPath $assetsRoot -Recurse -File -Filter '*.cs' -Force -ErrorAction SilentlyContinue)
    if (@($csFiles).Count -gt 0) {
        $visualScriptingReferences = @(Select-String -LiteralPath @($csFiles | ForEach-Object { $_.FullName }) -Pattern 'Unity\.VisualScripting' -ErrorAction SilentlyContinue)
    }
}
if (@($visualScriptingReferences).Count -gt 0 -and -not ($manifest -and $manifest.dependencies -and ($manifest.dependencies.PSObject.Properties.Name -contains 'com.unity.visualscripting'))) {
    $examples = @($visualScriptingReferences | Select-Object -First 4 | ForEach-Object { "$($_.Path):$($_.LineNumber)" })
    $checks.Add((New-Check 'visual-scripting-dependency' 'fail' "Unity.VisualScripting references exist, but com.unity.visualscripting is missing from Packages/manifest.json. Examples: $($examples -join '; ')." $manifestPath))
}
elseif (@($visualScriptingReferences).Count -gt 0) {
    $checks.Add((New-Check 'visual-scripting-dependency' 'pass' 'Unity.VisualScripting references are matched by com.unity.visualscripting in Packages/manifest.json.' $manifestPath))
}

$requiredManifestEntries = @(
    @{ Name = 'com.meta.xr.sdk.core'; Expected = '201.0.0' },
    @{ Name = 'com.meta.xr.sdk.interaction'; Expected = '201.0.0' },
    @{ Name = 'com.meta.xr.sdk.interaction.ovr'; Expected = '201.0.0' },
    @{ Name = 'com.unity.textmeshpro'; Expected = '5.0.0' },
    @{ Name = 'com.unity.ugui'; Expected = '2.0.0' },
    @{ Name = 'com.unity.mathematics'; Expected = '1.3.2' },
    @{ Name = 'com.unity.burst'; Expected = '1.8.21' },
    @{ Name = 'com.unity.collections'; Expected = '2.4.0' },
    @{ Name = 'com.unity.xr.hands'; Expected = '1.7.2' },
    @{ Name = 'com.unity.xr.openxr'; Expected = '1.15.1' },
    @{ Name = 'com.labstreaminglayer.lsl4unity'; Expected = 'file:com.labstreaminglayer.lsl4unity' }
)
foreach ($entry in $requiredManifestEntries) {
    $checks.Add((Test-ManifestDependency -Manifest $manifest -Name $entry.Name -Expected $entry.Expected))
}

if ($manifest -and $manifest.dependencies -and ($manifest.dependencies.PSObject.Properties.Name -contains 'com.meta.xr.sdk.interaction')) {
    $metaDependency = [string]$manifest.dependencies.'com.meta.xr.sdk.interaction'
    if ($metaDependency.StartsWith('file:')) {
        if (Test-Path -LiteralPath $metaPackagePath) {
            if (Test-Path -LiteralPath $metaPackageJsonPath) {
                $checks.Add((New-Check 'embedded-meta-package' 'pass' 'Embedded Meta Interaction SDK package has package.json.' $metaPackageJsonPath))
            }
            else {
                $checks.Add((New-Check 'embedded-meta-package' 'fail' 'Packages/com.meta.xr.sdk.interaction exists but is missing package.json, so Unity will not treat it as an embedded package.' $metaPackageJsonPath))
            }
        }
        else {
            $checks.Add((New-Check 'embedded-meta-package' 'fail' 'Packages/com.meta.xr.sdk.interaction is missing.' $metaPackagePath))
        }
    }
    else {
        $checks.Add((New-Check 'meta-package-source' 'pass' "Meta Interaction SDK will resolve from manifest dependency $metaDependency." $manifestPath))
    }
}

$hookFiles = @(
    'Assets\Scripts\ExperimentChain\QuestQuestionnaireChainBridge.cs',
    'Assets\Scripts\ExperimentChain\QuestExperimentChainHook.cs',
    'Assets\Scripts\ExperimentRun.cs',
    'Assets\Plugins\Android\AndroidManifest.xml'
)
foreach ($relative in $hookFiles) {
    $path = Join-Path $projectPath $relative
    if (Test-Path -LiteralPath $path) {
        $checks.Add((New-Check "hook-file:$relative" 'pass' 'Required source-hook file exists.' $path))
    }
    else {
        $checks.Add((New-Check "hook-file:$relative" 'fail' 'Required source-hook file is missing.' $path))
    }
}

$manifestAndroid = Join-Path $projectPath 'Assets\Plugins\Android\AndroidManifest.xml'
if (Test-Path -LiteralPath $manifestAndroid) {
    $androidManifestText = Get-Content -LiteralPath $manifestAndroid -Raw
    if ($androidManifestText -match 'org\.questquestionnaire\.CHAIN_COMMAND') {
        $checks.Add((New-Check 'android-chain-intent-filter' 'pass' 'AndroidManifest.xml exposes org.questquestionnaire.CHAIN_COMMAND.' $manifestAndroid))
    }
    else {
        $checks.Add((New-Check 'android-chain-intent-filter' 'fail' 'AndroidManifest.xml does not expose org.questquestionnaire.CHAIN_COMMAND.' $manifestAndroid))
    }
}

$failCount = @($checks | Where-Object { $_.status -eq 'fail' }).Count
$warnCount = @($checks | Where-Object { $_.status -eq 'warn' }).Count
$status = if ($failCount -gt 0) { 'fail' } elseif ($warnCount -gt 0) { 'warn' } else { 'pass' }

$summary = [pscustomobject][ordered]@{
    schemaVersion = 'questquestionnaire.unity-source-hook-preflight.v1'
    status = $status
    unityProjectPath = $projectPath
    failCount = $failCount
    warnCount = $warnCount
    checks = @($checks.ToArray())
    completedAt = (Get-Date).ToString('o')
}

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 8
}
else {
    $summary | Format-List schemaVersion,status,unityProjectPath,failCount,warnCount,completedAt
    $checks | Sort-Object status,name | Format-Table status,name,detail -AutoSize
    Write-Host "Preflight summary: $OutputPath"
}

if ($status -eq 'fail') {
    exit 1
}
