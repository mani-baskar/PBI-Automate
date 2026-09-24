Set-StrictMode -Version 2.0

function Get-BackupRoot {
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
    $root = Join-Path $base 'PBIAutomate\Backups'
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    return $root
}

function Get-ProjectBackupKey {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $normalized = ([System.IO.Path]::GetFullPath($ProjectRoot)).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalized)) } finally { $sha.Dispose() }
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    $leaf = Split-Path -Leaf $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = 'project' }
    $safeLeaf = ($leaf -replace '[^a-zA-Z0-9._-]','_')
    return ('{0}-{1}' -f $safeLeaf,$hex.Substring(0,12))
}

function New-PbiBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][object[]]$Items,
        [string]$PageName = ''
    )

    $targets = @($Items | Where-Object { $_.Changed } | Select-Object -ExpandProperty FilePath -Unique)
    if ($targets.Count -eq 0) { throw 'There are no changed visual files to back up.' }
    $projectKey = Get-ProjectBackupKey -ProjectRoot $ProjectRoot
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $operationDir = Join-Path (Join-Path (Get-BackupRoot) $projectKey) $timestamp
    New-Item -ItemType Directory -Path $operationDir -Force | Out-Null

    $entries = @(); $index = 0
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw ('Cannot back up missing file: {0}' -f $target) }
        $index++
        $backupName = ('{0:D4}-{1}' -f $index,(Split-Path -Leaf (Split-Path -Parent $target)))
        $backupPath = Join-Path $operationDir ($backupName + '.visual.json')
        Copy-Item -LiteralPath $target -Destination $backupPath -Force
        $entries += [pscustomobject]@{ TargetPath=$target; BackupPath=$backupPath; OriginalHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash }
    }

    $manifest = [pscustomobject]@{
        Product='PBI Automate'; Version=1; Timestamp=(Get-Date).ToString('o'); ProjectRoot=$ProjectRoot; ProjectKey=$projectKey; PageName=$PageName; Status='Created'; Entries=$entries
    }
    $manifestPath = Join-Path $operationDir 'manifest.json'
    $json = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($manifestPath,$json,(New-Object System.Text.UTF8Encoding($false)))

    [pscustomobject]@{ Directory=$operationDir; ManifestPath=$manifestPath; Manifest=$manifest }
}

function Restore-PbiBackupManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'Backup manifest not found.' }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($manifest.Entries)) {
        if (-not (Test-Path -LiteralPath $entry.BackupPath -PathType Leaf)) { throw ('Backup file missing: {0}' -f $entry.BackupPath) }
        $parent = Split-Path -Parent $entry.TargetPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $entry.BackupPath -Destination $entry.TargetPath -Force
        $restoredHash = (Get-FileHash -LiteralPath $entry.TargetPath -Algorithm SHA256).Hash
        if ($restoredHash -ne $entry.OriginalHash) { throw ('Restored hash validation failed for {0}' -f $entry.TargetPath) }
    }
    return $manifest
}

function Get-LatestPbiBackupManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $projectDir = Join-Path (Get-BackupRoot) (Get-ProjectBackupKey -ProjectRoot $ProjectRoot)
    if (-not (Test-Path -LiteralPath $projectDir -PathType Container)) { return $null }
    $latest = Get-ChildItem -LiteralPath $projectDir -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $latest) { return $null }
    $manifestPath = Join-Path $latest.FullName 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { return $manifestPath }
    return $null
}

Export-ModuleMember -Function New-PbiBackup, Restore-PbiBackupManifest, Get-LatestPbiBackupManifest
