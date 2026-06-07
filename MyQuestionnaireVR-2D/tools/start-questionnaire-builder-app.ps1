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
$script:DirectHandoffJobs = @{}
$script:DirectHandoffJobOrder = New-Object 'System.Collections.Generic.List[string]'
$script:TwoDFirstLauncherJobs = @{}
$script:TwoDFirstLauncherJobOrder = New-Object 'System.Collections.Generic.List[string]'

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
    return [ordered]@{
        schemaVersion = 'mq.builder_runner.job_receipt.v1'
        kind = 'quest-replay-export'
        status = if ([string]::IsNullOrWhiteSpace($ReplayStatus)) { $JobStatus } else { $ReplayStatus }
        jobStatus = $JobStatus
        actionStatus = $ReplayStatus
        dryRun = $summaryDryRun
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
        apiVersion = '2026-06-07.receipts.v1'
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
