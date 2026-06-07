param(
    [string]$UnityProjectPath = "",
    [string]$UnityApk = "",
    [string]$Aapt = "",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [switch]$AllowControllerOnly
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "unity-input-modality-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}
if ([string]::IsNullOrWhiteSpace($UnityProjectPath)) {
    $UnityProjectPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\AweGreatDictatorUnity'))
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "artifacts\unity-input-modality\$RunId"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$checks = New-Object 'System.Collections.Generic.List[object]'
$warnings = New-Object 'System.Collections.Generic.List[string]'
$androidNs = 'http://schemas.android.com/apk/res/android'

function Add-Check {
    param([string]$Name, [bool]$Pass, [string]$Detail)

    $script:checks.Add([ordered]@{
        name = $Name
        pass = $Pass
        detail = $Detail
    }) | Out-Null
}

function Write-Json {
    param([object]$Value, [string]$Path, [int]$Depth = 10)

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-AndroidAttribute {
    param([System.Xml.XmlElement]$Node, [string]$Name)

    if ($null -eq $Node) {
        return ''
    }
    return [string]$Node.GetAttribute($Name, $script:androidNs)
}

function Resolve-Aapt {
    param([string]$RequestedAapt)

    if (-not [string]::IsNullOrWhiteSpace($RequestedAapt)) {
        if (Test-Path -LiteralPath $RequestedAapt) { return $RequestedAapt }
        throw "aapt not found: $RequestedAapt"
    }
    $unityRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\build-tools"
    if (Test-Path -LiteralPath $unityRoot) {
        $candidate = Get-ChildItem -LiteralPath $unityRoot -Recurse -Filter aapt.exe -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }
    $pathCandidate = Get-Command aapt.exe -ErrorAction SilentlyContinue
    if ($pathCandidate) {
        return $pathCandidate.Source
    }
    throw "Could not find aapt.exe. Pass -Aapt explicitly."
}

function Invoke-NativeText {
    param([string]$Exe, [string[]]$Arguments, [string]$OutputPath)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($OutputPath) {
        @($output) | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = (@($output) -join "`n")
    }
}

function Test-OpenXrFeatureEnabled {
    param([string]$Text, [string]$ClassName, [switch]$AndroidOnly)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }
    $blocks = [regex]::Matches($Text, '(?ms)^--- !u!114.*?(?=^--- !u!114|\z)')
    foreach ($match in $blocks) {
        $block = [string]$match.Value
        if ($block -notmatch [regex]::Escape($ClassName)) {
            continue
        }
        if ($AndroidOnly -and $block -notmatch 'm_Name:\s*.*Android') {
            continue
        }
        if ($block -match 'm_enabled:\s*1') {
            return $true
        }
    }
    return $false
}

function Test-Text {
    param([string]$Text, [string]$Pattern)

    return [bool]([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline))
}

$UnityProjectPath = [System.IO.Path]::GetFullPath($UnityProjectPath)
$sourceExists = Test-Path -LiteralPath $UnityProjectPath
$apkExists = -not [string]::IsNullOrWhiteSpace($UnityApk) -and (Test-Path -LiteralPath $UnityApk)

Add-Check -Name 'source or apk evidence available' -Pass ($sourceExists -or $apkExists) -Detail "source=$UnityProjectPath; apk=$UnityApk"

$sourceEvidence = [ordered]@{
    projectPath = $UnityProjectPath
    exists = $sourceExists
}

if ($sourceExists) {
    $manifestPath = Join-Path $UnityProjectPath 'Assets\Plugins\Android\AndroidManifest.xml'
    $openXrSettingsPath = Join-Path $UnityProjectPath 'Assets\XR\Settings\OpenXRPackageSettings.asset'
    $editorScripts = @(Get-ChildItem -LiteralPath (Join-Path $UnityProjectPath 'Assets\Editor') -Filter '*.cs' -ErrorAction SilentlyContinue)
    $editorScriptText = (@($editorScripts | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")

    $sourceEvidence.manifest = $manifestPath
    $sourceEvidence.openXrSettings = $openXrSettingsPath
    $sourceEvidence.editorScripts = @($editorScripts | ForEach-Object { $_.FullName })

    Add-Check -Name 'source Android manifest exists' -Pass (Test-Path -LiteralPath $manifestPath) -Detail $manifestPath
    if (Test-Path -LiteralPath $manifestPath) {
        [xml]$manifestXml = Get-Content -LiteralPath $manifestPath -Raw
        $featureNodes = @($manifestXml.SelectNodes('//uses-feature'))
        $permissionNodes = @($manifestXml.SelectNodes('//uses-permission'))
        $metadataNodes = @($manifestXml.SelectNodes('//meta-data'))
        $handFeature = @($featureNodes | Where-Object { (Get-AndroidAttribute -Node $_ -Name 'name') -eq 'oculus.software.handtracking' } | Select-Object -First 1)
        $handFeatureNode = if ($handFeature.Count -gt 0) { $handFeature[0] } else { $null }
        $handRequired = Get-AndroidAttribute -Node $handFeatureNode -Name 'required'
        $hasHandPermission = @($permissionNodes | Where-Object { (Get-AndroidAttribute -Node $_ -Name 'name') -eq 'com.oculus.permission.HAND_TRACKING' }).Count -gt 0
        $hasHandVersionMetadata = @($metadataNodes | Where-Object { (Get-AndroidAttribute -Node $_ -Name 'name') -eq 'com.oculus.handtracking.version' }).Count -gt 0

        Add-Check -Name 'source manifest optional hand tracking feature' -Pass ($AllowControllerOnly -or ($null -ne $handFeatureNode -and $handRequired -eq 'false')) -Detail 'uses-feature oculus.software.handtracking android:required="false"'
        Add-Check -Name 'source manifest hand tracking permission' -Pass ($AllowControllerOnly -or $hasHandPermission) -Detail 'uses-permission com.oculus.permission.HAND_TRACKING'
        Add-Check -Name 'source manifest hand tracking metadata' -Pass ($AllowControllerOnly -or $hasHandVersionMetadata) -Detail 'meta-data com.oculus.handtracking.version'

        $sourceEvidence.manifestFacts = [ordered]@{
            handTrackingFeature = ($null -ne $handFeatureNode)
            handTrackingRequired = $handRequired
            handTrackingRequiredFalse = ($null -ne $handFeatureNode -and $handRequired -eq 'false')
            handTrackingPermission = $hasHandPermission
            handTrackingVersionMetadata = $hasHandVersionMetadata
        }
    }

    Add-Check -Name 'source OpenXR settings exist' -Pass (Test-Path -LiteralPath $openXrSettingsPath) -Detail $openXrSettingsPath
    if (Test-Path -LiteralPath $openXrSettingsPath) {
        $openXrText = Get-Content -LiteralPath $openXrSettingsPath -Raw
        $controllerProfiles = [ordered]@{
            oculusTouch = Test-OpenXrFeatureEnabled -Text $openXrText -ClassName 'OculusTouchControllerProfile' -AndroidOnly
            metaQuestTouchPlus = Test-OpenXrFeatureEnabled -Text $openXrText -ClassName 'MetaQuestTouchPlusControllerProfile' -AndroidOnly
            metaQuestTouchPro = Test-OpenXrFeatureEnabled -Text $openXrText -ClassName 'MetaQuestTouchProControllerProfile' -AndroidOnly
        }
        $handProfiles = [ordered]@{
            handInteraction = Test-OpenXrFeatureEnabled -Text $openXrText -ClassName 'HandInteractionProfile' -AndroidOnly
            microsoftHandInteraction = Test-OpenXrFeatureEnabled -Text $openXrText -ClassName 'MicrosoftHandInteraction' -AndroidOnly
        }
        $controllerEnabled = @($controllerProfiles.Values | Where-Object { [bool]$_ }).Count -gt 0
        $handEnabled = @($handProfiles.Values | Where-Object { [bool]$_ }).Count -gt 0

        Add-Check -Name 'source OpenXR Quest controller profile enabled' -Pass $controllerEnabled -Detail 'At least one Android Quest controller interaction profile is enabled.'
        Add-Check -Name 'source OpenXR hand profile enabled' -Pass ($AllowControllerOnly -or $handEnabled) -Detail 'At least one Android hand interaction profile is enabled.'

        $sourceEvidence.openXrFacts = [ordered]@{
            controllerProfiles = $controllerProfiles
            handProfiles = $handProfiles
            controllerEnabled = $controllerEnabled
            handEnabled = $handEnabled
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($editorScriptText)) {
        $buildConfiguresController = (
            (Test-Text $editorScriptText 'SetOpenXRFeature\s*\(\s*OculusTouchControllerProfile\.featureId\s*,\s*true\s*\)') -or
            (Test-Text $editorScriptText 'SetOpenXRFeature\s*\(\s*MetaQuestTouchPlusControllerProfile\.featureId\s*,\s*true\s*\)') -or
            (Test-Text $editorScriptText 'SetOpenXRFeature\s*\(\s*MetaQuestTouchProControllerProfile\.featureId\s*,\s*true\s*\)')
        )
        $buildConfiguresHands = (
            (Test-Text $editorScriptText 'SetOpenXRFeature\s*\(\s*HandInteractionProfile\.featureId\s*,\s*true\s*\)') -or
            (Test-Text $editorScriptText 'SetOpenXRFeature\s*\(\s*MicrosoftHandInteraction\.featureId\s*,\s*true\s*\)')
        )
        Add-Check -Name 'source build scripts enable controller profiles' -Pass $buildConfiguresController -Detail 'Editor build scripts should not overwrite the OpenXR controller profile gate.'
        Add-Check -Name 'source build scripts enable hand profiles' -Pass ($AllowControllerOnly -or $buildConfiguresHands) -Detail 'Editor build scripts should not overwrite the OpenXR hand profile gate.'
        $sourceEvidence.editorScriptFacts = [ordered]@{
            configuresControllerProfiles = $buildConfiguresController
            configuresHandProfiles = $buildConfiguresHands
        }
    } else {
        $warnings.Add("No Unity editor build scripts found under Assets\Editor; source settings were checked directly.") | Out-Null
    }
}

$apkEvidence = [ordered]@{
    apk = $UnityApk
    exists = $apkExists
}

if ($apkExists) {
    $resolvedAapt = Resolve-Aapt -RequestedAapt $Aapt
    $apkManifestPath = Join-Path $OutputRoot 'unity-apk-aapt-manifest.txt'
    $manifest = Invoke-NativeText -Exe $resolvedAapt -Arguments @('dump', 'xmltree', $UnityApk, 'AndroidManifest.xml') -OutputPath $apkManifestPath
    if ($manifest.ExitCode -ne 0) {
        Add-Check -Name 'apk manifest readable' -Pass $false -Detail $apkManifestPath
    } else {
        Add-Check -Name 'apk manifest readable' -Pass $true -Detail $apkManifestPath
        $manifestText = [string]$manifest.Text
        $handTrackingFeature = $manifestText -match 'oculus\.software\.handtracking'
        $handTrackingRequiredFalse = $manifestText -match 'oculus\.software\.handtracking[\s\S]{0,600}android:required[^\r\n]*(false|\(type 0x12\)0x0)'
        $handTrackingPermission = $manifestText -match 'com\.oculus\.permission\.HAND_TRACKING|oculus\.permission\.handtracking'
        $handTrackingVersion = $manifestText -match 'com\.oculus\.handtracking\.version'

        Add-Check -Name 'apk optional hand tracking feature' -Pass ($AllowControllerOnly -or ($handTrackingFeature -and $handTrackingRequiredFalse)) -Detail 'Merged APK manifest must advertise optional hand tracking for generic demo/stimulus APKs.'
        Add-Check -Name 'apk hand tracking permission' -Pass ($AllowControllerOnly -or $handTrackingPermission) -Detail 'Merged APK manifest should include HAND_TRACKING permission when hand support is enabled.'
        Add-Check -Name 'apk hand tracking metadata' -Pass ($AllowControllerOnly -or $handTrackingVersion) -Detail 'Merged APK manifest should include com.oculus.handtracking.version metadata.'

        $apkEvidence.aapt = $resolvedAapt
        $apkEvidence.manifest = $apkManifestPath
        $apkEvidence.manifestFacts = [ordered]@{
            handTrackingFeature = $handTrackingFeature
            handTrackingRequiredFalse = $handTrackingRequiredFalse
            handTrackingPermission = $handTrackingPermission
            handTrackingVersionMetadata = $handTrackingVersion
        }
    }
}

if ($AllowControllerOnly) {
    $warnings.Add('AllowControllerOnly was set; hand support checks are informational for this run.') | Out-Null
}

$checkArray = @($checks.ToArray())
$failed = @($checkArray | Where-Object { -not $_.pass })
$summary = [ordered]@{
    schemaVersion = 'mq.unity_input_modality_static.v1'
    status = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
    allowControllerOnly = [bool]$AllowControllerOnly
    checkCount = $checkArray.Count
    failedCount = $failed.Count
    warningCount = $warnings.Count
    source = $sourceEvidence
    apk = $apkEvidence
    checks = $checkArray
    warnings = @($warnings.ToArray())
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$summaryPath = Join-Path $OutputRoot 'unity-input-modality-summary.json'
Write-Json -Value $summary -Path $summaryPath -Depth 14

[pscustomobject]@{
    Status = $summary.status
    Checks = $summary.checkCount
    Failed = $summary.failedCount
    Summary = $summaryPath
}

if ($failed.Count -gt 0) {
    throw "Unity input-modality validation failed. See $summaryPath"
}
