Set-StrictMode -Version 2.0

function Get-AlignmentVerticalContainmentRatio {
    param(
        [Parameter(Mandatory=$true)]$Anchor,
        [Parameter(Mandatory=$true)]$Candidate
    )

    $anchorTop = [double]$Anchor.Y
    $anchorBottom = [double]$Anchor.Y + [double]$Anchor.Height
    $candidateTop = [double]$Candidate.Y
    $candidateBottom = [double]$Candidate.Y + [double]$Candidate.Height

    $overlapTop = [Math]::Max($anchorTop,$candidateTop)
    $overlapBottom = [Math]::Min($anchorBottom,$candidateBottom)
    $overlap = [Math]::Max(0.0,($overlapBottom - $overlapTop))

    # User rule: a visual belongs to the anchor row when at least 80% of
    # that candidate visual's height falls inside the anchor's height band.
    $candidateHeight = [double]$Candidate.Height
    if ($candidateHeight -le 0) { return 0.0 }

    return ($overlap / $candidateHeight)
}

function New-AlignmentProposedItem {
    param(
        [Parameter(Mandatory=$true)]$Item,
        [Parameter(Mandatory=$true)][double]$X,
        [Parameter(Mandatory=$true)][double]$Y,
        [Parameter(Mandatory=$true)][double]$Width,
        [Parameter(Mandatory=$true)][double]$Height,
        [bool]$IsLocked = $false,
        [int]$Column = 0,
        [int]$Row = 0
    )

    $oldX = if ($Item.PSObject.Properties.Name -contains 'OriginalX') { [double]$Item.OriginalX } else { [double]$Item.X }
    $oldY = if ($Item.PSObject.Properties.Name -contains 'OriginalY') { [double]$Item.OriginalY } else { [double]$Item.Y }
    $oldWidth = if ($Item.PSObject.Properties.Name -contains 'OriginalWidth') { [double]$Item.OriginalWidth } else { [double]$Item.Width }
    $oldHeight = if ($Item.PSObject.Properties.Name -contains 'OriginalHeight') { [double]$Item.OriginalHeight } else { [double]$Item.Height }

    $oldArea = $oldWidth * $oldHeight
    $newArea = $Width * $Height
    $areaChangePercent = 0.0
    if ($oldArea -gt 0) {
        $areaChangePercent = (($newArea - $oldArea) / $oldArea) * 100.0
    }

    $allowOverlap = $false
    if ($Item.PSObject.Properties.Name -contains 'AllowOverlap') { $allowOverlap = [bool]$Item.AllowOverlap }

    $protectionReason = $null
    if ($Item.PSObject.Properties.Name -contains 'ProtectionReason') { $protectionReason = $Item.ProtectionReason }

    [pscustomobject]@{
        Id = $Item.Id
        VisualType = $Item.VisualType
        FilePath = $Item.FilePath
        SourceHash = $Item.SourceHash
        ParentGroupName = $Item.ParentGroupName
        IsVisualGroup = $Item.IsVisualGroup
        IsHidden = $Item.IsHidden
        EffectiveHidden = $(if ($Item.PSObject.Properties.Name -contains 'EffectiveHidden') { [bool]$Item.EffectiveHidden } else { [bool]$Item.IsHidden })
        ProtectionReason = $protectionReason
        OldX = $oldX
        OldY = $oldY
        OldWidth = $oldWidth
        OldHeight = $oldHeight
        OriginalArea = [Math]::Round($oldArea,3)
        ProposedArea = [Math]::Round($newArea,3)
        AreaChangePercent = [Math]::Round($areaChangePercent,2)
        X = [Math]::Round($X,3)
        Y = [Math]::Round($Y,3)
        Width = [Math]::Round($Width,3)
        Height = [Math]::Round($Height,3)
        Column = $Column
        Row = $Row
        ColumnSpan = 1
        RowSpan = 1
        IsLocked = $IsLocked
        AllowOverlap = $allowOverlap
        Changed = (
            -not $IsLocked -and (
                [Math]::Abs($oldX - $X) -gt 0.001 -or
                [Math]::Abs($oldY - $Y) -gt 0.001 -or
                [Math]::Abs($oldWidth - $Width) -gt 0.001 -or
                [Math]::Abs($oldHeight - $Height) -gt 0.001
            )
        )
    }
}

function Get-AlignmentRowGroups {
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [ValidateRange(0.50,1.00)][double]$RowOverlapThreshold = 0.80
    )

    $remaining = @($Items | Sort-Object Y, X)
    $rows = @()

    while ($remaining.Count -gt 0) {
        # Top-most, then left-most visual is the primary anchor for this row.
        $anchor = $remaining[0]
        $rowItems = @()
        $nextRemaining = @()

        foreach ($item in $remaining) {
            $ratio = Get-AlignmentVerticalContainmentRatio -Anchor $anchor -Candidate $item
            if ($item.Id -eq $anchor.Id -or $ratio -ge $RowOverlapThreshold) {
                $rowItems += $item
            }
            else {
                $nextRemaining += $item
            }
        }

        $rowItems = @($rowItems | Sort-Object X)
        $baseHeight = [double](($rowItems | Measure-Object -Property Height -Maximum).Maximum)
        if ($baseHeight -le 0) { $baseHeight = [double]$anchor.Height }

        $rows += [pscustomobject]@{
            Anchor = $anchor
            Items = $rowItems
            BaseHeight = $baseHeight
        }

        $remaining = @($nextRemaining | Sort-Object Y, X)
    }

    return @($rows)
}

function Get-RowPackPbiLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Analysis,
        [ValidateRange(0,500)][double]$Margin = 5,
        [ValidateRange(0,500)][double]$Gap = 5,
        [ValidateRange(0.50,1.00)][double]$RowOverlapThreshold = 0.80,
        [ValidateRange(1.00,3.00)][double]$SmallRowGrowthCap = 1.40
    )

    $managed = @($Analysis.Items | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked)
    })
    $locked = @($Analysis.Items | Where-Object {
        $_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked
    })

    if ($managed.Count -eq 0) {
        throw 'No active visible visuals are available for alignment.'
    }

    $contentLeft = if ([double]$Analysis.ReservedLeft -gt 0) { [double]$Analysis.ReservedLeft + $Gap } else { $Margin }
    $contentTop = if ([double]$Analysis.ReservedTop -gt 0) { [double]$Analysis.ReservedTop + $Gap } else { $Margin }
    $contentRight = if ([double]$Analysis.ReservedRight -lt [double]$Analysis.PageWidth) { [double]$Analysis.ReservedRight - $Gap } else { [double]$Analysis.PageWidth - $Margin }
    $contentBottom = if ([double]$Analysis.ReservedBottom -lt [double]$Analysis.PageHeight) { [double]$Analysis.ReservedBottom - $Gap } else { [double]$Analysis.PageHeight - $Margin }

    $contentWidth = $contentRight - $contentLeft
    $contentHeight = $contentBottom - $contentTop
    if ($contentWidth -le 0 -or $contentHeight -le 0) {
        throw 'No usable page area remains after margin and protected regions are applied.'
    }

    $rows = @(Get-AlignmentRowGroups -Items $managed -RowOverlapThreshold $RowOverlapThreshold)
    if ($rows.Count -eq 0) { throw 'No visual rows could be detected.' }

    # --------------------------
    # Vertical row sizing
    # --------------------------
    $verticalGapTotal = [Math]::Max(0,($rows.Count - 1)) * $Gap
    $usableForRows = $contentHeight - $verticalGapTotal
    if ($usableForRows -le 0) {
        throw 'Configured gap leaves no usable height for detected rows.'
    }

    $baseHeights = @($rows | ForEach-Object { [double]$_.BaseHeight })
    $baseHeightTotal = [double](($baseHeights | Measure-Object -Sum).Sum)
    if ($baseHeightTotal -le 0) { throw 'Detected rows do not have valid heights.' }

    $requestedScale = $usableForRows / $baseHeightTotal
    $cappedScale = if ($requestedScale -gt $SmallRowGrowthCap) { $SmallRowGrowthCap } else { $requestedScale }
    $rowHeights = @()
    foreach ($height in $baseHeights) {
        $rowHeights += [Math]::Max(1.0,([double]$height * $cappedScale))
    }

    # If the page is taller than the capped row stack, keep card-like rows
    # capped and let the largest row/chart absorb the remaining space. This
    # keeps the bottom margin exact without making every small card too tall.
    $usedHeight = [double](($rowHeights | Measure-Object -Sum).Sum)
    $remainingHeight = $usableForRows - $usedHeight
    $largestRowIndex = 0
    $largestBaseHeight = -1.0
    for ($i = 0; $i -lt $baseHeights.Count; $i++) {
        if ([double]$baseHeights[$i] -gt $largestBaseHeight) {
            $largestBaseHeight = [double]$baseHeights[$i]
            $largestRowIndex = $i
        }
    }
    if ($remainingHeight -gt 0.001) {
        $rowHeights[$largestRowIndex] = [double]$rowHeights[$largestRowIndex] + $remainingHeight
    }

    # --------------------------
    # Horizontal row sizing
    # --------------------------
    # Every row fills exactly from left margin to right margin. The original
    # width percentage of visuals inside that row is preserved; only the gap
    # total is removed before proportional distribution.
    $proposed = @()
    $cursorY = $contentTop
    $maxColumns = 0

    for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
        $row = $rows[$rowIndex]
        $rowItems = @($row.Items | Sort-Object X)
        $maxColumns = [Math]::Max($maxColumns,$rowItems.Count)

        $horizontalGapTotal = [Math]::Max(0,($rowItems.Count - 1)) * $Gap
        $usableForVisuals = $contentWidth - $horizontalGapTotal
        if ($usableForVisuals -le 0) {
            throw ('Configured gap leaves no usable width for row ' + ($rowIndex + 1) + '.')
        }

        $originalWidthTotal = [double](($rowItems | Measure-Object -Property Width -Sum).Sum)
        if ($originalWidthTotal -le 0) {
            throw ('Detected row ' + ($rowIndex + 1) + ' does not have valid widths.')
        }

        $cursorX = $contentLeft
        $rowHeight = [double]$rowHeights[$rowIndex]

        for ($columnIndex = 0; $columnIndex -lt $rowItems.Count; $columnIndex++) {
            $item = $rowItems[$columnIndex]
            $share = [double]$item.Width / $originalWidthTotal
            $targetWidth = $usableForVisuals * $share

            # Force the final visual to end exactly at the right content edge.
            # This removes floating-point rounding and guarantees only Margin
            # remains after the final visual.
            if ($columnIndex -eq ($rowItems.Count - 1)) {
                $targetWidth = $contentRight - $cursorX
            }

            $proposed += New-AlignmentProposedItem -Item $item -X $cursorX -Y $cursorY -Width $targetWidth -Height $rowHeight -Column $columnIndex -Row $rowIndex
            $cursorX += $targetWidth + $Gap
        }

        $cursorY += $rowHeight + $Gap
    }

    foreach ($item in $locked) {
        $proposed += New-AlignmentProposedItem -Item $item -X ([double]$item.X) -Y ([double]$item.Y) -Width ([double]$item.Width) -Height ([double]$item.Height) -IsLocked $true -Column 0 -Row 0
    }

    [pscustomobject]@{
        PageWidth = [double]$Analysis.PageWidth
        PageHeight = [double]$Analysis.PageHeight
        Margin = $Margin
        Gap = $Gap
        ContentLeft = [Math]::Round($contentLeft,3)
        ContentTop = [Math]::Round($contentTop,3)
        ContentRight = [Math]::Round($contentRight,3)
        ContentBottom = [Math]::Round($contentBottom,3)
        Columns = $maxColumns
        Rows = $rows.Count
        LayoutStrategy = 'Row Pack Align'
        FirstRowVisualCount = @($rows[0].Items).Count
        RowOverlapThreshold = $RowOverlapThreshold
        SmallRowGrowthCap = $SmallRowGrowthCap
        WidthScaledToFill = $true
        MaxAreaShareDeltaPercent = $null
        Items = $proposed
        ChangedCount = @($proposed | Where-Object { $_.Changed }).Count
    }
}

function Invoke-AlignmentPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$PageSnapshot,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][double]$Margin,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    $initialAnalysis = Get-PbiLayoutAnalysis -PageSnapshot $PageSnapshot `
        -MinimumTolerance ([double]$Config.layout.minimumTolerance) `
        -MaximumTolerance ([double]$Config.layout.maximumTolerance)

    $analysis = $initialAnalysis
    $overlapNormalization = [pscustomobject]@{
        Snapshot = $PageSnapshot
        HadOverlaps = $false
        InitialOverlapPairCount = 0
        RemainingOverlapPairCount = 0
        MovedCount = 0
        ResizedCount = 0
        Resolved = $true
        UsedCompactFallback = $false
        DiagnosticOnly = $true
        Actions = @()
    }

    # Overlap pre-pass: use it only when it can fix the problem with one simple
    # move and no resize. A cascade/compact rewrite is rejected because the row
    # packer itself will cleanly rebuild the visible layout.
    try {
        $diagnostic = Resolve-PbiSnapshotOverlaps -PageSnapshot $PageSnapshot -InitialAnalysis $initialAnalysis -Margin $Margin -Gap $Gap

        $safeMinimalFix = (
            [bool]$diagnostic.HadOverlaps -and
            [int]$diagnostic.MovedCount -le 1 -and
            [int]$diagnostic.ResizedCount -eq 0 -and
            [int]$diagnostic.RemainingOverlapPairCount -eq 0 -and
            -not [bool]$diagnostic.UsedCompactFallback
        )

        if ($safeMinimalFix) {
            $analysis = Get-PbiLayoutAnalysis -PageSnapshot $diagnostic.Snapshot `
                -MinimumTolerance ([double]$Config.layout.minimumTolerance) `
                -MaximumTolerance ([double]$Config.layout.maximumTolerance)
            $overlapNormalization = $diagnostic
        }
        else {
            $overlapNormalization = [pscustomobject]@{
                Snapshot = $PageSnapshot
                HadOverlaps = [bool]$diagnostic.HadOverlaps
                InitialOverlapPairCount = [int]$diagnostic.InitialOverlapPairCount
                RemainingOverlapPairCount = [int]$diagnostic.RemainingOverlapPairCount
                MovedCount = 0
                ResizedCount = 0
                Resolved = $true
                UsedCompactFallback = $false
                DiagnosticOnly = $true
                Actions = @()
            }
        }
    }
    catch {
        # Diagnostic failure must never block the deterministic row-pack pass.
    }

    $layout = Get-RowPackPbiLayout -Analysis $analysis -Margin $Margin -Gap $Gap -RowOverlapThreshold 0.80 -SmallRowGrowthCap 1.40
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
