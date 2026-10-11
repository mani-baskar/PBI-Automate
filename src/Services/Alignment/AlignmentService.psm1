Set-StrictMode -Version 2.0

function Get-FirstRowVerticalOverlapRatio {
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
    $baseHeight = [Math]::Min([double]$Anchor.Height,[double]$Candidate.Height)

    if ($baseHeight -le 0) { return 0.0 }
    return ($overlap / $baseHeight)
}

function Test-FirstRowRectOverlap {
    param(
        [Parameter(Mandatory=$true)][double]$X,
        [Parameter(Mandatory=$true)][double]$Y,
        [Parameter(Mandatory=$true)][double]$Width,
        [Parameter(Mandatory=$true)][double]$Height,
        [Parameter(Mandatory=$true)]$Other
    )

    return (
        $X -lt ([double]$Other.X + [double]$Other.Width) -and
        ($X + $Width) -gt [double]$Other.X -and
        $Y -lt ([double]$Other.Y + [double]$Other.Height) -and
        ($Y + $Height) -gt [double]$Other.Y
    )
}

function New-FirstRowProposedItem {
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

function Get-FirstRowPbiLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Analysis,
        [ValidateRange(0,500)][double]$Margin = 5,
        [ValidateRange(0,500)][double]$Gap = 5,
        [ValidateRange(0.50,1.00)][double]$RowOverlapThreshold = 0.80
    )

    $managed = @($Analysis.Items | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked)
    })
    $locked = @($Analysis.Items | Where-Object {
        $_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked
    })

    if ($managed.Count -eq 0) {
        throw 'No active visible visuals are available for first-row alignment.'
    }

    $contentLeft = if ([double]$Analysis.ReservedLeft -gt 0) { [double]$Analysis.ReservedLeft + $Gap } else { $Margin }
    $contentTop = if ([double]$Analysis.ReservedTop -gt 0) { [double]$Analysis.ReservedTop + $Gap } else { $Margin }
    $contentRight = if ([double]$Analysis.ReservedRight -lt [double]$Analysis.PageWidth) { [double]$Analysis.ReservedRight - $Gap } else { [double]$Analysis.PageWidth - $Margin }
    $contentBottom = if ([double]$Analysis.ReservedBottom -lt [double]$Analysis.PageHeight) { [double]$Analysis.ReservedBottom - $Gap } else { [double]$Analysis.PageHeight - $Margin }

    if ($contentRight -le $contentLeft -or $contentBottom -le $contentTop) {
        throw 'No usable page area remains after margin and protected regions are applied.'
    }

    $anchor = @($managed | Sort-Object Y, X)[0]

    $rowItems = @()
    foreach ($item in $managed) {
        $ratio = Get-FirstRowVerticalOverlapRatio -Anchor $anchor -Candidate $item
        if ($item.Id -eq $anchor.Id -or $ratio -ge $RowOverlapThreshold) {
            $rowItems += $item
        }
    }
    $rowItems = @($rowItems | Sort-Object X)

    $rowIds = @{}
    foreach ($item in $rowItems) { $rowIds[[string]$item.Id] = $true }

    $nonRowItems = @($managed | Where-Object { -not $rowIds.ContainsKey([string]$_.Id) })

    $rowStartX = [Math]::Max($contentLeft,[double]$anchor.X)
    $rowY = [Math]::Max($contentTop,[double]$anchor.Y)
    $availableWidth = $contentRight - $rowStartX
    if ($availableWidth -le 0) { throw 'The first-row anchor is outside the usable page width.' }

    $widths = @($rowItems | ForEach-Object { [double]$_.Width })
    $originalWidthTotal = [double](($widths | Measure-Object -Sum).Sum)
    $gapTotal = [Math]::Max(0,($rowItems.Count - 1)) * $Gap
    $usableForVisuals = $availableWidth - $gapTotal

    if ($usableForVisuals -le 0) {
        throw 'Configured gap leaves no usable width for the detected first row.'
    }

    $widthScaled = $false

    if ($rowItems.Count -eq 1) {
        $coverage = [double]$anchor.Width / [Math]::Max(1.0,$availableWidth)
        if ($coverage -ge 0.90) {
            $widths = @($availableWidth)
            $rowStartX = $contentLeft
            $widthScaled = $true
        }
        elseif ([double]$anchor.Width -gt $availableWidth) {
            $widths = @($availableWidth)
            $widthScaled = $true
        }
    }
    elseif ($originalWidthTotal -gt $usableForVisuals) {
        $widthScaled = $true
        $scaledWidths = @()
        foreach ($width in $widths) {
            $share = if ($originalWidthTotal -gt 0) { [double]$width / $originalWidthTotal } else { 1.0 / $rowItems.Count }
            $scaledWidths += ($usableForVisuals * $share)
        }
        $widths = $scaledWidths
    }

    $proposed = @()
    $cursorX = $rowStartX
    $rowOverlapFixCount = 0
    $obstaclePushCount = 0

    for ($i = 0; $i -lt $rowItems.Count; $i++) {
        $item = $rowItems[$i]
        $targetWidth = [double]$widths[$i]
        $targetX = $cursorX

        if ($i -gt 0 -and [double]$item.X -lt ($targetX - 0.001)) {
            $rowOverlapFixCount++
        }

        # Keep the first visual as the primary anchor. For every later row
        # visual, if the desired position collides with an unchanged lower-row
        # visual, push only this row visual to the obstacle's right edge + Gap.
        if ($i -gt 0) {
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                $blockingRight = $null

                foreach ($obstacle in $nonRowItems) {
                    if (Test-FirstRowRectOverlap -X $targetX -Y $rowY -Width $targetWidth -Height ([double]$item.Height) -Other $obstacle) {
                        $candidateRight = [double]$obstacle.X + [double]$obstacle.Width + $Gap
                        if ($null -eq $blockingRight -or $candidateRight -gt [double]$blockingRight) {
                            $blockingRight = $candidateRight
                        }
                    }
                }

                if ($null -eq $blockingRight) { break }
                if ([double]$blockingRight -le ($targetX + 0.001)) { break }

                $targetX = [double]$blockingRight
                $obstaclePushCount++
            }
        }

        # If obstacle pushing would exceed the right margin, fall back to the
        # visual's current X when it is still inside the page. Validation will
        # block Apply rather than silently create a bad layout.
        if (($targetX + $targetWidth) -gt $contentRight) {
            $originalX = [Math]::Max($contentLeft,[double]$item.X)
            if (($originalX + $targetWidth) -le $contentRight) {
                $targetX = $originalX
            }
        }

        $proposed += New-FirstRowProposedItem -Item $item -X $targetX -Y $rowY -Width $targetWidth -Height ([double]$item.Height) -Column $i -Row 0
        $cursorX = $targetX + $targetWidth + $Gap
    }

    foreach ($item in $nonRowItems) {
        $proposed += New-FirstRowProposedItem -Item $item -X ([double]$item.X) -Y ([double]$item.Y) -Width ([double]$item.Width) -Height ([double]$item.Height) -Column ([int]$item.Column) -Row ([int]$item.Row)
    }

    foreach ($item in $locked) {
        $proposed += New-FirstRowProposedItem -Item $item -X ([double]$item.X) -Y ([double]$item.Y) -Width ([double]$item.Width) -Height ([double]$item.Height) -IsLocked $true -Column 0 -Row 0
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
        Columns = $rowItems.Count
        Rows = 1
        LayoutStrategy = 'First Row Align'
        FirstRowVisualCount = $rowItems.Count
        RowOverlapThreshold = $RowOverlapThreshold
        RowOverlapFixCount = $rowOverlapFixCount
        ObstaclePushCount = $obstaclePushCount
        WidthScaledToFit = $widthScaled
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
                HadOverlaps = $false
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
        # Diagnostic failure must never block the interview-safe first-row pass.
    }

    $layout = Get-FirstRowPbiLayout -Analysis $analysis -Margin $Margin -Gap $Gap -RowOverlapThreshold 0.80
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
