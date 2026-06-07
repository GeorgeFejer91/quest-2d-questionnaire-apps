$ErrorActionPreference = 'Stop'

function Write-SourceAssetSnapshotJson {
    param([object]$Value, [string]$Path, [int]$Depth = 10)

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertTo-SourceAssetLongPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
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

function New-SourceAssetDirectory {
    param([string]$Path)

    [System.IO.Directory]::CreateDirectory((ConvertTo-SourceAssetLongPath -Path $Path)) | Out-Null
}

function Test-SourceAssetFile {
    param([string]$Path)

    return [System.IO.File]::Exists((ConvertTo-SourceAssetLongPath -Path $Path))
}

function Copy-SourceAssetFile {
    param([string]$Source, [string]$Destination)

    $parent = Split-Path -Parent $Destination
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-SourceAssetDirectory -Path $parent
    }
    [System.IO.File]::Copy(
        (ConvertTo-SourceAssetLongPath -Path $Source),
        (ConvertTo-SourceAssetLongPath -Path $Destination),
        $true)
}

function Remove-SourceAssetFile {
    param([string]$Path)

    [System.IO.File]::Delete((ConvertTo-SourceAssetLongPath -Path $Path))
}

function Get-SourceAssetRelativePath {
    param([string]$Root, [string]$Path)

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $rootFull = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside expected root. Root=$rootFull Path=$fullPath"
    }
    return $fullPath.Substring($rootFull.Length)
}

function New-SourceAssetDirectorySnapshot {
    param(
        [string]$SourceRoot,
        [string]$SnapshotRoot,
        [string]$SummaryPath
    )

    $sourceExists = Test-Path -LiteralPath $SourceRoot
    New-SourceAssetDirectory -Path $SnapshotRoot
    $files = @()
    if ($sourceExists) {
        $sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
        $items = @(Get-ChildItem -LiteralPath $sourceRootFull -File -Recurse -Force | Sort-Object FullName)
        foreach ($item in $items) {
            $relativePath = Get-SourceAssetRelativePath -Root $sourceRootFull -Path $item.FullName
            $snapshotPath = Join-Path $SnapshotRoot $relativePath
            Copy-SourceAssetFile -Source $item.FullName -Destination $snapshotPath
            $files += [ordered]@{
                relativePath = $relativePath
                bytes = $item.Length
                sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
            }
        }
    }

    $snapshot = [ordered]@{
        schemaVersion = 'mq.directory_snapshot.v1'
        sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
        sourceExists = $sourceExists
        snapshotRoot = [System.IO.Path]::GetFullPath($SnapshotRoot)
        fileCount = $files.Count
        files = $files
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-SourceAssetSnapshotJson -Value $snapshot -Path $SummaryPath -Depth 8
    return $snapshot
}

function Restore-SourceAssetDirectorySnapshot {
    param(
        [object]$Snapshot,
        [string]$SourceRoot
    )

    if ($null -eq $Snapshot) {
        return [ordered]@{
            schemaVersion = 'mq.directory_snapshot_restore.v1'
            status = 'fail'
            error = 'Snapshot was not created.'
        }
    }

    $sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
    $snapshotRootFull = [System.IO.Path]::GetFullPath([string]$Snapshot.snapshotRoot)
    New-SourceAssetDirectory -Path $sourceRootFull

    $snapshotPaths = @{}
    $missingSnapshotFiles = @()
    $restoredCount = 0
    foreach ($file in @($Snapshot.files)) {
        $relativePath = [string]$file.relativePath
        $snapshotPaths[$relativePath.ToLowerInvariant()] = $true
        $snapshotFile = Join-Path $snapshotRootFull $relativePath
        if (-not (Test-SourceAssetFile -Path $snapshotFile)) {
            $missingSnapshotFiles += $relativePath
            continue
        }
        $targetFile = Join-Path $sourceRootFull $relativePath
        $targetFull = [System.IO.Path]::GetFullPath($targetFile)
        [void](Get-SourceAssetRelativePath -Root $sourceRootFull -Path $targetFull)
        Copy-SourceAssetFile -Source $snapshotFile -Destination $targetFull
        $restoredCount += 1
    }

    $removedNewFiles = @()
    $currentFiles = @(Get-ChildItem -LiteralPath $sourceRootFull -File -Recurse -Force)
    foreach ($currentFile in $currentFiles) {
        $relativePath = Get-SourceAssetRelativePath -Root $sourceRootFull -Path $currentFile.FullName
        if (-not $snapshotPaths.ContainsKey($relativePath.ToLowerInvariant())) {
            Remove-SourceAssetFile -Path $currentFile.FullName
            $removedNewFiles += $relativePath
        }
    }

    $missingRestoredFiles = @()
    $hashMismatches = @()
    foreach ($file in @($Snapshot.files)) {
        $relativePath = [string]$file.relativePath
        $targetFile = Join-Path $sourceRootFull $relativePath
        if (-not (Test-SourceAssetFile -Path $targetFile)) {
            $missingRestoredFiles += $relativePath
            continue
        }
        $actualHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
        if ($actualHash -ne [string]$file.sha256) {
            $hashMismatches += $relativePath
        }
    }

    $extraFiles = @()
    $postFiles = @(Get-ChildItem -LiteralPath $sourceRootFull -File -Recurse -Force)
    foreach ($postFile in $postFiles) {
        $relativePath = Get-SourceAssetRelativePath -Root $sourceRootFull -Path $postFile.FullName
        if (-not $snapshotPaths.ContainsKey($relativePath.ToLowerInvariant())) {
            $extraFiles += $relativePath
        }
    }

    $status = if ($missingSnapshotFiles.Count -eq 0 -and $missingRestoredFiles.Count -eq 0 -and $hashMismatches.Count -eq 0 -and $extraFiles.Count -eq 0) { 'pass' } else { 'fail' }
    return [ordered]@{
        schemaVersion = 'mq.directory_snapshot_restore.v1'
        status = $status
        sourceRoot = $sourceRootFull
        snapshotRoot = $snapshotRootFull
        restoredFileCount = $restoredCount
        removedNewFileCount = $removedNewFiles.Count
        missingSnapshotFileCount = $missingSnapshotFiles.Count
        missingRestoredFileCount = $missingRestoredFiles.Count
        hashMismatchCount = $hashMismatches.Count
        extraFileCount = $extraFiles.Count
        removedNewFiles = @($removedNewFiles | Select-Object -First 20)
        missingSnapshotFiles = @($missingSnapshotFiles | Select-Object -First 20)
        missingRestoredFiles = @($missingRestoredFiles | Select-Object -First 20)
        hashMismatches = @($hashMismatches | Select-Object -First 20)
        extraFiles = @($extraFiles | Select-Object -First 20)
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
}
