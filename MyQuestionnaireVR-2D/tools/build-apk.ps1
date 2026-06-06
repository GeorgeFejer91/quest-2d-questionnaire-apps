param(
    [string]$UnityAndroidRoot = "",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ConfigPath = "",
    [string]$ReferenceProjectPath = "",
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'

function Test-UnityAndroidRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return (Test-Path -LiteralPath (Join-Path $Path 'OpenJDK\bin\java.exe')) -and
        (Test-Path -LiteralPath (Join-Path $Path 'SDK'))
}

function Resolve-UnityAndroidRoot {
    param([string]$RequestedRoot)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $candidates.Add($RequestedRoot) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($env:UNITY_ANDROID_ROOT)) {
        $candidates.Add($env:UNITY_ANDROID_ROOT) | Out-Null
    }

    $editorRoots = @()
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $editorRoots += Join-Path $env:USERPROFILE 'Unity\Hub\Editor'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $editorRoots += Join-Path $env:ProgramFiles 'Unity\Hub\Editor'
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $editorRoots += Join-Path ${env:ProgramFiles(x86)} 'Unity\Hub\Editor'
    }

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

$UnityAndroidRoot = Resolve-UnityAndroidRoot -RequestedRoot $UnityAndroidRoot
if ([string]::IsNullOrWhiteSpace($UnityAndroidRoot)) {
    throw "Unity Android Build Support was not found. Install Unity with Android Build Support or set UNITY_ANDROID_ROOT to the AndroidPlayer folder."
}

$javaHome = Join-Path $UnityAndroidRoot 'OpenJDK'
$sdk = Join-Path $UnityAndroidRoot 'SDK'
if (-not (Test-Path -LiteralPath (Join-Path $javaHome 'bin\java.exe'))) {
    throw "Unity OpenJDK not found under: $javaHome"
}
if (-not (Test-Path -LiteralPath $sdk)) {
    throw "Unity Android SDK not found under: $sdk"
}

$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:UNITY_ANDROID_ROOT = $UnityAndroidRoot

function Invoke-Gradle {
    param(
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        & .\gradlew.bat --no-daemon --max-workers=1 @Arguments
        if ($LASTEXITCODE -eq 0) {
            return
        }

        if ($attempt -eq 1) {
            Write-Warning "Gradle command failed once; retrying to avoid transient daemon-stop failures."
        }
    }

    throw $FailureMessage
}

$localProperties = Join-Path $ProjectPath 'local.properties'
$sdkForward = $sdk -replace '\\', '/'
[System.IO.File]::WriteAllText($localProperties, "sdk.dir=$sdkForward`n", [System.Text.UTF8Encoding]::new($false))

$applyScript = Join-Path $ProjectPath 'tools\apply-questionnaire-config.ps1'
$validateAssetsScript = Join-Path $ProjectPath 'tools\validate-questionnaire-assets.ps1'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    & $applyScript -ReferenceProjectPath $ReferenceProjectPath | Out-Host
}
else {
    & $applyScript -ConfigPath $ConfigPath -ReferenceProjectPath $ReferenceProjectPath | Out-Host
}
& $validateAssetsScript | Out-Host

Push-Location $ProjectPath
try {
    if (-not $SkipTests) {
        Invoke-Gradle -Arguments @('testDebugUnitTest') -FailureMessage "Gradle unit tests failed."
    }

    Invoke-Gradle -Arguments @('assembleDebug') -FailureMessage "Gradle APK build failed."
}
finally {
    Pop-Location
}

$sourceApk = Join-Path $ProjectPath 'app\build\outputs\apk\debug\app-debug.apk'
if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Expected APK not found: $sourceApk"
}

$builds = Join-Path $ProjectPath 'Builds'
New-Item -ItemType Directory -Force -Path $builds | Out-Null
$targetApk = Join-Path $builds 'MyQuestionnaireVR-2D.apk'
Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force

$sha = (Get-FileHash -LiteralPath $targetApk -Algorithm SHA256).Hash
[pscustomobject]@{
    Apk = $targetApk
    SizeBytes = (Get-Item -LiteralPath $targetApk).Length
    SHA256 = $sha
    Status = 'OK'
} | Format-List
