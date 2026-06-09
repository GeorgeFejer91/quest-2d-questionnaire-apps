param(
    [int]$Port = 8776,
    [string]$ProjectPath = "",
    [string]$ReferenceProjectPath = "",
    [ValidateSet('Offline', 'OnlineConnector')]
    [string]$Mode = 'Offline',
    [string]$OnlinePageUrl = "http://127.0.0.1:8776/",
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
    $referenceCandidates = @(
        (Join-Path (Split-Path -Parent $ProjectPath) 'MyQuestionnaireVR'),
        (Join-Path (Split-Path -Parent (Split-Path -Parent $ProjectPath)) 'MyQuestionnaireVR')
    )
    foreach ($candidate in $referenceCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $ReferenceProjectPath = [System.IO.Path]::GetFullPath($candidate)
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($ReferenceProjectPath)) {
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
    $packagedEditorPath = Join-Path $ProjectPath 'index.html'
    if (Test-Path -LiteralPath $packagedEditorPath) {
        $EditorPath = $packagedEditorPath
    }
    else {
        throw "Questionnaire builder HTML not found: $EditorPath"
    }
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
$script:DirectHandoffJobs = @{}
$script:DirectHandoffJobOrder = New-Object 'System.Collections.Generic.List[string]'
$script:TwoDFirstLauncherJobs = @{}
$script:TwoDFirstLauncherJobOrder = New-Object 'System.Collections.Generic.List[string]'
$script:MinimalProtocolJobs = @{}
$script:MinimalProtocolJobOrder = New-Object 'System.Collections.Generic.List[string]'

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
        $requestedHeaders = [string]$Context.Request.Headers['Access-Control-Request-Headers']
        $allowedHeaders = 'Content-Type, X-MQ-Builder-Token'
        if (-not [string]::IsNullOrWhiteSpace($requestedHeaders)) {
            $allowedHeaders = $requestedHeaders
        }
        $Context.Response.Headers['Access-Control-Allow-Origin'] = $origin
        $Context.Response.Headers['Vary'] = 'Origin, Access-Control-Request-Headers'
        $Context.Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        $Context.Response.Headers['Access-Control-Allow-Headers'] = $allowedHeaders
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

function Write-BinaryFileResponse {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Path,
        [string]$DownloadFileName = ""
    )

    Set-CorsHeaders -Context $Context
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $Context.Response.StatusCode = $StatusCode
        $Context.Response.ContentType = $ContentType
        $Context.Response.ContentLength64 = $stream.Length
        $Context.Response.Headers['Cache-Control'] = 'no-store'
        $Context.Response.Headers['X-Content-Type-Options'] = 'nosniff'
        if (-not [string]::IsNullOrWhiteSpace($DownloadFileName)) {
            $safeName = (Get-SafeName -Value ([System.IO.Path]::GetFileNameWithoutExtension($DownloadFileName))) + [System.IO.Path]::GetExtension($DownloadFileName)
            $Context.Response.Headers['Content-Disposition'] = "attachment; filename=`"$safeName`""
        }
        $stream.CopyTo($Context.Response.OutputStream)
    }
    finally {
        $stream.Dispose()
        $Context.Response.OutputStream.Close()
    }
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

    if (-not (Test-FileExists -Path $Path)) {
        return $null
    }
    return ([System.IO.File]::ReadAllText((ConvertTo-LongPath -Path $Path)) | ConvertFrom-Json)
}

function ConvertTo-LongPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $IsWindows -and [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $fullPath
    }
    if ($fullPath.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
        return $fullPath
    }
    if ($fullPath.StartsWith('\\', [System.StringComparison]::Ordinal)) {
        return '\\?\UNC\' + $fullPath.TrimStart('\')
    }
    return '\\?\' + $fullPath
}

function Test-FileExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return [System.IO.File]::Exists((ConvertTo-LongPath -Path $Path))
}

function Read-TextFileIfExists {
    param([string]$Path)

    if (-not (Test-FileExists -Path $Path)) {
        return ''
    }

    $stream = [System.IO.File]::Open((ConvertTo-LongPath -Path $Path), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
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

function Get-JsonProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }
    if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }
    return $Object.PSObject.Properties[$Name].Value
}

function Get-NormalizedDirectoryPrefix {
    param([string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $directorySeparator = [string][System.IO.Path]::DirectorySeparatorChar
    $altDirectorySeparator = [string][System.IO.Path]::AltDirectorySeparatorChar
    if (-not $full.EndsWith($directorySeparator) -and -not $full.EndsWith($altDirectorySeparator)) {
        $full += [System.IO.Path]::DirectorySeparatorChar
    }
    return $full
}

function Get-ArtifactPreviewRoots {
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
    $roots = @(
        (Join-Path $ProjectPath 'artifacts'),
        (Join-Path $ReferenceProjectPath 'artifacts'),
        (Join-Path $repoRoot 'TemporalExperienceTracerVR-2D\artifacts')
    )
    return @($roots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [System.IO.Path]::GetFullPath([string]$_) } | Select-Object -Unique)
}

function Resolve-ArtifactPreviewPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Artifact preview path is required.'
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $extension = [System.IO.Path]::GetExtension($fullPath)
    if (-not $extension.Equals('.png', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Artifact preview only supports PNG files.'
    }

    $allowed = $false
    foreach ($root in Get-ArtifactPreviewRoots) {
        $rootPrefix = Get-NormalizedDirectoryPrefix -Path $root
        if ($fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $allowed = $true
            break
        }
    }
    if (-not $allowed) {
        throw "Artifact preview path is not allowed: $fullPath"
    }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Artifact preview path not found: $fullPath"
    }
    if ((Get-Item -LiteralPath $fullPath).PSIsContainer) {
        throw "Artifact preview path is a directory: $fullPath"
    }
    return $fullPath
}

function Test-PathInArtifactRoots {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in Get-ArtifactPreviewRoots) {
        $rootPrefix = Get-NormalizedDirectoryPrefix -Path $root
        if ($fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-ArtifactZipEntryName {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in Get-ArtifactPreviewRoots) {
        $rootPrefix = Get-NormalizedDirectoryPrefix -Path $root
        if ($fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $trimmedRoot = $rootPrefix.TrimEnd([char[]]@('\', '/'))
            $owner = Split-Path -Leaf (Split-Path -Parent $trimmedRoot)
            $relative = $fullPath.Substring($rootPrefix.Length).TrimStart('\', '/')
            return (($owner + '-artifacts/' + $relative) -replace '\\', '/')
        }
    }
    return ([System.IO.Path]::GetFileName($fullPath) -replace '\\', '/')
}

function Resolve-EvidenceBundleSummaryPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Evidence bundle summaryPath is required.'
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $extension = [System.IO.Path]::GetExtension($fullPath)
    if (-not $extension.Equals('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence bundle only accepts JSON summary paths.'
    }
    if (-not (Test-PathInArtifactRoots -Path $fullPath)) {
        throw "Evidence bundle summary path is not allowed: $fullPath"
    }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Evidence bundle summary path not found: $fullPath"
    }
    if ((Get-Item -LiteralPath $fullPath).PSIsContainer) {
        throw "Evidence bundle summary path is a directory: $fullPath"
    }
    return $fullPath
}

function Add-EvidenceBundleCandidate {
    param(
        [string]$Path,
        [hashtable]$Seen,
        [System.Collections.Generic.List[string]]$Files
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return
    }

    if (-not (Test-Path -LiteralPath $fullPath)) {
        return
    }
    $item = Get-Item -LiteralPath $fullPath
    if ($item.PSIsContainer) {
        return
    }
    if (-not (Test-PathInArtifactRoots -Path $fullPath)) {
        return
    }
    $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    $allowedExtensions = @('.json', '.txt', '.log', '.png', '.csv')
    if (-not ($allowedExtensions -contains $extension)) {
        return
    }

    $key = $fullPath.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) {
        return
    }
    $Seen[$key] = $true
    $Files.Add($fullPath) | Out-Null

    if ($extension -eq '.json') {
        try {
            $json = Get-Content -LiteralPath $fullPath -Encoding UTF8 -Raw | ConvertFrom-Json
            Add-EvidenceBundlePathsFromObject -Object $json -Seen $Seen -Files $Files
        }
        catch {
            return
        }
    }
}

function Add-EvidenceBundlePathsFromObject {
    param(
        [object]$Object,
        [hashtable]$Seen,
        [System.Collections.Generic.List[string]]$Files
    )

    if ($null -eq $Object) {
        return
    }
    if ($Object -is [string]) {
        Add-EvidenceBundleCandidate -Path $Object -Seen $Seen -Files $Files
        return
    }
    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        foreach ($item in $Object) {
            Add-EvidenceBundlePathsFromObject -Object $item -Seen $Seen -Files $Files
        }
        return
    }
    if ($Object.PSObject -and $Object.PSObject.Properties) {
        foreach ($property in $Object.PSObject.Properties) {
            Add-EvidenceBundlePathsFromObject -Object $property.Value -Seen $Seen -Files $Files
        }
    }
}

function New-EvidenceBundle {
    param([string]$SummaryPath)

    $summaryPathFull = Resolve-EvidenceBundleSummaryPath -Path $SummaryPath
    $bundleId = 'evidence-bundle-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $bundleDir = Join-Path $ProjectPath ("artifacts\builder-evidence-bundles\$bundleId")
    New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

    $seen = @{}
    $files = New-Object 'System.Collections.Generic.List[string]'
    Add-EvidenceBundleCandidate -Path $summaryPathFull -Seen $seen -Files $files

    $manifestFiles = @($files.ToArray() | ForEach-Object {
        $evidence = Get-FileEvidence -Path $_
        [ordered]@{
            sourcePath = $_
            entryName = Get-ArtifactZipEntryName -Path $_
            bytes = $evidence.bytes
            sha256 = $evidence.sha256
        }
    })
    $manifest = [ordered]@{
        schemaVersion = 'mq.builder_evidence_bundle.v1'
        bundleId = $bundleId
        sourceSummaryPath = $summaryPathFull
        fileCount = $manifestFiles.Count
        files = $manifestFiles
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $manifestPath = Join-Path $bundleDir 'evidence-bundle-manifest.json'
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $zipPath = Join-Path $bundleDir ($bundleId + '.zip')
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    $entryNames = @{}
    try {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $manifestPath, 'evidence-bundle-manifest.json', [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $entryNames['evidence-bundle-manifest.json'] = $true
        foreach ($file in @($files.ToArray())) {
            $entryName = Get-ArtifactZipEntryName -Path $file
            $baseEntryName = $entryName
            $suffix = 1
            while ($entryNames.ContainsKey($entryName.ToLowerInvariant())) {
                $directory = [System.IO.Path]::GetDirectoryName($baseEntryName) -replace '\\', '/'
                $leaf = [System.IO.Path]::GetFileNameWithoutExtension($baseEntryName)
                $extension = [System.IO.Path]::GetExtension($baseEntryName)
                $candidate = "$leaf-$suffix$extension"
                if (-not [string]::IsNullOrWhiteSpace($directory)) {
                    $candidate = "$directory/$candidate"
                }
                $entryName = $candidate
                $suffix += 1
            }
            $entryNames[$entryName.ToLowerInvariant()] = $true
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
    }

    return [ordered]@{
        status = 'ok'
        bundleId = $bundleId
        zipPath = $zipPath
        fileName = [System.IO.Path]::GetFileName($zipPath)
        fileCount = $manifestFiles.Count
        manifestPath = $manifestPath
    }
}

function Get-WorkflowCount {
    param(
        [object]$Counts,
        [string]$Name
    )

    $value = Get-JsonProperty -Object $Counts -Name $Name -Default 0
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return 0
    }
    return [int]$value
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
        $expectedBytes = Get-JsonProperty -Object $Render -Name 'byteLength' -Default 0
        $expectedHash = [string](Get-JsonProperty -Object $Render -Name 'sha256' -Default '')
        $expectedWidth = Get-JsonProperty -Object $Render -Name 'widthDp' -Default 0
        $expectedHeight = Get-JsonProperty -Object $Render -Name 'heightDp' -Default 0
        $evidence.matchesSummaryByteLength = ($expectedBytes -le 0 -or [int64]$evidence.bytes -eq [int64]$expectedBytes)
        $evidence.matchesSummarySha256 = ([string]::IsNullOrWhiteSpace($expectedHash) -or [string]$evidence.sha256 -eq $expectedHash)
        $evidence.matchesRenderDimensions = (
            ([int]$expectedWidth -le 0 -or [int]$evidence.width -eq [int]$expectedWidth) -and
            ([int]$expectedHeight -le 0 -or [int]$evidence.height -eq [int]$expectedHeight)
        )
    }
    return $evidence
}

function Get-RenderEvidence {
    param([string]$SummaryPath)

    $summary = Read-JsonFileIfExists -Path $SummaryPath
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
        status = Get-JsonProperty -Object $summary -Name 'status' -Default ''
        renderer = Get-JsonProperty -Object $summary -Name 'renderer' -Default ''
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
    }
}

function New-GenerationReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [int]$ExitCode,
        [bool]$SkipBuild,
        [bool]$RenderPreviewRequested
    )

    $apkPath = if ($null -ne $Summary) { [string](Get-JsonProperty -Object $Summary -Name 'apk' -Default '') } else { '' }
    $apkEvidence = Get-FileEvidence -Path $apkPath
    $renderSummaryPath = if ($null -ne $Summary) { [string](Get-JsonProperty -Object $Summary -Name 'renderSummary' -Default '') } else { '' }
    $renderEvidence = if (-not [string]::IsNullOrWhiteSpace($renderSummaryPath)) { Get-RenderEvidence -SummaryPath $renderSummaryPath } else { $null }
    $hashMatches = (
        $SkipBuild -or
        ([bool]$apkEvidence.exists -and -not [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $Summary -Name 'apkSha256' -Default '')) -and [string]$apkEvidence.sha256 -eq [string](Get-JsonProperty -Object $Summary -Name 'apkSha256' -Default ''))
    )
    $renderGatePass = (-not $RenderPreviewRequested) -or ($renderEvidence -and [bool]$renderEvidence.passesArtifactGate)

    $receiptStatus = 'pass'
    if ($ExitCode -ne 0 -or $null -eq $Summary -or (-not $SkipBuild -and -not [bool]$apkEvidence.exists) -or -not $hashMatches -or -not $renderGatePass) {
        $receiptStatus = 'fail'
    } elseif ($SkipBuild -or -not $RenderPreviewRequested) {
        $receiptStatus = 'partial-skipped-evidence'
    }

    return [ordered]@{
        schemaVersion = 'mq.builder.generate_apk_receipt.v1'
        kind = 'questionnaire-apk-generation'
        status = $receiptStatus
        exitCode = $ExitCode
        runId = if ($null -ne $Summary) { Get-JsonProperty -Object $Summary -Name 'runId' -Default '' } else { '' }
        buildSkipped = $SkipBuild
        renderPreviewRequested = $RenderPreviewRequested
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary -and (Test-Path -LiteralPath $SummaryPath))
            apkExists = [bool]$apkEvidence.exists
            apkHashMatchesSummary = $hashMatches
            renderArtifactGatePass = [bool]($renderEvidence -and $renderEvidence.passesArtifactGate)
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            apk = $apkEvidence
            renderSummaryPath = $renderSummaryPath
            render = if ($renderEvidence) {
                [ordered]@{
                    exists = [bool]$renderEvidence.exists
                    renderCount = Get-JsonProperty -Object $renderEvidence -Name 'renderCount' -Default 0
                    pngFileCount = Get-JsonProperty -Object $renderEvidence -Name 'pngFileCount' -Default 0
                    passesArtifactGate = [bool](Get-JsonProperty -Object $renderEvidence -Name 'passesArtifactGate' -Default $false)
                    samplePngs = @(Get-JsonProperty -Object $renderEvidence -Name 'samplePngs' -Default @())
                }
            } else {
                $null
            }
        }
        proofBoundary = 'APK generation and local render receipts prove trusted PC artifacts only; Quest install, replay/export, and direct handoff still require the later runner gates.'
    }
}

function New-WorkflowReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [string]$JobStatus = '',
        [string]$WorkflowStatus = ''
    )

    if ($null -eq $Summary) {
        $status = if ($JobStatus -eq 'running') { 'running' } else { 'missing-summary' }
        return [ordered]@{
            schemaVersion = 'mq.builder_to_quest.workflow_receipt.v1'
            status = $status
            jobStatus = $JobStatus
            workflowStatus = $WorkflowStatus
            offlineEvidenceReady = $false
            physicalQuestProductPathPending = $true
            defaultDirectPendingIntentApproved = $false
            counts = [ordered]@{
                requirements = 0
                failed = 0
                blocked = 0
                pending = 0
                warn = 0
                skipped = 0
            }
            artifacts = [ordered]@{
                summaryPath = $SummaryPath
            }
            proofBoundary = 'Workflow evidence is not inspectable until the matrix summary is written.'
        }
    }

    $summaryWorkflowStatus = [string](Get-JsonProperty -Object $Summary -Name 'status' -Default $WorkflowStatus)
    $countsSource = Get-JsonProperty -Object $Summary -Name 'counts'
    $counts = [ordered]@{
        requirements = Get-WorkflowCount -Counts $countsSource -Name 'requirements'
        failed = Get-WorkflowCount -Counts $countsSource -Name 'failed'
        blocked = Get-WorkflowCount -Counts $countsSource -Name 'blocked'
        pending = Get-WorkflowCount -Counts $countsSource -Name 'pending'
        warn = Get-WorkflowCount -Counts $countsSource -Name 'warn'
        skipped = Get-WorkflowCount -Counts $countsSource -Name 'skipped'
    }

    $evidence = Get-JsonProperty -Object $Summary -Name 'evidence'
    $questionnaireApk = Get-JsonProperty -Object $evidence -Name 'questionnaireApk'
    $temporalTracerApk = Get-JsonProperty -Object $evidence -Name 'temporalTracerApk'
    $unityApk = Get-JsonProperty -Object $evidence -Name 'unityApk'
    $questionnaireRender = Get-JsonProperty -Object $evidence -Name 'questionnaireRender'
    $temporalRender = Get-JsonProperty -Object $evidence -Name 'temporalTracerRender'
    $triggerBlockMapping = Get-JsonProperty -Object $evidence -Name 'triggerBlockMapping'
    $unityInputModality = Get-JsonProperty -Object $evidence -Name 'unityInputModality'
    $panelReturnContracts = Get-JsonProperty -Object $evidence -Name 'panelReturnContracts'
    $directPreflight = Get-JsonProperty -Object $evidence -Name 'directHandoffPreflight'
    $questAdb = Get-JsonProperty -Object $evidence -Name 'questAdb'
    $directQuest = Get-JsonProperty -Object $evidence -Name 'directQuestHandoff'
    $decisionGate = Get-JsonProperty -Object $directQuest -Name 'decisionGate'
    $defaultDirectApproved = if ($null -ne $decisionGate) { [bool](Get-JsonProperty -Object $decisionGate -Name 'defaultDirectPendingIntentApproved' -Default $false) } else { $false }
    $physicalPending = -not $defaultDirectApproved
    $offlineEvidenceReady = ($counts.failed -eq 0 -and $counts.blocked -eq 0)

    $receiptStatus = 'pass'
    if ($summaryWorkflowStatus -eq 'fail' -or $summaryWorkflowStatus -eq 'error' -or $counts.failed -gt 0) {
        $receiptStatus = 'fail'
    } elseif ($summaryWorkflowStatus -eq 'blocked' -or $counts.blocked -gt 0) {
        $receiptStatus = 'blocked'
    } elseif ($counts.skipped -gt 0) {
        $receiptStatus = 'partial-skipped-evidence'
    } elseif ($physicalPending -or $counts.pending -gt 0 -or $counts.warn -gt 0 -or $summaryWorkflowStatus -eq 'warn') {
        $receiptStatus = 'pass-with-physical-pending'
    }

    return [ordered]@{
        schemaVersion = 'mq.builder_to_quest.workflow_receipt.v1'
        status = $receiptStatus
        jobStatus = $JobStatus
        workflowStatus = $summaryWorkflowStatus
        offlineEvidenceReady = $offlineEvidenceReady
        physicalQuestProductPathPending = $physicalPending
        defaultDirectPendingIntentApproved = $defaultDirectApproved
        counts = $counts
        checks = [ordered]@{
            questionnaireApkExists = [bool](Get-JsonProperty -Object $questionnaireApk -Name 'exists' -Default $false)
            questionnaireRenderArtifactGatePass = [bool](Get-JsonProperty -Object $questionnaireRender -Name 'passesArtifactGate' -Default $false)
            temporalTracerRenderArtifactGatePass = [bool](Get-JsonProperty -Object $temporalRender -Name 'passesArtifactGate' -Default $false)
            triggerBlockMappingPass = ([string](Get-JsonProperty -Object $triggerBlockMapping -Name 'status' -Default '') -eq 'pass')
            unityInputModalityGuardrailsPass = ([string](Get-JsonProperty -Object $unityInputModality -Name 'status' -Default '') -eq 'pass')
            panelReturnContractsPass = ([string](Get-JsonProperty -Object $panelReturnContracts -Name 'status' -Default '') -eq 'pass')
            directHandoffPreflightPass = ([string](Get-JsonProperty -Object $directPreflight -Name 'preflightStatus' -Default (Get-JsonProperty -Object $directPreflight -Name 'status' -Default '')) -eq 'pass')
            questAdbProductPathReady = [bool](Get-JsonProperty -Object $questAdb -Name 'productPathReady' -Default $false)
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            questionnaireApk = $questionnaireApk
            temporalTracerApk = $temporalTracerApk
            unityApk = $unityApk
            questionnaireRender = [ordered]@{
                summaryPath = Get-JsonProperty -Object $questionnaireRender -Name 'summaryPath'
                renderCount = Get-JsonProperty -Object $questionnaireRender -Name 'renderCount' -Default 0
                pngFileCount = Get-JsonProperty -Object $questionnaireRender -Name 'pngFileCount' -Default 0
                passesArtifactGate = [bool](Get-JsonProperty -Object $questionnaireRender -Name 'passesArtifactGate' -Default $false)
                samplePngs = @(Get-JsonProperty -Object $questionnaireRender -Name 'samplePngs' -Default @())
            }
            temporalTracerRender = [ordered]@{
                summaryPath = Get-JsonProperty -Object $temporalRender -Name 'summaryPath'
                renderCount = Get-JsonProperty -Object $temporalRender -Name 'renderCount' -Default 0
                pngFileCount = Get-JsonProperty -Object $temporalRender -Name 'pngFileCount' -Default 0
                passesArtifactGate = [bool](Get-JsonProperty -Object $temporalRender -Name 'passesArtifactGate' -Default $false)
                samplePngs = @(Get-JsonProperty -Object $temporalRender -Name 'samplePngs' -Default @())
            }
            unityInputModality = [ordered]@{
                status = Get-JsonProperty -Object $unityInputModality -Name 'status'
                failedCount = Get-JsonProperty -Object $unityInputModality -Name 'failedCount' -Default 0
                source = Get-JsonProperty -Object $unityInputModality -Name 'source'
                apk = Get-JsonProperty -Object $unityInputModality -Name 'apk'
            }
            directHandoffPreflight = [ordered]@{
                summaryPath = Get-JsonProperty -Object $directPreflight -Name 'summaryPath'
                status = Get-JsonProperty -Object $directPreflight -Name 'status'
                preflightStatus = Get-JsonProperty -Object $directPreflight -Name 'preflightStatus'
                triggerCount = Get-JsonProperty -Object $directPreflight -Name 'triggerCount' -Default 0
            }
            questAdb = [ordered]@{
                readiness = Get-JsonProperty -Object $questAdb -Name 'readiness'
                productPathStatus = Get-JsonProperty -Object $questAdb -Name 'productPathStatus' -Default 'not-probed'
                productPathReady = [bool](Get-JsonProperty -Object $questAdb -Name 'productPathReady' -Default $false)
            }
            directQuestHandoff = [ordered]@{
                status = Get-JsonProperty -Object $directQuest -Name 'status'
                dryRun = [bool](Get-JsonProperty -Object $directQuest -Name 'dryRun' -Default $false)
                requestedQuestTrials = Get-JsonProperty -Object $directQuest -Name 'requestedQuestTrials' -Default 0
                attemptedTrialCount = Get-JsonProperty -Object $directQuest -Name 'attemptedTrialCount' -Default 0
                passCount = Get-JsonProperty -Object $directQuest -Name 'passCount' -Default 0
                blockedCount = Get-JsonProperty -Object $directQuest -Name 'blockedCount' -Default 0
                failCount = Get-JsonProperty -Object $directQuest -Name 'failCount' -Default 0
                decisionGate = $decisionGate
            }
        }
        proofBoundary = 'Direct PendingIntent cannot become the production default until 10 clean real Quest product-path trials plus one manual headset pass prove the route.'
    }
}

function New-InstallJobReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [string]$JobStatus = '',
        [string]$InstallStatus = '',
        [bool]$DryRun = $false
    )

    $apk = Get-JsonProperty -Object $Summary -Name 'apk'
    $install = Get-JsonProperty -Object $Summary -Name 'install'
    $packageCheck = Get-JsonProperty -Object $Summary -Name 'packageCheck'
    $summaryDryRun = if ($null -ne $Summary) { [bool](Get-JsonProperty -Object $Summary -Name 'dryRun' -Default $DryRun) } else { $DryRun }
    return [ordered]@{
        schemaVersion = 'mq.builder_runner.job_receipt.v1'
        kind = 'quest-apk-install'
        status = if ([string]::IsNullOrWhiteSpace($InstallStatus)) { $JobStatus } else { $InstallStatus }
        jobStatus = $JobStatus
        actionStatus = $InstallStatus
        dryRun = $summaryDryRun
        physicalQuestProductPathPending = $true
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary)
            apkExists = [bool](Get-JsonProperty -Object $apk -Name 'path' -Default '')
            readinessOnline = ([string](Get-JsonProperty -Object $Summary -Name 'readiness' -Default '') -eq 'online')
            installAttempted = [bool](Get-JsonProperty -Object $install -Name 'attempted' -Default $false)
            packageCheckAttempted = [bool](Get-JsonProperty -Object $packageCheck -Name 'attempted' -Default $false)
            dryRunContractPass = ($summaryDryRun -and [string]$InstallStatus -eq 'pass' -and -not [bool](Get-JsonProperty -Object $install -Name 'attempted' -Default $false))
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            apk = $apk
            package = Get-JsonProperty -Object $Summary -Name 'package'
            serial = Get-JsonProperty -Object $Summary -Name 'serial'
            readiness = Get-JsonProperty -Object $Summary -Name 'readiness'
            readinessStatus = Get-JsonProperty -Object $Summary -Name 'readinessStatus'
            readinessSummaryPath = Get-JsonProperty -Object $Summary -Name 'readinessSummaryPath'
            install = $install
            packageCheck = $packageCheck
        }
        proofBoundary = 'Install evidence only proves the APK load contract. Replay/export and direct handoff still need product-path Quest evidence.'
    }
}

function New-QuestReplayJobReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [string]$JobStatus = '',
        [string]$ReplayStatus = '',
        [bool]$DryRun = $false
    )

    $apk = Get-JsonProperty -Object $Summary -Name 'apk'
    $productPath = Get-JsonProperty -Object $Summary -Name 'productPath'
    $questValidation = Get-JsonProperty -Object $Summary -Name 'questValidation'
    $summaryDryRun = if ($null -ne $Summary) { [bool](Get-JsonProperty -Object $Summary -Name 'dryRun' -Default $DryRun) } else { $DryRun }
    $productPathStatus = [string](Get-JsonProperty -Object $Summary -Name 'productPathStatus' -Default 'not-probed')
    $wakeBeforeReadiness = [bool](Get-JsonProperty -Object $Summary -Name 'wakeBeforeReadiness' -Default $false)
    return [ordered]@{
        schemaVersion = 'mq.builder_runner.job_receipt.v1'
        kind = 'quest-replay-export'
        status = if ([string]::IsNullOrWhiteSpace($ReplayStatus)) { $JobStatus } else { $ReplayStatus }
        jobStatus = $JobStatus
        actionStatus = $ReplayStatus
        dryRun = $summaryDryRun
        wakeBeforeReadiness = $wakeBeforeReadiness
        productPathStatus = $productPathStatus
        productPathReady = [bool](Get-JsonProperty -Object $productPath -Name 'ready' -Default $false)
        physicalQuestProductPathPending = ($summaryDryRun -or $productPathStatus -ne 'ready' -or [string]$ReplayStatus -ne 'pass')
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary)
            apkExists = [bool](Get-JsonProperty -Object $apk -Name 'path' -Default '')
            readinessOnline = ([string](Get-JsonProperty -Object $Summary -Name 'readiness' -Default '') -eq 'online')
            productPathReady = [bool](Get-JsonProperty -Object $productPath -Name 'ready' -Default $false)
            questValidationSummaryWritten = -not [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $Summary -Name 'questValidationSummaryPath' -Default ''))
            replayExportAttempted = ($null -ne $questValidation)
            dryRunContractPass = ($summaryDryRun -and [string]$ReplayStatus -ne 'fail' -and $null -eq $questValidation)
            wakeBeforeReadiness = $wakeBeforeReadiness
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            apk = $apk
            serial = Get-JsonProperty -Object $Summary -Name 'serial'
            readiness = Get-JsonProperty -Object $Summary -Name 'readiness'
            readinessStatus = Get-JsonProperty -Object $Summary -Name 'readinessStatus'
            readinessSummaryPath = Get-JsonProperty -Object $Summary -Name 'readinessSummaryPath'
            productPathStatus = $productPathStatus
            productPathBlockedReasons = @(Get-JsonProperty -Object $Summary -Name 'productPathBlockedReasons' -Default @())
            readinessWakeAttempt = Get-JsonProperty -Object $Summary -Name 'readinessWakeAttempt'
            questValidationSummaryPath = Get-JsonProperty -Object $Summary -Name 'questValidationSummaryPath'
            questValidation = $questValidation
        }
        proofBoundary = 'Replay/export dry-runs prove the endpoint contract only. Live replay/export requires product-path readiness and Quest-side export evidence.'
    }
}

function New-DirectHandoffJobReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [string]$JobStatus = '',
        [string]$HandoffStatus = '',
        [bool]$DryRun = $false
    )

    $preflight = Get-JsonProperty -Object $Summary -Name 'preflight'
    $decisionGate = Get-JsonProperty -Object $Summary -Name 'decisionGate'
    $summaryDryRun = if ($null -ne $Summary) { [bool](Get-JsonProperty -Object $Summary -Name 'dryRun' -Default $DryRun) } else { $DryRun }
    $wakeBeforeReadiness = [bool](Get-JsonProperty -Object $Summary -Name 'wakeBeforeReadiness' -Default $false)
    $defaultDirectApproved = if ($null -ne $decisionGate) { [bool](Get-JsonProperty -Object $decisionGate -Name 'defaultDirectPendingIntentApproved' -Default $false) } else { $false }
    $candidateAStatus = Get-JsonProperty -Object $decisionGate -Name 'candidateAStatus'
    $preflightStatus = Get-JsonProperty -Object $decisionGate -Name 'preflightStatus' -Default (Get-JsonProperty -Object $preflight -Name 'status')
    $receiptStatus = if ([string]$HandoffStatus -eq 'pass' -and -not $defaultDirectApproved) { 'pass-with-physical-pending' } elseif ([string]::IsNullOrWhiteSpace($HandoffStatus)) { $JobStatus } else { $HandoffStatus }
    return [ordered]@{
        schemaVersion = 'mq.builder_runner.job_receipt.v1'
        kind = 'direct-pendingintent-handoff'
        status = $receiptStatus
        jobStatus = $JobStatus
        actionStatus = $HandoffStatus
        dryRun = $summaryDryRun
        wakeBeforeReadiness = $wakeBeforeReadiness
        candidateAStatus = $candidateAStatus
        defaultDirectPendingIntentApproved = $defaultDirectApproved
        physicalQuestProductPathPending = (-not $defaultDirectApproved)
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary)
            preflightPass = ([string]$preflightStatus -eq 'pass')
            attemptedTrials = [int](Get-JsonProperty -Object $Summary -Name 'attemptedTrialCount' -Default 0)
            passCount = [int](Get-JsonProperty -Object $Summary -Name 'passCount' -Default 0)
            blockedCount = [int](Get-JsonProperty -Object $Summary -Name 'blockedCount' -Default 0)
            failCount = [int](Get-JsonProperty -Object $Summary -Name 'failCount' -Default 0)
            dryRunContractPass = ($summaryDryRun -and [string]$HandoffStatus -eq 'pass' -and [string]$candidateAStatus -eq 'dry-run-only' -and -not $defaultDirectApproved)
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            preflightStatus = $preflightStatus
            triggerCount = Get-JsonProperty -Object $preflight -Name 'triggerCount' -Default 0
            requestedTrialCount = Get-JsonProperty -Object $decisionGate -Name 'requestedTrialCount' -Default (Get-JsonProperty -Object $Summary -Name 'trialCount' -Default 0)
            attemptedTrialCount = Get-JsonProperty -Object $Summary -Name 'attemptedTrialCount' -Default 0
            passCount = Get-JsonProperty -Object $Summary -Name 'passCount' -Default 0
            warnCount = Get-JsonProperty -Object $Summary -Name 'warnCount' -Default 0
            blockedCount = Get-JsonProperty -Object $Summary -Name 'blockedCount' -Default 0
            failCount = Get-JsonProperty -Object $Summary -Name 'failCount' -Default 0
            wakeBeforeReadiness = $wakeBeforeReadiness
            decisionGate = $decisionGate
        }
        proofBoundary = 'A dry-run can approve the direct handoff runner contract, but production direct PendingIntent needs real Quest product-path trials plus a manual headset pass.'
    }
}

function New-TwoDFirstLauncherJobReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [string]$JobStatus = '',
        [string]$LauncherStatus = '',
        [bool]$DryRun = $false
    )

    $preflight = Get-JsonProperty -Object $Summary -Name 'preflight'
    $decisionGate = Get-JsonProperty -Object $Summary -Name 'decisionGate'
    $summaryDryRun = if ($null -ne $Summary) { [bool](Get-JsonProperty -Object $Summary -Name 'dryRun' -Default $DryRun) } else { $DryRun }
    $wakeBeforeReadiness = [bool](Get-JsonProperty -Object $Summary -Name 'wakeBeforeReadiness' -Default $false)
    $gatePassed = if ($null -ne $decisionGate) { [bool](Get-JsonProperty -Object $decisionGate -Name 'twoDFirstLauncherGatePassed' -Default $false) } else { $false }
    $participantFrontDoor = Get-JsonProperty -Object $decisionGate -Name 'participantFrontDoor' -Default 'questionnaire-apk'
    $preflightStatus = Get-JsonProperty -Object $decisionGate -Name 'preflightStatus' -Default (Get-JsonProperty -Object $preflight -Name 'status')
    $receiptStatus = if ([string]$LauncherStatus -eq 'pass' -and -not $gatePassed) { 'pass-with-physical-pending' } elseif ([string]::IsNullOrWhiteSpace($LauncherStatus)) { $JobStatus } else { $LauncherStatus }
    return [ordered]@{
        schemaVersion = 'mq.builder_runner.job_receipt.v1'
        kind = '2d-first-launcher'
        status = $receiptStatus
        jobStatus = $JobStatus
        actionStatus = $LauncherStatus
        dryRun = $summaryDryRun
        wakeBeforeReadiness = $wakeBeforeReadiness
        participantFrontDoor = $participantFrontDoor
        twoDFirstLauncherGatePassed = $gatePassed
        physicalQuestProductPathPending = (-not $gatePassed)
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary)
            preflightPass = ([string]$preflightStatus -eq 'pass')
            attemptedTrials = [int](Get-JsonProperty -Object $Summary -Name 'attemptedTrialCount' -Default 0)
            passCount = [int](Get-JsonProperty -Object $Summary -Name 'passCount' -Default 0)
            blockedCount = [int](Get-JsonProperty -Object $Summary -Name 'blockedCount' -Default 0)
            failCount = [int](Get-JsonProperty -Object $Summary -Name 'failCount' -Default 0)
            dryRunContractPass = ($summaryDryRun -and [string]$LauncherStatus -eq 'pass' -and [string]$preflightStatus -eq 'pass' -and -not $gatePassed)
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            preflightStatus = $preflightStatus
            requestedTrialCount = Get-JsonProperty -Object $decisionGate -Name 'requestedTrialCount' -Default (Get-JsonProperty -Object $Summary -Name 'trialCount' -Default 0)
            attemptedTrialCount = Get-JsonProperty -Object $Summary -Name 'attemptedTrialCount' -Default 0
            passCount = Get-JsonProperty -Object $Summary -Name 'passCount' -Default 0
            warnCount = Get-JsonProperty -Object $Summary -Name 'warnCount' -Default 0
            blockedCount = Get-JsonProperty -Object $Summary -Name 'blockedCount' -Default 0
            failCount = Get-JsonProperty -Object $Summary -Name 'failCount' -Default 0
            wakeBeforeReadiness = $wakeBeforeReadiness
            preflight = $preflight
            decisionGate = $decisionGate
        }
        proofBoundary = 'A dry-run proves the packaged 2D-first front-door contract only. Production approval still needs one real Quest launch from the questionnaire APK into Unity plus manual headset observation.'
    }
}

function New-MinimalProtocolJobReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [string]$JobStatus = '',
        [string]$ProtocolStatus = '',
        [bool]$RunLive = $false
    )

    $summaryRunLive = if ($null -ne $Summary) { [bool](Get-JsonProperty -Object $Summary -Name 'runLive' -Default $RunLive) } else { $RunLive }
    $statuses = Get-JsonProperty -Object $Summary -Name 'statuses'
    $remainingLiveGates = @(Get-JsonProperty -Object $Summary -Name 'remainingLiveGates' -Default @())
    $failedStepCount = [int](Get-JsonProperty -Object $Summary -Name 'failedStepCount' -Default 0)
    $statusValue = if ([string]::IsNullOrWhiteSpace($ProtocolStatus)) { $JobStatus } else { $ProtocolStatus }
    $physicalPending = (-not $summaryRunLive) -or $remainingLiveGates.Count -gt 0
    $receiptStatus = if ($statusValue -eq 'pass' -and $physicalPending) { 'pass-with-physical-pending' } else { $statusValue }

    return [ordered]@{
        schemaVersion = 'mq.builder_runner.job_receipt.v1'
        kind = 'minimal-apk-trigger-protocol'
        status = $receiptStatus
        jobStatus = $JobStatus
        actionStatus = $ProtocolStatus
        runLive = $summaryRunLive
        dryRun = (-not $summaryRunLive)
        physicalQuestProductPathPending = $physicalPending
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary -and -not [string]::IsNullOrWhiteSpace($SummaryPath) -and (Test-Path -LiteralPath $SummaryPath))
            passiveTriggerProtocolPass = ([string](Get-JsonProperty -Object $statuses -Name 'passiveTriggerProtocol' -Default '') -eq 'pass')
            unityInputModalityPass = ([string](Get-JsonProperty -Object $statuses -Name 'unityInputModality' -Default '') -eq 'pass')
            twoDFirstFrontDoorPass = ([string](Get-JsonProperty -Object $statuses -Name 'twoDFirstFrontDoor' -Default '') -eq 'pass')
            questionnaireApkPresent = ([string](Get-JsonProperty -Object $statuses -Name 'questionnaireApkGenerated' -Default '') -eq 'present')
            unityApkPresent = ([string](Get-JsonProperty -Object $statuses -Name 'unityApk' -Default '') -eq 'present')
            noFailedSteps = ($failedStepCount -eq 0)
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            outputRoot = Get-JsonProperty -Object $Summary -Name 'outputRoot' -Default ''
            passiveTriggerProtocolSummary = Get-JsonProperty -Object (Get-JsonProperty -Object $Summary -Name 'evidence') -Name 'passiveTriggerProtocolSummary' -Default ''
            unityInputModalitySummary = Get-JsonProperty -Object (Get-JsonProperty -Object $Summary -Name 'evidence') -Name 'unityInputModalitySummary' -Default ''
            twoDFirstFrontDoorSummary = Get-JsonProperty -Object (Get-JsonProperty -Object $Summary -Name 'evidence') -Name 'twoDFirstFrontDoorSummary' -Default ''
            questionnaireApk = Get-JsonProperty -Object (Get-JsonProperty -Object $Summary -Name 'inputs') -Name 'questionnaireApk' -Default ''
            unityApk = Get-JsonProperty -Object (Get-JsonProperty -Object $Summary -Name 'inputs') -Name 'unityApk' -Default ''
        }
        statuses = $statuses
        remainingLiveGates = $remainingLiveGates
        proofBoundary = if ($summaryRunLive) {
            'Live minimal protocol gate was attempted. Manual Unity trigger observation and export audit remain pending unless the linked evidence explicitly proves them.'
        } else {
            'Dry-run software preflight only. It does not install, launch, wake, foreground-switch, observe Unity trigger input, or pull Quest exports.'
        }
    }
}

function New-DirectHandoffManualSignoffReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [int]$ExitCode
    )

    $evidence = Get-JsonProperty -Object $Summary -Name 'evidence'
    $operator = Get-JsonProperty -Object $Summary -Name 'operator'
    $directHandoff = Get-JsonProperty -Object $Summary -Name 'directHandoff'
    $missing = @(Get-JsonProperty -Object $Summary -Name 'missing' -Default @())
    $issues = @(Get-JsonProperty -Object $Summary -Name 'issues' -Default @())
    $status = if ($Summary) { [string](Get-JsonProperty -Object $Summary -Name 'status' -Default 'unknown') } else { 'missing-summary' }
    $instructionsPath = [string](Get-JsonProperty -Object $evidence -Name 'instructionsPath' -Default '')
    $templatePath = [string](Get-JsonProperty -Object $evidence -Name 'operatorSignoffTemplatePath' -Default '')
    $operatorSignoffPath = [string](Get-JsonProperty -Object $evidence -Name 'operatorSignoffPath' -Default '')
    $directHandoffSummaryPath = [string](Get-JsonProperty -Object $evidence -Name 'directHandoffSummaryPath' -Default '')
    $template = Read-JsonFileIfExists -Path $templatePath
    $templateFields = if ($template) { @($template.PSObject.Properties.Name) } else { @() }
    $instructionsText = Read-TextFileIfExists -Path $instructionsPath
    $manualStopConditionChecks = [ordered]@{
        controllerRequiredDialogObservation = ($templateFields -contains 'observedNoControllerRequiredLaunchDialog')
        unityStartGateObservation = ($templateFields -contains 'observedUnityStartGate' -and $templateFields -contains 'clickedStartExperimentInUnity')
        videoResumeObservation = ($templateFields -contains 'observedVideoResumedAfterQuestionnaire')
        noMetaMenuObservation = ($templateFields -contains 'observedNoMetaMenuNavigation')
        noAdbForegroundObservation = ($templateFields -contains 'observedNoAdbForegroundSwitchAfterInitialLaunch')
        instructionsMentionControllerDialog = $instructionsText.Contains('LaunchCheckControllerRequiredDialogActivity')
        instructionsMentionStartGate = $instructionsText.Contains('Start experiment')
        instructionsMentionFrozenVideo = $instructionsText.Contains('Unity video stays frozen')
        instructionsMentionNoMetaMenu = $instructionsText.Contains('Meta menu navigation')
        instructionsMentionNoAdbForeground = $instructionsText.Contains('ADB foreground switching')
    }
    $manualStopConditionGuardrailsPresent = -not @($manualStopConditionChecks.GetEnumerator() | Where-Object { -not [bool]$_.Value })

    return [ordered]@{
        schemaVersion = 'mq.builder_manual_signoff.receipt.v1'
        kind = 'direct-handoff-manual-signoff'
        status = $status
        exitCode = $ExitCode
        physicalQuestProductPathPending = ($status -ne 'pass')
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary -and (Test-Path -LiteralPath $SummaryPath))
            instructionsWritten = (-not [string]::IsNullOrWhiteSpace($instructionsPath) -and (Test-Path -LiteralPath $instructionsPath))
            operatorTemplateWritten = (-not [string]::IsNullOrWhiteSpace($templatePath) -and (Test-Path -LiteralPath $templatePath))
            operatorSignoffProvided = (-not [string]::IsNullOrWhiteSpace($operatorSignoffPath) -and (Test-Path -LiteralPath $operatorSignoffPath))
            operatorNamePresent = -not [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $operator -Name 'operatorName' -Default ''))
            signedAtUtcPresent = -not [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $operator -Name 'signedAtUtc' -Default ''))
            directHandoffProductPathPass = [bool](Get-JsonProperty -Object $directHandoff -Name 'passesProductPathEvidence' -Default $false)
            requiredObservationsComplete = ($missing.Count -eq 0)
            noValidationIssues = ($issues.Count -eq 0)
            stopConditionGuardrailsPresent = $manualStopConditionGuardrailsPresent
        }
        counts = [ordered]@{
            missing = $missing.Count
            issues = $issues.Count
        }
        guardrails = [ordered]@{
            present = $manualStopConditionGuardrailsPresent
            checks = $manualStopConditionChecks
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            instructionsPath = $instructionsPath
            operatorSignoffTemplatePath = $templatePath
            operatorSignoffPath = $operatorSignoffPath
            directHandoffSummaryPath = $directHandoffSummaryPath
        }
        missing = $missing
        issues = $issues
        proofBoundary = 'This prepares or validates the structured manual headset signoff. A pending template is not a physical pass; production approval still requires a filled operator signoff tied to a real non-dry-run product-path summary.'
    }
}

function New-PhysicalGatePacketReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [int]$ExitCode
    )

    $status = if ($Summary) { [string](Get-JsonProperty -Object $Summary -Name 'status' -Default 'unknown') } else { 'missing-summary' }
    $counts = if ($Summary -and $Summary.PSObject.Properties.Name -contains 'counts') { $Summary.counts } else { [pscustomobject]@{} }
    $artifacts = Get-JsonProperty -Object $Summary -Name 'artifacts' -Default ([pscustomobject]@{})
    $audit = Get-JsonProperty -Object $Summary -Name 'audit' -Default ([pscustomobject]@{})
    $manualSignoff = Get-JsonProperty -Object $Summary -Name 'manualSignoff' -Default ([pscustomobject]@{})
    $remainingRequirements = @(Get-JsonProperty -Object $Summary -Name 'remainingRequirements' -Default @())
    $runbookPath = [string](Get-JsonProperty -Object $artifacts -Name 'runbookPath' -Default '')
    $auditSummaryPath = [string](Get-JsonProperty -Object $artifacts -Name 'auditSummaryPath' -Default ([string](Get-JsonProperty -Object $audit -Name 'summaryPath' -Default '')))
    $manualSummaryPath = [string](Get-JsonProperty -Object $artifacts -Name 'manualSignoffSummaryPath' -Default ([string](Get-JsonProperty -Object $manualSignoff -Name 'summaryPath' -Default '')))
    $templatePath = [string](Get-JsonProperty -Object $artifacts -Name 'operatorSignoffTemplatePath' -Default ([string](Get-JsonProperty -Object $manualSignoff -Name 'operatorSignoffTemplatePath' -Default '')))
    $operatorGuardrails = @(Get-JsonProperty -Object $Summary -Name 'operatorGuardrails' -Default @())
    $operatorGuardrailIds = @($operatorGuardrails | ForEach-Object { [string](Get-JsonProperty -Object $_ -Name 'id' -Default '') })
    $runbookText = Read-TextFileIfExists -Path $runbookPath
    $physicalPacketGuardrailChecks = [ordered]@{
        twoDFirstStartGate = ($operatorGuardrailIds -contains '2d-demographics-unity-start-video')
        noControllerRequiredDialog = ($operatorGuardrailIds -contains 'no-controller-required-dialog')
        noMenuOrAdbRecovery = ($operatorGuardrailIds -contains 'no-menu-or-adb-recovery')
        unityVideoResumesAfterPanel = ($operatorGuardrailIds -contains 'unity-video-resumes-after-panel')
        runbookMentionsControllerDialog = $runbookText.Contains('LaunchCheckControllerRequiredDialogActivity')
        runbookMentionsFrozenVideo = $runbookText.Contains('Unity video remains frozen')
        runbookMentionsMetaMenu = $runbookText.Contains('Meta menu navigation')
    }
    $physicalPacketGuardrailsPresent = -not @($physicalPacketGuardrailChecks.GetEnumerator() | Where-Object { -not [bool]$_.Value })

    return [ordered]@{
        schemaVersion = 'mq.builder_physical_gate_packet.receipt.v1'
        kind = 'universal-handoff-physical-gate-packet'
        status = $status
        exitCode = $ExitCode
        completionApproved = if ($Summary -and $Summary.PSObject.Properties.Name -contains 'completionApproved') { [bool]$Summary.completionApproved } else { $false }
        defaultDirectPendingIntentApproved = if ($Summary -and $Summary.PSObject.Properties.Name -contains 'defaultDirectPendingIntentApproved') { [bool]$Summary.defaultDirectPendingIntentApproved } else { $false }
        physicalQuestProductPathPending = if ($Summary -and $Summary.PSObject.Properties.Name -contains 'physicalQuestProductPathPending') { [bool]$Summary.physicalQuestProductPathPending } else { $true }
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary -and (Test-FileExists -Path $SummaryPath))
            runbookWritten = (Test-FileExists -Path $runbookPath)
            auditSummaryPresent = (Test-FileExists -Path $auditSummaryPath)
            manualSignoffTemplateWritten = (Test-FileExists -Path $templatePath)
            manualSignoffSummaryPresent = (Test-FileExists -Path $manualSummaryPath)
            operatorGuardrailsPresent = $physicalPacketGuardrailsPresent
        }
        counts = $counts
        remainingGateCount = $remainingRequirements.Count
        guardrails = [ordered]@{
            present = $physicalPacketGuardrailsPresent
            ids = $operatorGuardrailIds
            checks = $physicalPacketGuardrailChecks
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            runbookPath = $runbookPath
            auditSummaryPath = $auditSummaryPath
            manualSignoffSummaryPath = $manualSummaryPath
            manualSignoffInstructionsPath = [string](Get-JsonProperty -Object $artifacts -Name 'manualSignoffInstructionsPath' -Default '')
            operatorSignoffTemplatePath = $templatePath
        }
        proofBoundary = 'This packet prepares the remaining physical headset gates for an operator. It is not a product-path pass and does not replace live Quest trials or filled manual signoff.'
    }
}

function New-TwoApkLiveValidationPacketReceipt {
    param(
        [object]$Summary,
        [string]$SummaryPath,
        [int]$ExitCode
    )

    $status = if ($Summary) { [string](Get-JsonProperty -Object $Summary -Name 'status' -Default 'unknown') } else { 'missing-summary' }
    $productContract = Get-JsonProperty -Object $Summary -Name 'productContract' -Default ([pscustomobject]@{})
    $inputs = Get-JsonProperty -Object $Summary -Name 'inputs' -Default ([pscustomobject]@{})
    $evidence = Get-JsonProperty -Object $Summary -Name 'evidence' -Default ([pscustomobject]@{})
    $statuses = Get-JsonProperty -Object $Summary -Name 'statuses' -Default ([pscustomobject]@{})
    $operatorSignoffValidation = Get-JsonProperty -Object $Summary -Name 'operatorSignoffValidation' -Default ([pscustomobject]@{})
    $remainingLiveGates = @(Get-JsonProperty -Object $Summary -Name 'remainingLiveGates' -Default @())
    $proofBoundary = [string](Get-JsonProperty -Object $Summary -Name 'proofBoundary' -Default '')
    $questionnaireApk = Get-JsonProperty -Object $inputs -Name 'questionnaireApk' -Default ([pscustomobject]@{})
    $unityApk = Get-JsonProperty -Object $inputs -Name 'unityApk' -Default ([pscustomobject]@{})
    $pairSummaryPath = [string](Get-JsonProperty -Object $evidence -Name 'twoApkPairSummary' -Default '')
    $dryRunSummaryPath = [string](Get-JsonProperty -Object $evidence -Name 'dryRunPreflightSummary' -Default '')
    $runbookPath = [string](Get-JsonProperty -Object $evidence -Name 'operatorRunbook' -Default '')
    $templatePath = [string](Get-JsonProperty -Object $evidence -Name 'operatorSignoffTemplate' -Default '')
    $operatorSignoffPath = [string](Get-JsonProperty -Object $evidence -Name 'operatorSignoffPath' -Default '')
    $runbookText = Read-TextFileIfExists -Path $runbookPath
    $template = Read-JsonFileIfExists -Path $templatePath
    $observedTemplate = Get-JsonProperty -Object $template -Name 'observed' -Default ([pscustomobject]@{})
    $observedFields = if ($observedTemplate -and $observedTemplate.PSObject.Properties) { @($observedTemplate.PSObject.Properties.Name) } else { @() }
    $twoApkGuardrailChecks = [ordered]@{
        questionnaireFrontDoorContract = ([string](Get-JsonProperty -Object $productContract -Name 'participantFrontDoor' -Default '') -eq 'generated 2D questionnaire APK')
        unityPassiveRoleContract = ([string](Get-JsonProperty -Object $productContract -Name 'unityRole' -Default '') -match 'passive trigger')
        questionnaireLogicOwnerContract = ([string](Get-JsonProperty -Object $productContract -Name 'questionnaireRole' -Default '') -match 'study logic owner')
        noHeadsetSideEffectsBoundary = $proofBoundary.Contains('does not install, launch, wake, or change the Quest')
        runbookQuestionnaireFirst = $runbookText.Contains('participant starts the generated 2D questionnaire APK')
        runbookDoNotLaunchUnityFirst = $runbookText.Contains('Do not launch Unity from Meta Home')
        runbookNoAdbOrMenuRepair = $runbookText.Contains('Do not use ADB')
        runbookUnityPassiveTriggersOnly = $runbookText.Contains('Unity emits passive trigger IDs only')
        runbookQuestionnaireResumesMappedBlock = $runbookText.Contains('questionnaire APK resumes the mapped block')
        signoffHasQuestionnaireFirstObservation = ($observedFields -contains 'startedGeneratedQuestionnaireFromMetaHome')
        signoffHasUnityNotStartedObservation = ($observedFields -contains 'didNotStartUnityFromMetaHome')
        signoffHasImmersiveUnityObservation = ($observedFields -contains 'unityDisplayedAsImmersiveForegroundApp')
        signoffHasPassiveUnityObservation = ($observedFields -contains 'noUnitySideQuestionnaireDecisionObserved')
    }
    $twoApkGuardrailsPresent = -not @($twoApkGuardrailChecks.GetEnumerator() | Where-Object { -not [bool]$_.Value })

    return [ordered]@{
        schemaVersion = 'mq.builder_two_apk_live_validation_packet.receipt.v1'
        kind = 'two-apk-live-validation-packet'
        status = $status
        exitCode = $ExitCode
        physicalQuestProductPathPending = ($status -ne 'operator-signoff-pass')
        checks = [ordered]@{
            summaryWritten = ($null -ne $Summary -and (Test-FileExists -Path $SummaryPath))
            twoApkPairAuditPass = ([string](Get-JsonProperty -Object $statuses -Name 'twoApkPairAudit' -Default '') -eq 'pass')
            dryRunPreflightPassOrSkipped = ([string](Get-JsonProperty -Object $statuses -Name 'dryRunPreflight' -Default '') -in @('pass', 'skipped'))
            operatorRunbookWritten = (Test-FileExists -Path $runbookPath)
            operatorSignoffTemplateWritten = (Test-FileExists -Path $templatePath)
            operatorSignoffProvided = (Test-FileExists -Path $operatorSignoffPath)
            questionnaireApkExists = [bool](Get-JsonProperty -Object $questionnaireApk -Name 'exists' -Default $false)
            unityApkExists = [bool](Get-JsonProperty -Object $unityApk -Name 'exists' -Default $false)
            operatorGuardrailsPresent = $twoApkGuardrailsPresent
            operatorSignoffPass = [bool](Get-JsonProperty -Object $operatorSignoffValidation -Name 'pass' -Default $false)
        }
        statuses = [ordered]@{
            twoApkPairAudit = [string](Get-JsonProperty -Object $statuses -Name 'twoApkPairAudit' -Default '')
            dryRunPreflight = [string](Get-JsonProperty -Object $statuses -Name 'dryRunPreflight' -Default '')
            operatorSignoff = [string](Get-JsonProperty -Object $statuses -Name 'operatorSignoff' -Default '')
        }
        remainingLiveGateCount = $remainingLiveGates.Count
        guardrails = [ordered]@{
            present = $twoApkGuardrailsPresent
            checks = $twoApkGuardrailChecks
        }
        artifacts = [ordered]@{
            summaryPath = $SummaryPath
            pairSummaryPath = $pairSummaryPath
            dryRunPreflightSummaryPath = $dryRunSummaryPath
            runbookPath = $runbookPath
            operatorSignoffTemplatePath = $templatePath
            operatorSignoffPath = $operatorSignoffPath
            questionnaireApkPath = [string](Get-JsonProperty -Object $questionnaireApk -Name 'path' -Default '')
            unityApkPath = [string](Get-JsonProperty -Object $unityApk -Name 'path' -Default '')
        }
        contract = [ordered]@{
            participantFrontDoor = [string](Get-JsonProperty -Object $productContract -Name 'participantFrontDoor' -Default '')
            unityRole = [string](Get-JsonProperty -Object $productContract -Name 'unityRole' -Default '')
            questionnaireRole = [string](Get-JsonProperty -Object $productContract -Name 'questionnaireRole' -Default '')
            lslRole = [string](Get-JsonProperty -Object $productContract -Name 'lslRole' -Default '')
        }
        remainingLiveGates = $remainingLiveGates
        proofBoundary = $proofBoundary
    }
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
    if ($Payload.PSObject.Properties.Name -contains 'dryRunQuestDirectHandoff' -and [bool]$Payload.dryRunQuestDirectHandoff) {
        $arguments += '-DryRunQuestDirectHandoff'
    }
    if ($Payload.PSObject.Properties.Name -contains 'skipInstall' -and [bool]$Payload.skipInstall) {
        $arguments += '-SkipInstall'
    }
    if ($Payload.PSObject.Properties.Name -contains 'questSerial' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questSerial)) {
        $arguments += @('-Serial', [string]$Payload.questSerial)
    }
    if ($Payload.PSObject.Properties.Name -contains 'questTrials' -and [int]$Payload.questTrials -gt 0) {
        $questTrials = [Math]::Min(10, [Math]::Max(1, [int]$Payload.questTrials))
        $arguments += @('-QuestTrials', [string]$questTrials)
    }
    if ($Payload.PSObject.Properties.Name -contains 'waitForReadySeconds' -and [int]$Payload.waitForReadySeconds -ge 0) {
        $waitForReadySeconds = [Math]::Min(28800, [Math]::Max(0, [int]$Payload.waitForReadySeconds))
        $arguments += @('-WaitForReadySeconds', [string]$waitForReadySeconds)
    }
    $dryRunDirectHandoff = ($Payload.PSObject.Properties.Name -contains 'dryRunQuestDirectHandoff' -and [bool]$Payload.dryRunQuestDirectHandoff)
    if (-not $dryRunDirectHandoff -and $Payload.PSObject.Properties.Name -contains 'wakeBeforeReadiness' -and [bool]$Payload.wakeBeforeReadiness) {
        $arguments += '-WakeBeforeReadiness'
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
    $workflowReceipt = New-WorkflowReceipt -Summary $summary -SummaryPath ([string]$job['summaryPath']) -JobStatus $jobStatus -WorkflowStatus $workflowStatus

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        workflowStatus = $workflowStatus
        exitCode = $exitCode
        processError = $processError
        configPath = $job['configPath']
        runQuestDirectHandoff = [bool]$job['runQuestDirectHandoff']
        dryRunQuestDirectHandoff = [bool]$job['dryRunQuestDirectHandoff']
        questTrials = [int]$job['questTrials']
        waitForReadySeconds = [int]$job['waitForReadySeconds']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        workflowReceipt = $workflowReceipt
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
    $runQuestDirectHandoff = ($Payload.PSObject.Properties.Name -contains 'runQuestDirectHandoff' -and [bool]$Payload.runQuestDirectHandoff)
    $dryRunQuestDirectHandoff = ($Payload.PSObject.Properties.Name -contains 'dryRunQuestDirectHandoff' -and [bool]$Payload.dryRunQuestDirectHandoff)
    $questTrials = if ($Payload.PSObject.Properties.Name -contains 'questTrials' -and [int]$Payload.questTrials -gt 0) { [Math]::Min(10, [Math]::Max(1, [int]$Payload.questTrials)) } else { 10 }
    $waitForReadySeconds = if ($Payload.PSObject.Properties.Name -contains 'waitForReadySeconds' -and [int]$Payload.waitForReadySeconds -ge 0) { [Math]::Min(28800, [Math]::Max(0, [int]$Payload.waitForReadySeconds)) } else { 30 }
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
        runQuestDirectHandoff = [bool]$runQuestDirectHandoff
        dryRunQuestDirectHandoff = [bool]$dryRunQuestDirectHandoff
        questTrials = [int]$questTrials
        waitForReadySeconds = [int]$waitForReadySeconds
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
        productPathStatus = if ($summary -and $summary.PSObject.Properties.Name -contains 'productPathStatus') { $summary.productPathStatus } else { 'not-probed' }
        productPathReady = if ($summary -and $summary.PSObject.Properties.Name -contains 'productPathReady') { [bool]$summary.productPathReady } else { $false }
        productPath = if ($summary -and $summary.PSObject.Properties.Name -contains 'productPath') { $summary.productPath } else { $null }
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
    $jobReceipt = New-InstallJobReceipt -Summary $summary -SummaryPath ([string]$job['summaryPath']) -JobStatus $jobStatus -InstallStatus $installStatus -DryRun ([bool]$job['dryRun'])

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
        jobReceipt = $jobReceipt
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
    $jobReceipt = New-QuestReplayJobReceipt -Summary $summary -SummaryPath ([string]$job['summaryPath']) -JobStatus $jobStatus -ReplayStatus $replayStatus -DryRun ([bool]$job['dryRun'])

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        replayStatus = $replayStatus
        productPathStatus = if ($summary -and $summary.PSObject.Properties.Name -contains 'productPathStatus') { $summary.productPathStatus } else { '' }
        productPathBlockedReasons = if ($summary -and $summary.PSObject.Properties.Name -contains 'productPathBlockedReasons') { @($summary.productPathBlockedReasons) } else { @() }
        exitCode = $exitCode
        processError = $processError
        apk = $job['apk']
        questSerial = $job['questSerial']
        dryRun = [bool]$job['dryRun']
        wakeBeforeReadinessRequested = [bool]$job['wakeBeforeReadinessRequested']
        wakeBeforeReadiness = [bool]$job['wakeBeforeReadiness']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        jobReceipt = $jobReceipt
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
    $wakeBeforeReadinessRequested = ($Payload.PSObject.Properties.Name -contains 'wakeBeforeReadiness' -and [bool]$Payload.wakeBeforeReadiness)
    $wakeBeforeReadiness = (-not $dryRun -and $wakeBeforeReadinessRequested)

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
    if ($wakeBeforeReadinessRequested) {
        $arguments += '-WakeBeforeReadiness'
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
        wakeBeforeReadinessRequested = [bool]$wakeBeforeReadinessRequested
        wakeBeforeReadiness = [bool]$wakeBeforeReadiness
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

function Get-DirectHandoffJobStatus {
    param([string]$RunId)

    if ([string]::IsNullOrWhiteSpace($RunId) -or -not $script:DirectHandoffJobs.ContainsKey($RunId)) {
        return $null
    }

    $job = $script:DirectHandoffJobs[$RunId]
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
    $handoffStatus = 'running'
    if ($hasExited) {
        $jobStatus = if ($null -ne $exitCode -and $exitCode -eq 0) { 'completed' } else { 'failed' }
        if ($summary) {
            $handoffStatus = [string]$summary.status
        }
        elseif ($jobStatus -eq 'completed') {
            $handoffStatus = 'missing-summary'
        }
        else {
            $handoffStatus = 'error'
        }
    }
    elseif ($summary -and $summary.PSObject.Properties.Name -contains 'status') {
        $handoffStatus = [string]$summary.status
    }
    $jobReceipt = New-DirectHandoffJobReceipt -Summary $summary -SummaryPath ([string]$job['summaryPath']) -JobStatus $jobStatus -HandoffStatus $handoffStatus -DryRun ([bool]$job['dryRun'])

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        handoffStatus = $handoffStatus
        passCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'passCount') { $summary.passCount } else { $null }
        warnCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'warnCount') { $summary.warnCount } else { $null }
        blockedCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'blockedCount') { $summary.blockedCount } else { $null }
        failCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'failCount') { $summary.failCount } else { $null }
        decisionGate = if ($summary -and $summary.PSObject.Properties.Name -contains 'decisionGate') { $summary.decisionGate } else { $null }
        exitCode = $exitCode
        processError = $processError
        questionnaireApk = $job['questionnaireApk']
        temporalTracerApk = $job['temporalTracerApk']
        unityApk = $job['unityApk']
        questSerial = $job['questSerial']
        dryRun = [bool]$job['dryRun']
        trialCount = [int]$job['trialCount']
        waitForReadySeconds = [int]$job['waitForReadySeconds']
        wakeBeforeReadiness = [bool]$job['wakeBeforeReadiness']
        waitSeconds = [int]$job['waitSeconds']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        jobReceipt = $jobReceipt
        summary = $summary
        startedAt = $job['startedAt']
        completedAt = $job['completedAt']
    }
}

function Start-DirectHandoffJob {
    param([object]$Payload)

    $runId = 'builder-direct-handoff-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $jobDir = Join-Path $ProjectPath ("artifacts\builder-app-direct-handoff\$runId")
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

    $questionnaireApk = if ($Payload.PSObject.Properties.Name -contains 'questionnaireApk') { [string]$Payload.questionnaireApk } elseif ($Payload.PSObject.Properties.Name -contains 'apk') { [string]$Payload.apk } else { '' }
    $temporalTracerApk = if ($Payload.PSObject.Properties.Name -contains 'temporalTracerApk') { [string]$Payload.temporalTracerApk } else { '' }
    $unityApk = if ($Payload.PSObject.Properties.Name -contains 'unityApk') { [string]$Payload.unityApk } else { '' }
    $serial = if ($Payload.PSObject.Properties.Name -contains 'questSerial') { [string]$Payload.questSerial } else { '' }
    $dryRun = ($Payload.PSObject.Properties.Name -contains 'dryRun' -and [bool]$Payload.dryRun)
    $skipInstall = ($Payload.PSObject.Properties.Name -contains 'skipInstall' -and [bool]$Payload.skipInstall)
    $trialCount = if ($Payload.PSObject.Properties.Name -contains 'trialCount') { [Math]::Min(10, [Math]::Max(1, [int]$Payload.trialCount)) } else { 10 }
    $waitForReadySeconds = if ($Payload.PSObject.Properties.Name -contains 'waitForReadySeconds') { [Math]::Min(28800, [Math]::Max(0, [int]$Payload.waitForReadySeconds)) } else { 30 }
    $waitSeconds = if ($Payload.PSObject.Properties.Name -contains 'waitSeconds') { [Math]::Max(1, [int]$Payload.waitSeconds) } else { 95 }
    $wakeBeforeReadiness = (-not $dryRun -and $Payload.PSObject.Properties.Name -contains 'wakeBeforeReadiness' -and [bool]$Payload.wakeBeforeReadiness)

    $stdoutPath = Join-Path $jobDir 'direct-handoff-stdout.txt'
    $stderrPath = Join-Path $jobDir 'direct-handoff-stderr.txt'
    $summaryPath = Join-Path $jobDir 'quest-direct-handoff-validation-summary.json'
    $script = Join-Path $ProjectPath 'tools\quest-direct-handoff-validate.ps1'
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
        '-TrialCount',
        [string]$trialCount,
        '-WaitForReadySeconds',
        [string]$waitForReadySeconds,
        '-WaitSeconds',
        [string]$waitSeconds,
        '-FastVideoForValidation',
        '-AutoTraceForValidation'
    )
    if (-not [string]::IsNullOrWhiteSpace($questionnaireApk)) {
        $arguments += @('-QuestionnaireApk', $questionnaireApk)
    }
    if (-not [string]::IsNullOrWhiteSpace($temporalTracerApk)) {
        $arguments += @('-TemporalTracerApk', $temporalTracerApk)
    }
    if (-not [string]::IsNullOrWhiteSpace($unityApk)) {
        $arguments += @('-UnityApk', $unityApk)
    }
    if (-not [string]::IsNullOrWhiteSpace($serial)) {
        $arguments += @('-Serial', $serial)
    }
    if ($dryRun) {
        $arguments += '-DryRun'
    }
    if ($skipInstall) {
        $arguments += '-SkipInstall'
    }
    if ($wakeBeforeReadiness) {
        $arguments += '-WakeBeforeReadiness'
    }

    $process = Start-Process `
        -FilePath 'powershell' `
        -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $script:DirectHandoffJobs[$runId] = [ordered]@{
        process = $process
        runId = $runId
        questionnaireApk = $questionnaireApk
        temporalTracerApk = $temporalTracerApk
        unityApk = $unityApk
        questSerial = $serial
        dryRun = [bool]$dryRun
        trialCount = [int]$trialCount
        waitForReadySeconds = [int]$waitForReadySeconds
        wakeBeforeReadiness = [bool]$wakeBeforeReadiness
        waitSeconds = [int]$waitSeconds
        artifactDir = $jobDir
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        summaryPath = $summaryPath
        startedAt = (Get-Date).ToString('o')
        completedAt = ''
    }
    $script:DirectHandoffJobOrder.Add($runId) | Out-Null

    while ($script:DirectHandoffJobOrder.Count -gt 20) {
        $oldest = $script:DirectHandoffJobOrder[0]
        $script:DirectHandoffJobOrder.RemoveAt(0)
        if ($script:DirectHandoffJobs.ContainsKey($oldest)) {
            $oldJob = $script:DirectHandoffJobs[$oldest]
            $oldProcess = $oldJob['process']
            if ($oldProcess -and $oldProcess.HasExited) {
                $script:DirectHandoffJobs.Remove($oldest)
            }
        }
    }

    return Get-DirectHandoffJobStatus -RunId $runId
}

function Get-TwoDFirstLauncherJobStatus {
    param([string]$RunId)

    if ([string]::IsNullOrWhiteSpace($RunId) -or -not $script:TwoDFirstLauncherJobs.ContainsKey($RunId)) {
        return $null
    }

    $job = $script:TwoDFirstLauncherJobs[$RunId]
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
    $launcherStatus = 'running'
    if ($hasExited) {
        $jobStatus = if ($null -ne $exitCode -and $exitCode -eq 0) { 'completed' } else { 'failed' }
        if ($summary) {
            $launcherStatus = [string]$summary.status
        }
        elseif ($jobStatus -eq 'completed') {
            $launcherStatus = 'missing-summary'
        }
        else {
            $launcherStatus = 'error'
        }
    }
    elseif ($summary -and $summary.PSObject.Properties.Name -contains 'status') {
        $launcherStatus = [string]$summary.status
    }
    $jobReceipt = New-TwoDFirstLauncherJobReceipt -Summary $summary -SummaryPath ([string]$job['summaryPath']) -JobStatus $jobStatus -LauncherStatus $launcherStatus -DryRun ([bool]$job['dryRun'])

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        launcherStatus = $launcherStatus
        passCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'passCount') { $summary.passCount } else { $null }
        warnCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'warnCount') { $summary.warnCount } else { $null }
        blockedCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'blockedCount') { $summary.blockedCount } else { $null }
        failCount = if ($summary -and $summary.PSObject.Properties.Name -contains 'failCount') { $summary.failCount } else { $null }
        decisionGate = if ($summary -and $summary.PSObject.Properties.Name -contains 'decisionGate') { $summary.decisionGate } else { $null }
        exitCode = $exitCode
        processError = $processError
        questionnaireApk = $job['questionnaireApk']
        unityApk = $job['unityApk']
        questSerial = $job['questSerial']
        dryRun = [bool]$job['dryRun']
        skipInstall = [bool]$job['skipInstall']
        trialCount = [int]$job['trialCount']
        waitForReadySeconds = [int]$job['waitForReadySeconds']
        wakeBeforeReadiness = [bool]$job['wakeBeforeReadiness']
        waitSeconds = [int]$job['waitSeconds']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        jobReceipt = $jobReceipt
        summary = $summary
        startedAt = $job['startedAt']
        completedAt = $job['completedAt']
    }
}

function Start-TwoDFirstLauncherJob {
    param([object]$Payload)

    $runId = 'builder-2d-first-launcher-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $jobDir = Join-Path $ProjectPath ("artifacts\builder-app-2d-first-launcher\$runId")
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

    $questionnaireApk = if ($Payload.PSObject.Properties.Name -contains 'questionnaireApk') { [string]$Payload.questionnaireApk } elseif ($Payload.PSObject.Properties.Name -contains 'apk') { [string]$Payload.apk } else { '' }
    $unityApk = if ($Payload.PSObject.Properties.Name -contains 'unityApk') { [string]$Payload.unityApk } else { '' }
    $serial = if ($Payload.PSObject.Properties.Name -contains 'questSerial') { [string]$Payload.questSerial } else { '' }
    $dryRun = ($Payload.PSObject.Properties.Name -contains 'dryRun' -and [bool]$Payload.dryRun)
    $skipInstall = ($Payload.PSObject.Properties.Name -contains 'skipInstall' -and [bool]$Payload.skipInstall)
    $trialCount = if ($Payload.PSObject.Properties.Name -contains 'trialCount') { [Math]::Min(10, [Math]::Max(1, [int]$Payload.trialCount)) } else { 1 }
    $waitForReadySeconds = if ($Payload.PSObject.Properties.Name -contains 'waitForReadySeconds') { [Math]::Min(28800, [Math]::Max(0, [int]$Payload.waitForReadySeconds)) } else { 30 }
    $waitSeconds = if ($Payload.PSObject.Properties.Name -contains 'waitSeconds') { [Math]::Max(1, [int]$Payload.waitSeconds) } else { 45 }
    $wakeBeforeReadiness = (-not $dryRun -and $Payload.PSObject.Properties.Name -contains 'wakeBeforeReadiness' -and [bool]$Payload.wakeBeforeReadiness)

    $stdoutPath = Join-Path $jobDir '2d-first-launcher-stdout.txt'
    $stderrPath = Join-Path $jobDir '2d-first-launcher-stderr.txt'
    $summaryPath = Join-Path $jobDir 'quest-2d-first-launcher-validation-summary.json'
    $script = Join-Path $ProjectPath 'tools\quest-2d-first-launcher-validate.ps1'
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
        '-TrialCount',
        [string]$trialCount,
        '-WaitForReadySeconds',
        [string]$waitForReadySeconds,
        '-WaitSeconds',
        [string]$waitSeconds
    )
    if (-not [string]::IsNullOrWhiteSpace($questionnaireApk)) {
        $arguments += @('-QuestionnaireApk', $questionnaireApk)
    }
    if (-not [string]::IsNullOrWhiteSpace($unityApk)) {
        $arguments += @('-UnityApk', $unityApk)
    }
    if (-not [string]::IsNullOrWhiteSpace($serial)) {
        $arguments += @('-Serial', $serial)
    }
    if ($dryRun) {
        $arguments += '-DryRun'
    }
    if ($skipInstall) {
        $arguments += '-SkipInstall'
    }
    if ($wakeBeforeReadiness) {
        $arguments += '-WakeBeforeReadiness'
    }

    $process = Start-Process `
        -FilePath 'powershell' `
        -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $script:TwoDFirstLauncherJobs[$runId] = [ordered]@{
        process = $process
        runId = $runId
        questionnaireApk = $questionnaireApk
        unityApk = $unityApk
        questSerial = $serial
        dryRun = [bool]$dryRun
        skipInstall = [bool]$skipInstall
        trialCount = [int]$trialCount
        waitForReadySeconds = [int]$waitForReadySeconds
        wakeBeforeReadiness = [bool]$wakeBeforeReadiness
        waitSeconds = [int]$waitSeconds
        artifactDir = $jobDir
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        summaryPath = $summaryPath
        startedAt = (Get-Date).ToString('o')
        completedAt = ''
    }
    $script:TwoDFirstLauncherJobOrder.Add($runId) | Out-Null

    while ($script:TwoDFirstLauncherJobOrder.Count -gt 20) {
        $oldest = $script:TwoDFirstLauncherJobOrder[0]
        $script:TwoDFirstLauncherJobOrder.RemoveAt(0)
        if ($script:TwoDFirstLauncherJobs.ContainsKey($oldest)) {
            $oldJob = $script:TwoDFirstLauncherJobs[$oldest]
            $oldProcess = $oldJob['process']
            if ($oldProcess -and $oldProcess.HasExited) {
                $script:TwoDFirstLauncherJobs.Remove($oldest)
            }
        }
    }

    return Get-TwoDFirstLauncherJobStatus -RunId $runId
}

function Get-MinimalProtocolJobStatus {
    param([string]$RunId)

    if ([string]::IsNullOrWhiteSpace($RunId) -or -not $script:MinimalProtocolJobs.ContainsKey($RunId)) {
        return $null
    }
    $job = $script:MinimalProtocolJobs[$RunId]
    $process = $job['process']
    $summary = Read-JsonFileIfExists -Path ([string]$job['summaryPath'])
    $summaryStatus = if ($summary) { [string](Get-JsonProperty -Object $summary -Name 'status' -Default '') } else { '' }
    $jobStatus = 'running'
    $exitCode = $null
    $processError = ''
    if ($process -and $process.HasExited) {
        $exitCode = $process.ExitCode
        $jobStatus = if ($summaryStatus -eq 'pass' -or $exitCode -eq 0) { 'completed' } else { 'failed' }
        $job['completedAt'] = if ([string]::IsNullOrWhiteSpace([string]$job['completedAt'])) { (Get-Date).ToString('o') } else { $job['completedAt'] }
    }
    elseif (-not $process) {
        $jobStatus = 'failed'
        $processError = 'Process did not start.'
    }

    $protocolStatus = if ($summary) { $summaryStatus } elseif ($jobStatus -eq 'running') { 'running' } else { 'missing-summary' }
    $jobReceipt = New-MinimalProtocolJobReceipt -Summary $summary -SummaryPath ([string]$job['summaryPath']) -JobStatus $jobStatus -ProtocolStatus $protocolStatus -RunLive ([bool]$job['runLive'])

    return [ordered]@{
        status = 'ok'
        jobId = $RunId
        runId = $RunId
        jobStatus = $jobStatus
        protocolStatus = $protocolStatus
        exitCode = $exitCode
        processError = $processError
        runLive = [bool]$job['runLive']
        dryRun = (-not [bool]$job['runLive'])
        skipQuestionnaireBuild = [bool]$job['skipQuestionnaireBuild']
        runGradleTests = [bool]$job['runGradleTests']
        runFullLocalProtocol = [bool]$job['runFullLocalProtocol']
        questSerial = $job['questSerial']
        questionnaireApk = $job['questionnaireApk']
        unityApk = $job['unityApk']
        artifactDir = $job['artifactDir']
        summaryPath = $job['summaryPath']
        stdoutPath = $job['stdoutPath']
        stderrPath = $job['stderrPath']
        stdout = Get-TailText -Path ([string]$job['stdoutPath'])
        stderr = Get-TailText -Path ([string]$job['stderrPath'])
        jobReceipt = $jobReceipt
        summary = $summary
        startedAt = $job['startedAt']
        completedAt = $job['completedAt']
    }
}

function Start-MinimalProtocolJob {
    param([object]$Payload)

    $runId = 'builder-minimal-protocol-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $jobDir = Join-Path $ProjectPath ("artifacts\builder-minimal-apk-trigger-protocol\$runId")
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

    $questionnaireApk = if ($Payload.PSObject.Properties.Name -contains 'questionnaireApk') { [string]$Payload.questionnaireApk } elseif ($Payload.PSObject.Properties.Name -contains 'apk') { [string]$Payload.apk } else { '' }
    $unityApk = if ($Payload.PSObject.Properties.Name -contains 'unityApk') { [string]$Payload.unityApk } else { '' }
    $unityPackage = if ($Payload.PSObject.Properties.Name -contains 'unityPackage') { [string]$Payload.unityPackage } else { '' }
    $unityActivity = if ($Payload.PSObject.Properties.Name -contains 'unityActivity') { [string]$Payload.unityActivity } else { '' }
    $serial = if ($Payload.PSObject.Properties.Name -contains 'questSerial') { [string]$Payload.questSerial } else { '' }
    $runLive = ($Payload.PSObject.Properties.Name -contains 'runLive' -and [bool]$Payload.runLive)
    $skipQuestionnaireBuild = (-not ($Payload.PSObject.Properties.Name -contains 'skipQuestionnaireBuild')) -or [bool]$Payload.skipQuestionnaireBuild
    $skipInstall = ($Payload.PSObject.Properties.Name -contains 'skipInstall' -and [bool]$Payload.skipInstall)
    $noAutoReplay = ($Payload.PSObject.Properties.Name -contains 'noAutoReplay' -and [bool]$Payload.noAutoReplay)
    $runGradleTests = ($Payload.PSObject.Properties.Name -contains 'runGradleTests' -and [bool]$Payload.runGradleTests)
    $runFullLocalProtocol = ($Payload.PSObject.Properties.Name -contains 'runFullLocalProtocol' -and [bool]$Payload.runFullLocalProtocol)
    $trialCount = if ($Payload.PSObject.Properties.Name -contains 'trialCount') { [Math]::Min(10, [Math]::Max(1, [int]$Payload.trialCount)) } else { 1 }
    $waitForReadySeconds = if ($Payload.PSObject.Properties.Name -contains 'waitForReadySeconds') { [Math]::Min(28800, [Math]::Max(0, [int]$Payload.waitForReadySeconds)) } else { 30 }
    $readinessPollSeconds = if ($Payload.PSObject.Properties.Name -contains 'readinessPollSeconds') { [Math]::Min(60, [Math]::Max(1, [int]$Payload.readinessPollSeconds)) } else { 2 }
    $waitSeconds = if ($Payload.PSObject.Properties.Name -contains 'waitSeconds') { [Math]::Max(1, [int]$Payload.waitSeconds) } else { 45 }
    $wakeBeforeReadiness = ($runLive -and $Payload.PSObject.Properties.Name -contains 'wakeBeforeReadiness' -and [bool]$Payload.wakeBeforeReadiness)
    $allowLaunchWhenNotReady = ($runLive -and $Payload.PSObject.Properties.Name -contains 'allowLaunchWhenNotReady' -and [bool]$Payload.allowLaunchWhenNotReady)

    if ($runLive -and [string]::IsNullOrWhiteSpace($serial)) {
        throw "Live minimal protocol validation requires a Quest serial. Run dry-run preflight without runLive for software-only validation."
    }

    $stdoutPath = Join-Path $jobDir 'minimal-protocol-stdout.txt'
    $stderrPath = Join-Path $jobDir 'minimal-protocol-stderr.txt'
    $summaryPath = Join-Path $jobDir 'quest-minimal-apk-trigger-protocol-summary.json'
    $script = Join-Path $ProjectPath 'tools\quest-minimal-apk-trigger-protocol-validate.ps1'
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
        '-TrialCount',
        [string]$trialCount,
        '-WaitForReadySeconds',
        [string]$waitForReadySeconds,
        '-ReadinessPollSeconds',
        [string]$readinessPollSeconds,
        '-WaitSeconds',
        [string]$waitSeconds
    )
    if (-not [string]::IsNullOrWhiteSpace($questionnaireApk)) {
        $arguments += @('-QuestionnaireApk', $questionnaireApk)
    }
    if (-not [string]::IsNullOrWhiteSpace($unityApk)) {
        $arguments += @('-UnityApk', $unityApk)
    }
    if (-not [string]::IsNullOrWhiteSpace($unityPackage)) {
        $arguments += @('-UnityPackage', $unityPackage)
    }
    if (-not [string]::IsNullOrWhiteSpace($unityActivity)) {
        $arguments += @('-UnityActivity', $unityActivity)
    }
    if (-not [string]::IsNullOrWhiteSpace($serial)) {
        $arguments += @('-Serial', $serial)
    }
    if ($runLive) { $arguments += '-RunLive' }
    if ($skipQuestionnaireBuild) { $arguments += '-SkipQuestionnaireBuild' }
    if ($skipInstall) { $arguments += '-SkipInstall' }
    if ($noAutoReplay) { $arguments += '-NoAutoReplay' }
    if ($wakeBeforeReadiness) { $arguments += '-WakeBeforeReadiness' }
    if ($allowLaunchWhenNotReady) { $arguments += '-AllowLaunchWhenNotReady' }
    if ($runGradleTests) { $arguments += '-RunGradleTests' }
    if ($runFullLocalProtocol) { $arguments += '-RunFullLocalProtocol' }

    $process = Start-Process `
        -FilePath 'powershell' `
        -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $script:MinimalProtocolJobs[$runId] = [ordered]@{
        process = $process
        runId = $runId
        questionnaireApk = $questionnaireApk
        unityApk = $unityApk
        unityPackage = $unityPackage
        unityActivity = $unityActivity
        questSerial = $serial
        runLive = [bool]$runLive
        skipQuestionnaireBuild = [bool]$skipQuestionnaireBuild
        skipInstall = [bool]$skipInstall
        noAutoReplay = [bool]$noAutoReplay
        runGradleTests = [bool]$runGradleTests
        runFullLocalProtocol = [bool]$runFullLocalProtocol
        trialCount = [int]$trialCount
        waitForReadySeconds = [int]$waitForReadySeconds
        readinessPollSeconds = [int]$readinessPollSeconds
        waitSeconds = [int]$waitSeconds
        wakeBeforeReadiness = [bool]$wakeBeforeReadiness
        allowLaunchWhenNotReady = [bool]$allowLaunchWhenNotReady
        artifactDir = $jobDir
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        summaryPath = $summaryPath
        startedAt = (Get-Date).ToString('o')
        completedAt = ''
    }
    $script:MinimalProtocolJobOrder.Add($runId) | Out-Null

    while ($script:MinimalProtocolJobOrder.Count -gt 20) {
        $oldest = $script:MinimalProtocolJobOrder[0]
        $script:MinimalProtocolJobOrder.RemoveAt(0)
        if ($script:MinimalProtocolJobs.ContainsKey($oldest)) {
            $oldJob = $script:MinimalProtocolJobs[$oldest]
            $oldProcess = $oldJob['process']
            if ($oldProcess -and $oldProcess.HasExited) {
                $script:MinimalProtocolJobs.Remove($oldest)
            }
        }
    }

    return Get-MinimalProtocolJobStatus -RunId $runId
}

function Receive-JsonPayload {
    param([System.Net.HttpListenerRequest]$Request)

    $body = Get-RequestBody -Request $Request
    if ([string]::IsNullOrWhiteSpace($body)) {
        return [pscustomobject]@{}
    }
    return $body | ConvertFrom-Json
}

function Save-StagedScenarioApk {
    param([object]$Payload)

    $fileName = if ($Payload.PSObject.Properties.Name -contains 'fileName') { [string]$Payload.fileName } else { 'scenario.apk' }
    $base64 = if ($Payload.PSObject.Properties.Name -contains 'base64') { [string]$Payload.base64 } else { '' }
    if ([string]::IsNullOrWhiteSpace($base64)) {
        throw "Scenario APK upload is missing base64 content."
    }

    $safeName = Get-SafeName -Value ([System.IO.Path]::GetFileName($fileName))
    if (-not $safeName.EndsWith('.apk', [System.StringComparison]::OrdinalIgnoreCase)) {
        $safeName = "$safeName.apk"
    }

    $runId = 'builder-scenario-apk-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $targetDir = Join-Path $ProjectPath ("artifacts\builder-scenario-apks\$runId")
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    $targetPath = Join-Path $targetDir $safeName
    $bytes = [Convert]::FromBase64String($base64)
    [System.IO.File]::WriteAllBytes($targetPath, $bytes)

    $sha = ''
    try {
        $sha = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
    }
    catch {
        $sha = ''
    }

    $summaryPath = Join-Path $targetDir 'staged-scenario-apk-summary.json'
    $summary = [ordered]@{
        status = 'ok'
        schemaVersion = 'questquestionnaire.builder.staged-scenario-apk.v1'
        runId = $runId
        fileName = $safeName
        apk = $targetPath
        bytes = $bytes.Length
        sha256 = $sha
        stagedAt = (Get-Date).ToString('o')
    }
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    return [ordered]@{
        status = 'ok'
        runId = $runId
        fileName = $safeName
        apk = $targetPath
        bytes = $bytes.Length
        sha256 = $sha
        artifactDir = $targetDir
        summaryPath = $summaryPath
    }
}

function Save-StagedScenarioApkChunk {
    param([object]$Payload)

    $fileName = if ($Payload.PSObject.Properties.Name -contains 'fileName') { [string]$Payload.fileName } else { 'scenario.apk' }
    $base64 = if ($Payload.PSObject.Properties.Name -contains 'base64') { [string]$Payload.base64 } else { '' }
    $uploadId = if ($Payload.PSObject.Properties.Name -contains 'uploadId') { [string]$Payload.uploadId } else { '' }
    $chunkIndex = if ($Payload.PSObject.Properties.Name -contains 'chunkIndex') { [int]$Payload.chunkIndex } else { -1 }
    $chunkCount = if ($Payload.PSObject.Properties.Name -contains 'chunkCount') { [int]$Payload.chunkCount } else { 0 }
    $totalBytes = if ($Payload.PSObject.Properties.Name -contains 'totalBytes') { [long]$Payload.totalBytes } else { 0 }
    if ([string]::IsNullOrWhiteSpace($base64)) {
        throw "Scenario APK chunk upload is missing base64 content."
    }
    if ($chunkIndex -lt 0 -or $chunkCount -lt 1 -or $chunkIndex -ge $chunkCount) {
        throw "Scenario APK chunk index is invalid."
    }
    if ([string]::IsNullOrWhiteSpace($uploadId)) {
        $uploadId = 'builder-scenario-apk-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    }

    $safeName = Get-SafeName -Value ([System.IO.Path]::GetFileName($fileName))
    if (-not $safeName.EndsWith('.apk', [System.StringComparison]::OrdinalIgnoreCase)) {
        $safeName = "$safeName.apk"
    }

    $safeUploadId = Get-SafeName -Value $uploadId
    if (-not $safeUploadId.StartsWith('builder-scenario-apk-', [System.StringComparison]::OrdinalIgnoreCase)) {
        $safeUploadId = "builder-scenario-apk-$safeUploadId"
    }
    $targetDir = Join-Path $ProjectPath ("artifacts\builder-scenario-apks\$safeUploadId")
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    $targetPath = Join-Path $targetDir $safeName
    $bytes = [Convert]::FromBase64String($base64)
    $mode = if ($chunkIndex -eq 0) { [System.IO.FileMode]::Create } else { [System.IO.FileMode]::Append }
    $stream = [System.IO.File]::Open($targetPath, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $stream.Dispose()
    }

    $writtenBytes = (Get-Item -LiteralPath $targetPath).Length
    $complete = ($chunkIndex -eq ($chunkCount - 1))
    $sha = ''
    $summaryPath = Join-Path $targetDir 'staged-scenario-apk-summary.json'
    if ($complete) {
        if ($totalBytes -gt 0 -and $writtenBytes -ne $totalBytes) {
            throw "Scenario APK chunk upload completed with byte mismatch. Expected $totalBytes bytes, wrote $writtenBytes bytes."
        }
        try {
            $sha = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
        }
        catch {
            $sha = ''
        }

        $summary = [ordered]@{
            status = 'ok'
            schemaVersion = 'questquestionnaire.builder.staged-scenario-apk.v1'
            runId = $safeUploadId
            fileName = $safeName
            apk = $targetPath
            bytes = $writtenBytes
            sha256 = $sha
            chunkCount = $chunkCount
            stagedAt = (Get-Date).ToString('o')
        }
        $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    }

    return [ordered]@{
        status = 'ok'
        complete = $complete
        runId = $safeUploadId
        fileName = $safeName
        apk = $targetPath
        bytes = $writtenBytes
        sha256 = $sha
        chunkIndex = $chunkIndex
        chunkCount = $chunkCount
        artifactDir = $targetDir
        summaryPath = if ($complete) { $summaryPath } else { '' }
    }
}

function Resolve-RepoRelativeApkPath {
    param([string[]]$CandidatePaths)

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath '..'))
    $searchRoots = @($ProjectPath, $repoRoot) | Select-Object -Unique

    foreach ($candidate in $CandidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $relative = ([string]$candidate).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if ([System.IO.Path]::IsPathRooted($relative)) {
            throw "Repo example APK path must be relative to the repository root."
        }
        foreach ($root in $searchRoots) {
            $rootFull = [System.IO.Path]::GetFullPath($root)
            $rootPrefix = $rootFull
            if (-not $rootPrefix.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $rootPrefix += [System.IO.Path]::DirectorySeparatorChar
            }
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relative))
            if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Repo example APK path is outside the allowed local program roots."
            }
            if (-not $fullPath.EndsWith('.apk', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Repo example path is not an APK: $candidate"
            }
            if (Test-Path -LiteralPath $fullPath) {
                return $fullPath
            }
        }
    }

    throw "No local repo example APK was found. Expected one of: $($CandidatePaths -join ', ')"
}

function Invoke-ExampleScenarioApkBuild {
    $buildScript = Join-Path $ProjectPath 'tools\build-example-scenario-apks.ps1'
    if (-not (Test-Path -LiteralPath $buildScript)) {
        return [ordered]@{
            attempted = $false
            exitCode = -1
            output = "Example APK build script was not found: $buildScript"
        }
    }

    $result = Invoke-ProjectPowerShell -Arguments @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $buildScript,
        '-ProjectPath',
        $ProjectPath
    )

    return [ordered]@{
        attempted = $true
        exitCode = $result.exitCode
        output = $result.output
    }
}

function Get-ApkTriggerCatalogEntryRank {
    param([string]$Name)

    $normalized = ([string]$Name).Replace('\', '/').TrimStart('/').ToLowerInvariant()
    $preferred = @(
        'assets/mq/questionnaire-trigger-catalog.json',
        'assets/bin/data/streamingassets/mq/questionnaire-trigger-catalog.json',
        'assets/bin/data/streamingassets/questionnaire-trigger-catalog.json'
    )
    $exactIndex = [Array]::IndexOf($preferred, $normalized)
    if ($exactIndex -ge 0) {
        return $exactIndex
    }
    if ($normalized.EndsWith('/assets/streamingassets/mq/questionnaire-trigger-catalog.json')) {
        return 100
    }
    if ($normalized.EndsWith('/streamingassets/mq/questionnaire-trigger-catalog.json')) {
        return 110
    }
    if ($normalized.EndsWith('/mq/questionnaire-trigger-catalog.json')) {
        return 120
    }
    if ($normalized.EndsWith('/streamingassets/questionnaire-trigger-catalog.json')) {
        return 130
    }
    if ($normalized.EndsWith('/questionnaire-trigger-catalog.json') -or $normalized -eq 'questionnaire-trigger-catalog.json') {
        return 140
    }
    return -1
}

function Read-TriggerCatalogFromApkPath {
    param([string]$ApkPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
    try {
        $entry = $zip.Entries |
            ForEach-Object {
                [pscustomobject]@{
                    Entry = $_
                    Rank = Get-ApkTriggerCatalogEntryRank -Name $_.FullName
                }
            } |
            Where-Object { $_.Rank -ge 0 } |
            Sort-Object Rank |
            Select-Object -First 1
        if (-not $entry) {
            throw "No questionnaire trigger catalog was found inside local APK: $ApkPath"
        }
        $reader = [System.IO.StreamReader]::new($entry.Entry.Open(), [System.Text.Encoding]::UTF8)
        try {
            $json = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        return $json | ConvertFrom-Json
    }
    finally {
        $zip.Dispose()
    }
}

function Stage-ExistingScenarioApk {
    param(
        [string]$ApkPath,
        [string]$RunPrefix = 'builder-repo-example-apk'
    )

    $safeName = Get-SafeName -Value ([System.IO.Path]::GetFileName($ApkPath))
    if (-not $safeName.EndsWith('.apk', [System.StringComparison]::OrdinalIgnoreCase)) {
        $safeName = "$safeName.apk"
    }
    $safePrefix = Get-SafeName -Value $RunPrefix
    $runId = $safePrefix + '-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $targetDir = Join-Path $ProjectPath ("artifacts\builder-scenario-apks\$runId")
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $targetPath = Join-Path $targetDir $safeName
    Copy-Item -LiteralPath $ApkPath -Destination $targetPath -Force
    $item = Get-Item -LiteralPath $targetPath
    $sha = ''
    try {
        $sha = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
    }
    catch {
        $sha = ''
    }

    $summaryPath = Join-Path $targetDir 'staged-scenario-apk-summary.json'
    $summary = [ordered]@{
        status = 'ok'
        schemaVersion = 'questquestionnaire.builder.staged-scenario-apk.v1'
        runId = $runId
        fileName = $safeName
        sourceApk = $ApkPath
        apk = $targetPath
        bytes = $item.Length
        sha256 = $sha
        stagedAt = (Get-Date).ToString('o')
    }
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    return [ordered]@{
        status = 'ok'
        runId = $runId
        fileName = $safeName
        sourceApk = $ApkPath
        apk = $targetPath
        bytes = $item.Length
        sha256 = $sha
        artifactDir = $targetDir
        summaryPath = $summaryPath
    }
}

function Import-RepoExampleScenarioApk {
    param([object]$Payload)

    $candidatePaths = @()
    if ($Payload.PSObject.Properties.Name -contains 'candidatePaths' -and $Payload.candidatePaths) {
        foreach ($candidate in $Payload.candidatePaths) {
            $candidatePaths += [string]$candidate
        }
    }
    elseif ($Payload.PSObject.Properties.Name -contains 'relativePath') {
        $candidatePaths += [string]$Payload.relativePath
    }
    if ($candidatePaths.Count -eq 0) {
        throw "Repo example APK scan needs at least one relative APK path."
    }

    $build = $null
    try {
        $apkPath = Resolve-RepoRelativeApkPath -CandidatePaths $candidatePaths
    }
    catch {
        $initialError = $_.Exception.Message
        $build = Invoke-ExampleScenarioApkBuild
        if (-not $build.attempted -or $build.exitCode -ne 0) {
            throw "$initialError Example APK auto-build did not produce local APKs. $($build.output)"
        }
        $apkPath = Resolve-RepoRelativeApkPath -CandidatePaths $candidatePaths
    }
    $catalog = Read-TriggerCatalogFromApkPath -ApkPath $apkPath
    $stage = Stage-ExistingScenarioApk -ApkPath $apkPath -RunPrefix 'builder-repo-example-apk'
    return [ordered]@{
        status = 'ok'
        schemaVersion = 'questquestionnaire.builder.repo-example-scenario-apk.v1'
        sourceApk = $apkPath
        exampleApkBuild = $build
        catalog = $catalog
        triggerCount = @($catalog.triggers).Count
        staged = $stage
        fileName = $stage.fileName
        apk = $stage.apk
        bytes = $stage.bytes
        sha256 = $stage.sha256
        summaryPath = $stage.summaryPath
    }
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

function Invoke-HandoffReadinessAudit {
    param([object]$Payload)

    $runId = 'builder-handoff-readiness-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $script = Join-Path $ProjectPath 'tools\audit-universal-handoff-readiness.ps1'
    $summaryPath = Join-Path $ProjectPath ("artifacts\universal-handoff-readiness\$runId\universal-handoff-readiness-audit-summary.json")
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ProjectPath',
        $ProjectPath,
        '-RunId',
        $runId
    )
    if ($Payload.PSObject.Properties.Name -contains 'companionSummaryPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.companionSummaryPath)) {
        $companionSummaryPath = Resolve-EvidenceBundleSummaryPath -Path ([string]$Payload.companionSummaryPath)
        $arguments += @('-CompanionSummaryPath', $companionSummaryPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'requireComplete' -and [bool]$Payload.requireComplete) {
        $arguments += '-RequireComplete'
    }

    $result = Invoke-ProjectPowerShell -Arguments $arguments
    $summary = Read-JsonFileIfExists -Path $summaryPath
    $auditStatus = if ($summary) { [string]$summary.status } elseif ($result.exitCode -eq 0) { 'missing-summary' } else { 'error' }
    $counts = if ($summary -and $summary.PSObject.Properties.Name -contains 'counts') { $summary.counts } else { [pscustomobject]@{} }
    $summaryEvidence = if ($summary -and $summary.PSObject.Properties.Name -contains 'evidence') { $summary.evidence } else { [pscustomobject]@{} }
    $auditReceipt = [ordered]@{
        schemaVersion = 'mq.builder_audit.receipt.v1'
        kind = 'universal-handoff-readiness'
        status = $auditStatus
        exitCode = $result.exitCode
        completionApproved = if ($summary -and $summary.PSObject.Properties.Name -contains 'completionApproved') { [bool]$summary.completionApproved } else { $false }
        defaultDirectPendingIntentApproved = if ($summary -and $summary.PSObject.Properties.Name -contains 'defaultDirectPendingIntentApproved') { [bool]$summary.defaultDirectPendingIntentApproved } else { $false }
        counts = $counts
        physicalQuestProductPathPending = if ($summary -and $counts.PSObject.Properties.Name -contains 'physicalPending') { [int]$counts.physicalPending -gt 0 } else { $true }
        artifacts = [ordered]@{
            summaryPath = $summaryPath
            nextPhysicalGates = if ($summary -and $summary.PSObject.Properties.Name -contains 'nextPhysicalGates') { $summary.nextPhysicalGates } else { $null }
            physicalGatePacketSummaryPath = [string](Get-JsonProperty -Object $summaryEvidence -Name 'physicalGatePacketSummaryPath' -Default '')
            physicalGatePacketEvidenceBundlePath = [string](Get-JsonProperty -Object $summaryEvidence -Name 'physicalGatePacketEvidenceBundlePath' -Default '')
            physicalGatePacketEvidenceBundleAvailable = [bool](Get-JsonProperty -Object $summaryEvidence -Name 'physicalGatePacketEvidenceBundleAvailable' -Default $false)
            physicalGatePacketEvidenceBundlePass = [bool](Get-JsonProperty -Object $summaryEvidence -Name 'physicalGatePacketEvidenceBundlePass' -Default $false)
            physicalGatePacketEvidenceBundleEntryCount = [int](Get-JsonProperty -Object $summaryEvidence -Name 'physicalGatePacketEvidenceBundleEntryCount' -Default 0)
            physicalGatePacketEvidenceBundleTextEntryCount = [int](Get-JsonProperty -Object $summaryEvidence -Name 'physicalGatePacketEvidenceBundleTextEntryCount' -Default 0)
            physicalGatePacketMissingBundleEntries = @(Get-JsonProperty -Object $summaryEvidence -Name 'physicalGatePacketMissingBundleEntries' -Default @())
        }
        proofBoundary = 'Readiness audit summarizes existing evidence. It cannot replace the remaining live Quest product-path trials or manual headset signoff.'
    }

    return [ordered]@{
        status = if ($summary) { 'ok' } else { 'error' }
        auditStatus = $auditStatus
        runId = $runId
        exitCode = $result.exitCode
        summaryPath = $summaryPath
        auditReceipt = $auditReceipt
        summary = $summary
        output = $result.output
    }
}

function Invoke-DirectHandoffManualSignoff {
    param([object]$Payload)

    $runId = 'builder-direct-handoff-manual-signoff-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $script = Join-Path $ProjectPath 'tools\new-direct-handoff-manual-signoff.ps1'
    $summaryPath = Join-Path $ProjectPath ("artifacts\direct-handoff-manual-signoff\$runId\direct-handoff-manual-signoff-summary.json")
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ProjectPath',
        $ProjectPath,
        '-RunId',
        $runId
    )
    if ($Payload.PSObject.Properties.Name -contains 'directHandoffSummaryPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.directHandoffSummaryPath)) {
        $directHandoffSummaryPath = Resolve-EvidenceBundleSummaryPath -Path ([string]$Payload.directHandoffSummaryPath)
        $arguments += @('-DirectHandoffSummaryPath', $directHandoffSummaryPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'operatorSignoffPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.operatorSignoffPath)) {
        $operatorSignoffPath = Resolve-EvidenceBundleSummaryPath -Path ([string]$Payload.operatorSignoffPath)
        $arguments += @('-OperatorSignoffPath', $operatorSignoffPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'questSerial' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questSerial)) {
        $arguments += @('-QuestSerial', [string]$Payload.questSerial)
    }
    if ($Payload.PSObject.Properties.Name -contains 'requirePass' -and [bool]$Payload.requirePass) {
        $arguments += '-RequirePass'
    }

    $result = Invoke-ProjectPowerShell -Arguments $arguments
    $summary = Read-JsonFileIfExists -Path $summaryPath
    $manualStatus = if ($summary) { [string]$summary.status } elseif ($result.exitCode -eq 0) { 'missing-summary' } else { 'error' }
    $receipt = New-DirectHandoffManualSignoffReceipt -Summary $summary -SummaryPath $summaryPath -ExitCode $result.exitCode

    return [ordered]@{
        status = if ($summary) { 'ok' } else { 'error' }
        manualSignoffStatus = $manualStatus
        runId = $runId
        exitCode = $result.exitCode
        summaryPath = $summaryPath
        manualSignoffReceipt = $receipt
        summary = $summary
        output = $result.output
    }
}

function Invoke-UniversalHandoffPhysicalGatePacket {
    param([object]$Payload)

    $runId = 'builder-universal-handoff-physical-gate-packet-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $script = Join-Path $ProjectPath 'tools\new-universal-handoff-physical-gate-packet.ps1'
    $summaryPath = Join-Path $ProjectPath ("artifacts\universal-handoff-physical-gate-packet\$runId\universal-handoff-physical-gate-packet-summary.json")
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ProjectPath',
        $ProjectPath,
        '-RunId',
        $runId
    )
    if ($Payload.PSObject.Properties.Name -contains 'auditSummaryPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.auditSummaryPath)) {
        $auditSummaryPath = Resolve-EvidenceBundleSummaryPath -Path ([string]$Payload.auditSummaryPath)
        $arguments += @('-AuditSummaryPath', $auditSummaryPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'companionSummaryPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.companionSummaryPath)) {
        $companionSummaryPath = Resolve-EvidenceBundleSummaryPath -Path ([string]$Payload.companionSummaryPath)
        $arguments += @('-CompanionSummaryPath', $companionSummaryPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'questSerial' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questSerial)) {
        $arguments += @('-QuestSerial', [string]$Payload.questSerial)
    }

    $result = Invoke-ProjectPowerShell -Arguments $arguments
    $summary = Read-JsonFileIfExists -Path $summaryPath
    $packetStatus = if ($summary) { [string]$summary.status } elseif ($result.exitCode -eq 0) { 'missing-summary' } else { 'error' }
    $receipt = New-PhysicalGatePacketReceipt -Summary $summary -SummaryPath $summaryPath -ExitCode $result.exitCode

    return [ordered]@{
        status = if ($summary) { 'ok' } else { 'error' }
        packetStatus = $packetStatus
        runId = $runId
        exitCode = $result.exitCode
        summaryPath = $summaryPath
        physicalGatePacketReceipt = $receipt
        summary = $summary
        output = $result.output
    }
}

function Invoke-TwoApkLiveValidationPacket {
    param([object]$Payload)

    $runId = 'builder-two-apk-live-validation-packet-' + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
    $script = Join-Path $ProjectPath 'tools\new-two-apk-live-validation-packet.ps1'
    $summaryPath = Join-Path $ProjectPath ("artifacts\two-apk-live-validation-packet\$runId\two-apk-live-validation-packet-summary.json")
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script,
        '-ProjectPath',
        $ProjectPath,
        '-RunId',
        $runId
    )

    $configPath = ''
    if ($Payload.PSObject.Properties.Name -contains 'config') {
        $configPath = Save-ConfigPayload -Payload $Payload
    }
    elseif ($Payload.PSObject.Properties.Name -contains 'questionnaireConfig' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questionnaireConfig)) {
        $configPath = [string]$Payload.questionnaireConfig
    }
    elseif ($Payload.PSObject.Properties.Name -contains 'configPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.configPath)) {
        $configPath = [string]$Payload.configPath
    }
    if (-not [string]::IsNullOrWhiteSpace($configPath)) {
        $arguments += @('-QuestionnaireConfig', $configPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'questionnaireApk' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questionnaireApk)) {
        $arguments += @('-QuestionnaireApk', [string]$Payload.questionnaireApk)
    }
    elseif ($Payload.PSObject.Properties.Name -contains 'apk' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.apk)) {
        $arguments += @('-QuestionnaireApk', [string]$Payload.apk)
    }
    if ($Payload.PSObject.Properties.Name -contains 'unityProjectPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.unityProjectPath)) {
        $arguments += @('-UnityProjectPath', [string]$Payload.unityProjectPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'unityApk' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.unityApk)) {
        $arguments += @('-UnityApk', [string]$Payload.unityApk)
    }
    if ($Payload.PSObject.Properties.Name -contains 'questSerial' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.questSerial)) {
        $arguments += @('-QuestSerial', [string]$Payload.questSerial)
    }
    if ($Payload.PSObject.Properties.Name -contains 'operatorSignoffPath' -and -not [string]::IsNullOrWhiteSpace([string]$Payload.operatorSignoffPath)) {
        $arguments += @('-OperatorSignoffPath', [string]$Payload.operatorSignoffPath)
    }
    if ($Payload.PSObject.Properties.Name -contains 'skipDryRunPreflight' -and [bool]$Payload.skipDryRunPreflight) {
        $arguments += '-SkipDryRunPreflight'
    }
    if ($Payload.PSObject.Properties.Name -contains 'requirePass' -and [bool]$Payload.requirePass) {
        $arguments += '-RequirePass'
    }

    $result = Invoke-ProjectPowerShell -Arguments $arguments
    $summary = Read-JsonFileIfExists -Path $summaryPath
    $packetStatus = if ($summary) { [string](Get-JsonProperty -Object $summary -Name 'status' -Default 'unknown') } elseif ($result.exitCode -eq 0) { 'missing-summary' } else { 'error' }
    $receipt = New-TwoApkLiveValidationPacketReceipt -Summary $summary -SummaryPath $summaryPath -ExitCode $result.exitCode

    return [ordered]@{
        status = if ($summary) { 'ok' } else { 'error' }
        packetStatus = $packetStatus
        runId = $runId
        exitCode = $result.exitCode
        summaryPath = $summaryPath
        twoApkLivePacketReceipt = $receipt
        summary = $summary
        output = $result.output
    }
}

function New-StatusPayload {
    param([bool]$Authorized)

    $payload = [ordered]@{
        status = 'ok'
        schemaVersion = 'my-questionnaire-2d.builder-app.v1'
        apiVersion = '2026-06-07.packet-bundle-audit-receipts.v1'
        receiptSchemaVersion = 'my-questionnaire-2d.builder-receipts.v1'
        mode = $Mode
        url = "http://127.0.0.1:$Port/"
        requiresToken = $true
        authorized = $Authorized
        allowedOrigins = $EffectiveAllowedOrigins
        onlinePageUrl = $OnlinePageUrl
        capabilities = @(
            'public-status',
            'token-auth',
            'save-config',
            'validate-config',
            'generate-apk',
            'generate-apk-receipt',
            'artifact-preview',
            'evidence-bundle',
            'workflow-render-previews',
            'validate-workflow',
            'workflow-job-status',
            'workflow-receipt',
            'quest-readiness',
            'stage-scenario-apk',
            'stage-scenario-apk-chunk',
            'stage-repo-example-scenario-apk',
            'install-apk',
            'install-apk-job-status',
            'quest-replay',
            'quest-replay-job-status',
            'direct-handoff',
            'direct-handoff-preflight',
            'direct-handoff-job-status',
            '2d-first-launcher',
            '2d-first-launcher-preflight',
            '2d-first-launcher-job-status',
            'minimal-apk-trigger-protocol',
            'minimal-apk-trigger-protocol-job-status',
            'two-apk-live-validation-packet',
            'handoff-readiness-audit',
            'direct-handoff-manual-signoff',
            'physical-gate-packet',
            'operator-guardrail-receipts',
            'packet-bundle-audit-receipts',
            'runner-job-receipts',
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
            directHandoff = Join-Path $ProjectPath 'tools\quest-direct-handoff-validate.ps1'
            twoDFirstLauncher = Join-Path $ProjectPath 'tools\quest-2d-first-launcher-validate.ps1'
            minimalApkTriggerProtocol = Join-Path $ProjectPath 'tools\quest-minimal-apk-trigger-protocol-validate.ps1'
            twoApkLiveValidationPacket = Join-Path $ProjectPath 'tools\new-two-apk-live-validation-packet.ps1'
            handoffReadinessAudit = Join-Path $ProjectPath 'tools\audit-universal-handoff-readiness.ps1'
            directHandoffManualSignoff = Join-Path $ProjectPath 'tools\new-direct-handoff-manual-signoff.ps1'
            physicalGatePacket = Join-Path $ProjectPath 'tools\new-universal-handoff-physical-gate-packet.ps1'
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

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/artifact-preview') {
        Assert-OriginAndToken -Request $request
        $artifactPath = Resolve-ArtifactPreviewPath -Path ([string]$request.QueryString['path'])
        Write-BinaryFileResponse -Context $Context -StatusCode 200 -ContentType 'image/png' -Path $artifactPath
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/evidence-bundle') {
        Assert-OriginAndToken -Request $request
        $bundle = New-EvidenceBundle -SummaryPath ([string]$request.QueryString['summaryPath'])
        Write-BinaryFileResponse -Context $Context -StatusCode 200 -ContentType 'application/zip' -Path ([string]$bundle.zipPath) -DownloadFileName ([string]$bundle.fileName)
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

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/direct-handoff-job') {
        Assert-OriginAndToken -Request $request
        $runId = [string]$request.QueryString['runId']
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = [string]$request.QueryString['jobId']
        }
        $status = Get-DirectHandoffJobStatus -RunId $runId
        if ($null -eq $status) {
            Write-JsonResponse -Context $Context -StatusCode 404 -Value ([ordered]@{
                status = 'error'
                message = "Unknown direct handoff job: $runId"
            })
            return
        }
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $status
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/2d-first-launcher-job') {
        Assert-OriginAndToken -Request $request
        $runId = [string]$request.QueryString['runId']
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = [string]$request.QueryString['jobId']
        }
        $status = Get-TwoDFirstLauncherJobStatus -RunId $runId
        if ($null -eq $status) {
            Write-JsonResponse -Context $Context -StatusCode 404 -Value ([ordered]@{
                status = 'error'
                message = "Unknown 2D-first launcher job: $runId"
            })
            return
        }
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $status
        return
    }

    if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/minimal-protocol-job') {
        Assert-OriginAndToken -Request $request
        $runId = [string]$request.QueryString['runId']
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = [string]$request.QueryString['jobId']
        }
        $status = Get-MinimalProtocolJobStatus -RunId $runId
        if ($null -eq $status) {
            Write-JsonResponse -Context $Context -StatusCode 404 -Value ([ordered]@{
                status = 'error'
                message = "Unknown minimal protocol job: $runId"
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

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/stage-scenario-apk') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Save-StagedScenarioApk -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $result
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/stage-scenario-apk-chunk') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Save-StagedScenarioApkChunk -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $result
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/stage-repo-example-scenario-apk') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Import-RepoExampleScenarioApk -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 200 -Value $result
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

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/direct-handoff') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $job = Start-DirectHandoffJob -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 202 -Value $job
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/2d-first-launcher') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $job = Start-TwoDFirstLauncherJob -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 202 -Value $job
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/minimal-protocol') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $job = Start-MinimalProtocolJob -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode 202 -Value $job
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/two-apk-live-packet') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Invoke-TwoApkLiveValidationPacket -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.status -eq 'ok') { 200 } else { 500 })) -Value $result
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/handoff-readiness-audit') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Invoke-HandoffReadinessAudit -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.status -eq 'ok') { 200 } else { 500 })) -Value $result
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/direct-handoff-manual-signoff') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Invoke-DirectHandoffManualSignoff -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.status -eq 'ok') { 200 } else { 500 })) -Value $result
        return
    }

    if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/physical-gate-packet') {
        Assert-OriginAndToken -Request $request
        $payload = Receive-JsonPayload -Request $request
        $result = Invoke-UniversalHandoffPhysicalGatePacket -Payload $payload
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.status -eq 'ok') { 200 } else { 500 })) -Value $result
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
        $skipBuildRequested = ($payload.PSObject.Properties.Name -contains 'skipBuild' -and [bool]$payload.skipBuild)
        $renderPreviewRequested = ($payload.PSObject.Properties.Name -contains 'renderPreview' -and [bool]$payload.renderPreview)

        $result = Invoke-ProjectPowerShell -Arguments $arguments
        $summaryPath = Join-Path $ProjectPath ("artifacts\apk-generator\$runId\generator-summary.json")
        $summary = Read-JsonFileIfExists -Path $summaryPath
        $apk = if ($null -ne $summary) { $summary.apk } else { $null }
        $generationReceipt = New-GenerationReceipt -Summary $summary -SummaryPath $summaryPath -ExitCode $result.exitCode -SkipBuild $skipBuildRequested -RenderPreviewRequested $renderPreviewRequested
        Write-JsonResponse -Context $Context -StatusCode ($(if ($result.exitCode -eq 0) { 200 } else { 500 })) -Value ([ordered]@{
            status = if ($result.exitCode -eq 0) { 'ok' } else { 'error' }
            configPath = $configPath
            runId = $runId
            exitCode = $result.exitCode
            apk = $apk
            summaryPath = $summaryPath
            generationReceipt = $generationReceipt
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
            $jobStatus = if ($result.exitCode -eq 0) { 'completed' } else { 'failed' }
            $workflowStatus = if ($summary) { $summary.status } else { 'missing-summary' }
            $workflowReceipt = New-WorkflowReceipt -Summary $summary -SummaryPath $summaryPath -JobStatus $jobStatus -WorkflowStatus $workflowStatus
            Write-JsonResponse -Context $Context -StatusCode ($(if ($result.exitCode -eq 0) { 200 } else { 500 })) -Value ([ordered]@{
                status = if ($result.exitCode -eq 0) { 'ok' } else { 'error' }
                jobStatus = $jobStatus
                workflowStatus = $workflowStatus
                configPath = $configPath
                runId = $runId
                jobId = $runId
                exitCode = $result.exitCode
                summaryPath = $summaryPath
                workflowReceipt = $workflowReceipt
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
    Start-Process $url
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
            elseif ($message -like 'Artifact preview path is required*') {
                $statusCode = 400
            }
            elseif ($message -like 'Artifact preview path is not allowed*') {
                $statusCode = 403
            }
            elseif ($message -like 'Artifact preview path not found*') {
                $statusCode = 404
            }
            elseif ($message -like 'Artifact preview only supports*') {
                $statusCode = 415
            }
            elseif ($message -like 'Evidence bundle summaryPath is required*') {
                $statusCode = 400
            }
            elseif ($message -like 'Evidence bundle summary path is not allowed*') {
                $statusCode = 403
            }
            elseif ($message -like 'Evidence bundle summary path not found*') {
                $statusCode = 404
            }
            elseif ($message -like 'Evidence bundle summary path is a directory*') {
                $statusCode = 400
            }
            elseif ($message -like 'Evidence bundle only accepts*') {
                $statusCode = 415
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
