Set-StrictMode -Version 2.0

function Get-FileTextEncoding {
    param([Parameter(Mandatory=$true)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return (New-Object System.Text.UTF8Encoding($true))
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return (New-Object System.Text.UnicodeEncoding($false,$true))
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return (New-Object System.Text.UnicodeEncoding($true,$true))
    }
    return (New-Object System.Text.UTF8Encoding($false))
}
function Complete-PbiBackupManifest {
    param(
        [Parameter(Mandatory=$true)][string]$ManifestPath,
        [Parameter(Mandatory=$true)][string]$Status
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($entry in @($manifest.Entries)) {
        if (Test-Path -LiteralPath $entry.TargetPath -PathType Leaf) {
            $appliedHash = (Get-FileHash -LiteralPath $entry.TargetPath -Algorithm SHA256).Hash
            $entry | Add-Member -MemberType NoteProperty -Name AppliedHash -Value $appliedHash -Force
        }
    }

    $manifest.Status = $Status
    $manifest | Add-Member -MemberType NoteProperty -Name AppliedAt -Value ((Get-Date).ToString('o')) -Force
    $json = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($ManifestPath,$json,(New-Object System.Text.UTF8Encoding($false)))
}

function Format-InvariantNumber {
    param([double]$Value)
    return $Value.ToString('0.###',[System.Globalization.CultureInfo]::InvariantCulture)
}

function Set-PositionNumberInText {
    param([string]$Text,[string]$Property,[double]$Value)
    $positionPattern = '(?s)("position"\s*:\s*\{)(.*?)(\})'
    $positionMatch = [regex]::Match($Text,$positionPattern)
    if (-not $positionMatch.Success) { throw 'position object was not found in visual.json.' }
    $block = $positionMatch.Groups[2].Value
    $number = Format-InvariantNumber -Value $Value
    $propertyPattern = '(?m)("' + [regex]::Escape($Property) + '"\s*:\s*)(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)'
    if (-not [regex]::IsMatch($block,$propertyPattern)) { throw ('position.{0} was not found in visual.json.' -f $Property) }
    $newBlock = [regex]::Replace($block,$propertyPattern,('${1}' + $number),1)
    return $Text.Substring(0,$positionMatch.Groups[2].Index) + $newBlock + $Text.Substring($positionMatch.Groups[2].Index + $positionMatch.Groups[2].Length)
}

function Test-GeometryInJsonFile {
    param([string]$Path,$Item)
    $encoding = Get-FileTextEncoding -Path $Path
    $json = [System.IO.File]::ReadAllText($Path,$encoding) | ConvertFrom-Json
    if (-not ($json.PSObject.Properties.Name -contains 'position')) { return $false }
    $p = $json.position
    return ([Math]::Abs(([double]$p.x)-$Item.X) -le 0.001) -and ([Math]::Abs(([double]$p.y)-$Item.Y) -le 0.001) -and ([Math]::Abs(([double]$p.width)-$Item.Width) -le 0.001) -and ([Math]::Abs(([double]$p.height)-$Item.Height) -le 0.001)
}

function Set-PbiLayoutFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Layout,
        [Parameter(Mandatory=$true)]$BackupOperation
    )

    $changed = @($Layout.Items | Where-Object { $_.Changed })
    if ($changed.Count -eq 0) { return [pscustomobject]@{ Success=$true; ChangedCount=0; Files=@() } }
    $written = New-Object System.Collections.Generic.List[string]

    try {
        foreach ($item in $changed) {
            $target = [string]$item.FilePath
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw ('visual.json missing before write: {0}' -f $target) }
            if ($item.PSObject.Properties.Name -contains 'SourceHash' -and -not [string]::IsNullOrWhiteSpace([string]$item.SourceHash)) {
                $currentHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                if ($currentHash -ne [string]$item.SourceHash) {
                    throw ('visual.json changed after analysis for {0}. Re-analyze before applying.' -f $item.Id)
                }
            }
            $encoding = Get-FileTextEncoding -Path $target
            $text = [System.IO.File]::ReadAllText($target,$encoding)
            $updated = Set-PositionNumberInText -Text $text -Property 'x' -Value $item.X
            $updated = Set-PositionNumberInText -Text $updated -Property 'y' -Value $item.Y
            $updated = Set-PositionNumberInText -Text $updated -Property 'width' -Value $item.Width
            $updated = Set-PositionNumberInText -Text $updated -Property 'height' -Value $item.Height

            $temp = $target + '.pbiautomate.tmp'
            [System.IO.File]::WriteAllText($temp,$updated,$encoding)
            try {
                $null = [System.IO.File]::ReadAllText($temp,$encoding) | ConvertFrom-Json
                if (-not (Test-GeometryInJsonFile -Path $temp -Item $item)) { throw ('Temporary geometry validation failed for {0}' -f $item.Id) }
                Move-Item -LiteralPath $temp -Destination $target -Force
            } finally {
                if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
            }

            if (-not (Test-GeometryInJsonFile -Path $target -Item $item)) { throw ('Final geometry validation failed for {0}' -f $item.Id) }
            $written.Add($target)
        }
        Complete-PbiBackupManifest -ManifestPath $BackupOperation.ManifestPath -Status 'Applied'
        return [pscustomobject]@{ Success=$true; ChangedCount=$written.Count; Files=@($written) }
    }
    catch {
        $manifestPath = $BackupOperation.ManifestPath
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($manifest.Entries)) {
                if (Test-Path -LiteralPath $entry.BackupPath -PathType Leaf) { Copy-Item -LiteralPath $entry.BackupPath -Destination $entry.TargetPath -Force }
            }
        }
        throw
    }
}

Export-ModuleMember -Function Set-PbiLayoutFiles
