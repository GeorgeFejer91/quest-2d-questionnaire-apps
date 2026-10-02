param(
    [string]$ProjectPath = $PSScriptRoot,
    [string]$Unity = "",
    [string]$TempProjectPath = "C:\qq3demo",
    [switch]$CleanTemp
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-UnityProjectVersion {
    param([string]$ProjectPath)

    $projectVersionPath = Join-Path $ProjectPath 'ProjectSettings\ProjectVersion.txt'
    if (-not (Test-Path -LiteralPath $projectVersionPath)) {
        return ''
    }

    $versionLine = Get-Content -LiteralPath $projectVersionPath |
        Where-Object { $_ -match '^m_EditorVersion:\s*(.+)$' } |
        Select-Object -First 1
    if (-not $versionLine) {
        return ''
    }

    return ($versionLine -replace '^m_EditorVersion:\s*', '').Trim()
}

function Get-UnityHubEditorRoots {
    $roots = New-Object 'System.Collections.Generic.List[string]'

    $candidateRoots = @(
        (Join-Path $env:USERPROFILE 'Unity\Hub\Editor'),
        (Join-Path $env:ProgramFiles 'Unity\Hub\Editor')
    )

    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $candidateRoots += (Join-Path $programFilesX86 'Unity\Hub\Editor')
    }

    foreach ($root in $candidateRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root)) {
            $roots.Add((Resolve-Path -LiteralPath $root).Path) | Out-Null
        }
    }

    return @($roots.ToArray() | Select-Object -Unique)
}

function Get-InstalledUnityEditors {
    param([string[]]$HubRoots)

    $editors = New-Object 'System.Collections.Generic.List[object]'
    foreach ($root in $HubRoots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $unityExe = Join-Path $_.FullName 'Editor\Unity.exe'
            if (Test-Path -LiteralPath $unityExe) {
                $editors.Add([ordered]@{
                    version = $_.Name
                    path = (Resolve-Path -LiteralPath $unityExe).Path
                }) | Out-Null
            }
        }
    }

    return @($editors.ToArray() | Sort-Object version -Descending)
}

function Resolve-UnityEditor {
    param([string]$RequestedUnity, [string]$ProjectPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedUnity)) {
        if (Test-Path -LiteralPath $RequestedUnity) {
            return (Resolve-Path -LiteralPath $RequestedUnity).Path
        }
        throw "Unity editor not found: $RequestedUnity"
    }

    $projectVersion = Get-UnityProjectVersion -ProjectPath $ProjectPath
    $editors = @(Get-InstalledUnityEditors -HubRoots (Get-UnityHubEditorRoots))

    if (-not [string]::IsNullOrWhiteSpace($projectVersion)) {
        $matchingEditor = $editors |
            Where-Object { [string]$_.version -eq $projectVersion } |
            Select-Object -First 1
        if ($matchingEditor) {
            return [string]$matchingEditor.path
        }

        $installedVersions = if ($editors.Count -gt 0) {
            ($editors | ForEach-Object { "$($_.version) at $($_.path)" }) -join '; '
        } else {
            'none found'
        }
        throw "Could not find Unity editor version $projectVersion required by ProjectSettings\ProjectVersion.txt. Installed candidates: $installedVersions. Install the matching editor or pass -Unity explicitly if you intentionally want to use a different version."
    }

    $command = Get-Command Unity.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source)) {
        return $command.Source
    }

    if ($editors.Count -gt 0) {
        return [string]$editors[0].path
    }

    throw "Could not resolve Unity.exe. Pass -Unity with the full editor path."
}

function Get-UnityBuildFailureHint {
    param([string]$LogPath)

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return "Unity did not create the requested log file."
    }

    $logText = Get-Content -LiteralPath $LogPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($logText)) {
        return ""
    }

    if ($logText -match 'No valid Unity Editor license found') {
        return "No valid Unity Editor license found. Activate Unity for this Windows user before running the headless build."
    }
    if ($logText -match 'Switching to AndroidPlayer is disabled|Error building player because build target was unsupported|platform build profile settings is null') {
        return "Unity did not register Android Build Support for this editor. Install the matching editor through Unity Hub with Android Build Support, SDK/NDK tools, and OpenJDK."
    }
    if ($logText -match 'executeMethod method .* threw exception') {
        return "The Unity build method threw; inspect the log for the stack trace."
    }

    return ""
}

$projectFull = (Resolve-Path -LiteralPath $ProjectPath).Path
$unityEditor = Resolve-UnityEditor -RequestedUnity $Unity -ProjectPath $projectFull
$tempFull = [System.IO.Path]::GetFullPath($TempProjectPath)
if ([string]::IsNullOrWhiteSpace($tempFull) -or $tempFull.Length -lt 6) {
    throw "Refusing to use unsafe temp project path: $TempProjectPath"
}
if ($tempFull.StartsWith($projectFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Temp project path must not be inside the Unity source project."
}

if ($CleanTemp -and (Test-Path -LiteralPath $tempFull)) {
    $resolvedTemp = (Resolve-Path -LiteralPath $tempFull).Path
    if ($resolvedTemp -ne $tempFull) {
        throw "Unexpected temp project path: $resolvedTemp"
    }
    Remove-Item -LiteralPath $tempFull -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $tempFull | Out-Null
$excludeDirs = @('Library', 'Temp', 'Logs', 'Builds', 'obj', '.gradle')
$excludeFiles = @('*.csproj', '*.sln')
robocopy $projectFull $tempFull /MIR /XD $excludeDirs /XF $excludeFiles /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

$logDir = Join-Path $tempFull 'Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'build-android-shortpath.log'

$unityArgs = @(
    '-batchmode',
    '-quit',
    '-buildTarget',
    'Android',
    '-projectPath',
    $tempFull,
    '-executeMethod',
    'QuestQuestionnaireCircleDemoProjectSetup.BuildAndroid',
    '-logFile',
    $log
)
$unityProcess = Start-Process -FilePath $unityEditor -ArgumentList $unityArgs -Wait -PassThru -WindowStyle Hidden
if ($unityProcess.ExitCode -ne 0) {
    $failureHint = Get-UnityBuildFailureHint -LogPath $log
    $detail = if ([string]::IsNullOrWhiteSpace($failureHint)) { "" } else { " $failureHint" }
    throw "Unity build failed with exit code $($unityProcess.ExitCode).$detail See log: $log"
}

$sourceApk = Join-Path $tempFull 'Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk'
if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Unity reported success, but the APK was not found: $sourceApk"
}

$destDir = Join-Path $projectFull 'Builds'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$destApk = Join-Path $destDir 'QuestQuestionnaireThreeCircleTriggerDemo.apk'
Copy-Item -LiteralPath $sourceApk -Destination $destApk -Force

Get-Item -LiteralPath $destApk | Select-Object FullName,@{Name='SizeMB';Expression={[math]::Round($_.Length / 1MB, 2)}},LastWriteTime
