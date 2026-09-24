Set-StrictMode -Version 2.0

function Set-UndoManifestStatus {
    param(
        [Parameter(Mandatory=$true)][string]$ManifestPath,
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string]$Status
    )

    $Manifest.Status = $Status
    $Manifest | Add-Member -MemberType NoteProperty -Name UndoneAt -Value ((Get-Date).ToString('o')) -Force
    $json = $Manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($ManifestPath,$json,(New-Object System.Text.UTF8Encoding($false)))
}

function Undo-LatestPbiApply {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)

    $manifestPath = Get-LatestPbiBackupManifest -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($manifestPath)) { throw 'No PBI Automate backup was found for this project.' }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $status = ''
    if ($manifest.PSObject.Properties.Name -contains 'Status') { $status = [string]$manifest.Status }

    if ($status -eq 'Undone') {
        throw 'The latest PBI Automate apply operation has already been undone.'
    }
    if ($status -ne 'Applied') {
        throw ('The latest PBI Automate operation is not in Applied state (status: {0}). Nothing can be safely undone.' -f $status)
    }

    foreach ($entry in @($manifest.Entries)) {
        if (-not (Test-Path -LiteralPath $entry.TargetPath -PathType Leaf)) {
            throw ('Cannot undo because the current visual file is missing: {0}' -f $entry.TargetPath)
        }

        if ($entry.PSObject.Properties.Name -contains 'AppliedHash' -and -not [string]::IsNullOrWhiteSpace([string]$entry.AppliedHash)) {
            $currentHash = (Get-FileHash -LiteralPath $entry.TargetPath -Algorithm SHA256).Hash
            if ($currentHash -ne [string]$entry.AppliedHash) {
                throw ('Undo blocked because "{0}" changed after PBI Automate applied the layout. Reverting would overwrite newer changes.' -f $entry.TargetPath)
            }
        }
    }

    $restoredManifest = Restore-PbiBackupManifest -ManifestPath $manifestPath
    Set-UndoManifestStatus -ManifestPath $manifestPath -Manifest $restoredManifest -Status 'Undone'

    [pscustomobject]@{
        Success = $true
        ManifestPath = $manifestPath
        RestoredCount = @($restoredManifest.Entries).Count
        Timestamp = $restoredManifest.Timestamp
    }
}

Export-ModuleMember -Function Undo-LatestPbiApply
