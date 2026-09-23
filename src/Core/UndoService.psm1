Set-StrictMode -Version 2.0

function Undo-LatestPbiApply {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $manifestPath = Get-LatestPbiBackupManifest -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($manifestPath)) { throw 'No PBI Automate backup was found for this project.' }
    $manifest = Restore-PbiBackupManifest -ManifestPath $manifestPath
    [pscustomobject]@{ Success=$true; ManifestPath=$manifestPath; RestoredCount=@($manifest.Entries).Count; Timestamp=$manifest.Timestamp }
}

Export-ModuleMember -Function Undo-LatestPbiApply
