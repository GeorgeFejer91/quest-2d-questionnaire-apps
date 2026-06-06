param(
    [string]$UnityProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\Viscereality\Viscereality",
    [string]$TargetPackage = "com.Viscereality.ViscerealityPeriPersonalSpaceRight",
    [string]$OutputPath = "",
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Get-RelativePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $rootUri = [System.Uri]((Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\')
    $pathUri = [System.Uri]((Resolve-Path -LiteralPath $Path).Path)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Read-Text {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw
    }
    return ''
}

function Get-GuidFromMeta {
    param([string]$AssetPath)
    $metaPath = "$AssetPath.meta"
    if (-not (Test-Path -LiteralPath $metaPath)) {
        return ''
    }
    $text = Get-Content -LiteralPath $metaPath -Raw
    if ($text -match '(?m)^guid:\s*([a-fA-F0-9]+)') {
        return $Matches[1]
    }
    return ''
}

function Find-ScriptGuid {
    param(
        [string]$ProjectPath,
        [string]$FileName
    )
    $script = Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Assets') -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $script) {
        return ''
    }
    return Get-GuidFromMeta -AssetPath $script.FullName
}

function Get-BuildProfileInfo {
    param(
        [string]$ProjectPath,
        [string]$ProfilePath,
        [string]$TargetPackage
    )
    $text = Read-Text $ProfilePath
    $name = ''
    if ($text -match '(?m)^\s*m_Name:\s*(.+)$') {
        $name = $Matches[1].Trim()
    }
    $productName = ''
    if ($text -match "productName:\s*([^']+)'?") {
        $productName = $Matches[1].Trim()
    }
    $package = ''
    if ($text -match 'Android:\s*([A-Za-z0-9_\.]+)') {
        $package = $Matches[1].Trim()
    }

    $enabledScenes = New-Object System.Collections.Generic.List[string]
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match 'm_enabled:\s*1') {
            for ($j = $i + 1; $j -lt [Math]::Min($i + 5, $lines.Length); $j++) {
                if ($lines[$j] -match 'm_path:\s*(.+)$') {
                    $enabledScenes.Add($Matches[1].Trim())
                    break
                }
            }
        }
    }

    [pscustomobject][ordered]@{
        path = Get-RelativePath -Root $ProjectPath -Path $ProfilePath
        name = $name
        productName = $productName
        package = $package
        enabledScenes = @($enabledScenes.ToArray())
        matchesTargetPackage = [string]::Equals($package, $TargetPackage, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Get-SceneInfo {
    param(
        [string]$ProjectPath,
        [string]$ScenePath,
        [hashtable]$GuidMap,
        [string]$ExperimentRunGuid,
        [string]$HookGuid
    )
    $text = Read-Text $ScenePath
    $references = New-Object System.Collections.Generic.List[string]
    foreach ($key in $GuidMap.Keys) {
        $guid = $GuidMap[$key]
        if (-not [string]::IsNullOrWhiteSpace($guid) -and $text.Contains($guid)) {
            $references.Add($key)
        }
    }
    $hasExperimentRun = -not [string]::IsNullOrWhiteSpace($ExperimentRunGuid) -and $text.Contains($ExperimentRunGuid)
    $hasHookComponent = -not [string]::IsNullOrWhiteSpace($HookGuid) -and $text.Contains($HookGuid)
    $relative = Get-RelativePath -Root $ProjectPath -Path $ScenePath

    $score = 0
    if ($hasExperimentRun) { $score += 5 }
    if ($hasHookComponent) { $score += 2 }
    foreach ($ref in @($references.ToArray())) {
        if ($ref -match 'Space|PE_|PESussex') { $score += 1 }
    }
    if ($relative -match 'Pre Sussex') { $score += 1 }
    if ($relative -match 'Space|Sussex') { $score += 2 }

    [pscustomobject][ordered]@{
        path = $relative
        score = $score
        hasExperimentRun = $hasExperimentRun
        hasHookComponent = $hasHookComponent
        referencedCandidateAssets = @($references.ToArray())
    }
}

$project = Resolve-Path -LiteralPath $UnityProjectPath -ErrorAction Stop
$projectPath = $project.Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $runId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $OutputPath = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) "artifacts\unity-source-hook-candidates\$runId") 'unity-source-hook-candidates.json'
}

$manifestPath = Join-Path $projectPath 'Assets\Plugins\Android\AndroidManifest.xml'
$manifestText = Read-Text $manifestPath
$experimentRunPath = Join-Path $projectPath 'Assets\Scripts\ExperimentRun.cs'
$experimentRunText = Read-Text $experimentRunPath
$hookPath = Join-Path $projectPath 'Assets\Scripts\ExperimentChain\QuestExperimentChainHook.cs'
$hookText = Read-Text $hookPath
$bridgePath = Join-Path $projectPath 'Assets\Scripts\ExperimentChain\QuestQuestionnaireChainBridge.cs'

$candidateAssets = @(
    'Assets\Configs\Space.asset',
    'Assets\Configs\PE_DirectConfig.asset',
    'Assets\Configs\PE_SimpleLinearConfig.asset',
    'Assets\Configs\PESussexSimpleConfig.asset',
    'Assets\Configs\PE_AdvancedConfig.asset',
    'Assets\Configs\PE_GG.asset'
)
$guidMap = @{}
foreach ($relativeAsset in $candidateAssets) {
    $assetPath = Join-Path $projectPath $relativeAsset
    if (Test-Path -LiteralPath $assetPath) {
        $guidMap[$relativeAsset] = Get-GuidFromMeta -AssetPath $assetPath
    }
}

$experimentRunGuid = Find-ScriptGuid -ProjectPath $projectPath -FileName 'ExperimentRun.cs'
$hookGuid = Find-ScriptGuid -ProjectPath $projectPath -FileName 'QuestExperimentChainHook.cs'

$buildProfilesRoot = Join-Path $projectPath 'Assets\Settings\Build Profiles'
$buildProfiles = @()
if (Test-Path -LiteralPath $buildProfilesRoot) {
    $buildProfiles = @(Get-ChildItem -LiteralPath $buildProfilesRoot -File -Filter '*.asset' |
        ForEach-Object { Get-BuildProfileInfo -ProjectPath $projectPath -ProfilePath $_.FullName -TargetPackage $TargetPackage })
}

$sceneRoot = Join-Path $projectPath 'Assets\Scenes'
$sceneInfos = @()
if (Test-Path -LiteralPath $sceneRoot) {
    $sceneInfos = @(Get-ChildItem -LiteralPath $sceneRoot -Recurse -File -Filter '*.unity' |
        ForEach-Object { Get-SceneInfo -ProjectPath $projectPath -ScenePath $_.FullName -GuidMap $guidMap -ExperimentRunGuid $experimentRunGuid -HookGuid $hookGuid } |
        Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.path }; Descending = $false })
}

$matchingProfiles = @($buildProfiles | Where-Object { $_.matchesTargetPackage })
$experimentRunScenes = @($sceneInfos | Where-Object { $_.hasExperimentRun })
$bestCandidates = @($sceneInfos | Where-Object { $_.score -gt 0 } | Select-Object -First 8)

$status = if (@($matchingProfiles).Count -gt 0 -and @($experimentRunScenes).Count -gt 0) {
    'pass'
} elseif ($manifestText -match 'org\.mesmerprism\.viscereality\.CHAIN_COMMAND' -and $experimentRunText -match 'ContinueCurrentPlan') {
    'source-hook-ready-exact-build-profile-missing'
} else {
    'fail'
}

$summary = [ordered]@{
    schemaVersion = 'viscereality.unity-source-hook-candidates.v1'
    status = $status
    unityProjectPath = $projectPath
    targetPackage = $TargetPackage
    manifestHasChainCommandIntent = $manifestText -match 'org\.mesmerprism\.viscereality\.CHAIN_COMMAND'
    hookFiles = [ordered]@{
        experimentRun = [ordered]@{
            path = $experimentRunPath
            exists = Test-Path -LiteralPath $experimentRunPath
            guid = $experimentRunGuid
            callsContinueCurrentPlan = $experimentRunText -match 'QuestExperimentChainHook\.ContinueCurrentPlan'
            hasNotifyExperimentChainComplete = $experimentRunText -match 'NotifyExperimentChainComplete'
        }
        hook = [ordered]@{
            path = $hookPath
            exists = Test-Path -LiteralPath $hookPath
            guid = $hookGuid
            readsAutoContinueExtra = $hookText -match 'mq\.autoContinueDelayMs'
        }
        bridge = [ordered]@{
            path = $bridgePath
            exists = Test-Path -LiteralPath $bridgePath
        }
    }
    buildProfiles = $buildProfiles
    matchingBuildProfiles = $matchingProfiles
    scenesWithExperimentRun = $experimentRunScenes
    bestSceneCandidates = $bestCandidates
    candidateAssetGuids = $guidMap
    recommendation = if (@($matchingProfiles).Count -gt 0) {
        'Use the matching build profile and call QuestExperimentChainHook.ContinueCurrentPlan() from the real scenario end event.'
    } else {
        'Closed APK route remains wrapper/manual gate. For semantic source hook, create/recover a build profile with the target package and a confirmed scene that owns ExperimentRun or an equivalent end-event hook.'
    }
    completedAt = (Get-Date).ToString('o')
}

$outDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 20
} else {
    $summary | Format-List schemaVersion,status,unityProjectPath,targetPackage,manifestHasChainCommandIntent,completedAt
    @($buildProfiles) | Format-Table name,package,matchesTargetPackage,enabledScenes -AutoSize
    @($bestCandidates) | Format-Table score,path,hasExperimentRun,referencedCandidateAssets -AutoSize
    Write-Host "Source-hook candidate audit: $OutputPath"
}
