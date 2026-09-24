Set-StrictMode -Version 2.0

function Invoke-AlignmentPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$PageSnapshot,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][double]$Margin,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    # First classify the current page, then normalize any unintended
    # active-visual overlaps in memory. No PBIR file is written at this stage.
    $initialAnalysis = Get-PbiLayoutAnalysis -PageSnapshot $PageSnapshot `
        -MinimumTolerance ([double]$Config.layout.minimumTolerance) `
        -MaximumTolerance ([double]$Config.layout.maximumTolerance)

    $overlapNormalization = Resolve-PbiSnapshotOverlaps -PageSnapshot $PageSnapshot -InitialAnalysis $initialAnalysis -Margin $Margin -Gap $Gap

    $analysisSnapshot = $overlapNormalization.Snapshot
    $analysis = if ($overlapNormalization.HadOverlaps) {
        Get-PbiLayoutAnalysis -PageSnapshot $analysisSnapshot `
            -MinimumTolerance ([double]$Config.layout.minimumTolerance) `
            -MaximumTolerance ([double]$Config.layout.maximumTolerance)
    }
    else {
        $initialAnalysis
    }

    $layout = Get-SmartPbiLayout -Analysis $analysis -Margin $Margin -Gap $Gap
    $layout | Add-Member -MemberType NoteProperty -Name PreNormalizationOverlapPairs -Value ([int]$overlapNormalization.InitialOverlapPairCount) -Force
    $layout | Add-Member -MemberType NoteProperty -Name PreNormalizationMovedCount -Value ([int]$overlapNormalization.MovedCount) -Force
    $layout | Add-Member -MemberType NoteProperty -Name PreNormalizationResizedCount -Value ([int]$overlapNormalization.ResizedCount) -Force
    $layout | Add-Member -MemberType NoteProperty -Name PreNormalizationRemainingOverlapPairs -Value ([int]$overlapNormalization.RemainingOverlapPairCount) -Force
    $layout | Add-Member -MemberType NoteProperty -Name PreNormalizationCompactFallback -Value ([bool]$overlapNormalization.UsedCompactFallback) -Force

    $validation = Test-PbiLayout -Layout $layout

    [pscustomobject]@{
        InitialAnalysis = $initialAnalysis
        OverlapNormalization = $overlapNormalization
        Analysis = $analysis
        Layout = $layout
        Validation = $validation
    }
}

function Test-AlignmentCurrentPage {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$PageSnapshot)

    $current = [pscustomobject]@{
        PageWidth = [double]$PageSnapshot.Width
        PageHeight = [double]$PageSnapshot.Height
        Items = @($PageSnapshot.Visuals)
    }

    return Test-PbiLayout -Layout $current
}

function Invoke-AlignmentApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$PageName,
        [Parameter(Mandatory=$true)]$Layout
    )

    $validation = Test-PbiLayout -Layout $Layout
    if (-not $validation.IsValid) {
        throw ('Proposed alignment layout is invalid: ' + ($validation.Errors -join ' | '))
    }

    $backup = New-PbiBackup -ProjectRoot $ProjectRoot -Items $Layout.Items -PageName $PageName
    $write = Set-PbiLayoutFiles -Layout $Layout -BackupOperation $backup

    [pscustomobject]@{
        Backup = $backup
        Write = $write
    }
}

function Invoke-AlignmentUndo {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)

    return Undo-LatestPbiApply -ProjectRoot $ProjectRoot
}

Export-ModuleMember -Function Invoke-AlignmentPreview, Test-AlignmentCurrentPage, Invoke-AlignmentApply, Invoke-AlignmentUndo
