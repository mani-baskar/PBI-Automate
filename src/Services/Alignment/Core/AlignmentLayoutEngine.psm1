Set-StrictMode -Version 2.0

function Get-AnalysisNumber {
    param(
        [Parameter(Mandatory=$true)]$Analysis,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][double]$Default
    )

    if ($Analysis.PSObject.Properties.Name -contains $Name) {
        return [double]$Analysis.$Name
    }

    return $Default
}

function Get-AnalysisArray {
    param(
        [Parameter(Mandatory=$true)]$Analysis,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($Analysis.PSObject.Properties.Name -contains $Name) {
        return @($Analysis.$Name)
    }

    return @()
}

function Get-ItemArea {
    param([Parameter(Mandatory=$true)]$Item)
    return [Math]::Max(1.0,([double]$Item.Width * [double]$Item.Height))
}

function Get-AreaSum {
    param([object[]]$Items)

    $sum = 0.0
    foreach ($item in @($Items)) {
        $sum += Get-ItemArea -Item $item
    }

    return $sum
}

function Get-MedianNumber {
    param([double[]]$Values)

    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return 0.0 }

    $mid = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$mid] }

    return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2.0
}

function Test-NearAnchorDimension {
    param(
        [Parameter(Mandatory=$true)][double]$Value,
        [Parameter(Mandatory=$true)][double]$Anchor,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    if ($Value -le 0 -or $Anchor -le 0) { return $false }

    # A small existing difference is treated as accidental manual drift.
    # The primary top/left anchor wins instead of moving an already-good edge.
    $threshold = [Math]::Max(($Gap * 2.0),($Anchor * 0.12))
    return ([Math]::Abs($Value - $Anchor) -le $threshold)
}

function Get-ProportionalLengths {
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [Parameter(Mandatory=$true)][double]$TotalLength,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    if ($Items.Count -eq 0) { return @() }

    $usable = $TotalLength - (($Items.Count - 1) * $Gap)
    if ($usable -le 0) {
        throw 'Configured gap leaves no usable room for a visual band.'
    }

    $areas = @($Items | ForEach-Object { Get-ItemArea -Item $_ })
    $areaSum = [double](($areas | Measure-Object -Sum).Sum)
    if ($areaSum -le 0) { $areaSum = [double]$Items.Count }

    $lengths = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $weight = [double]$areas[$i] / $areaSum
        $lengths += [double]($usable * $weight)
    }

    return @($lengths)
}

function New-ProposedItem {
    param(
        [Parameter(Mandatory=$true)]$Item,
        [Parameter(Mandatory=$true)][double]$X,
        [Parameter(Mandatory=$true)][double]$Y,
        [Parameter(Mandatory=$true)][double]$Width,
        [Parameter(Mandatory=$true)][double]$Height,
        [Parameter(Mandatory=$true)][int]$Column,
        [Parameter(Mandatory=$true)][int]$Row,
        [Parameter(Mandatory=$true)][int]$ColumnSpan,
        [Parameter(Mandatory=$true)][int]$RowSpan,
        [bool]$IsLocked = $false,
        [bool]$AllowOverlap = $false,
        $ProtectionReason = $null
    )

    $oldX = $(if ($Item.PSObject.Properties.Name -contains 'OriginalX') { [double]$Item.OriginalX } else { [double]$Item.X })
    $oldY = $(if ($Item.PSObject.Properties.Name -contains 'OriginalY') { [double]$Item.OriginalY } else { [double]$Item.Y })
    $oldWidth = $(if ($Item.PSObject.Properties.Name -contains 'OriginalWidth') { [double]$Item.OriginalWidth } else { [double]$Item.Width })
    $oldHeight = $(if ($Item.PSObject.Properties.Name -contains 'OriginalHeight') { [double]$Item.OriginalHeight } else { [double]$Item.Height })

    $oldArea = $oldWidth * $oldHeight
    $newArea = $Width * $Height
    $areaChangePercent = 0.0

    if ($oldArea -gt 0) {
        $areaChangePercent = (($newArea - $oldArea) / $oldArea) * 100.0
    }

    [pscustomobject]@{
        Id = $Item.Id
        VisualType = $Item.VisualType
        FilePath = $Item.FilePath
        SourceHash = $Item.SourceHash
        ParentGroupName = $Item.ParentGroupName
        IsVisualGroup = $Item.IsVisualGroup
        IsHidden = $Item.IsHidden
        EffectiveHidden = $(if ($Item.PSObject.Properties.Name -contains 'EffectiveHidden') { [bool]$Item.EffectiveHidden } else { [bool]$Item.IsHidden })
        ProtectionReason = $ProtectionReason
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
        ColumnSpan = $ColumnSpan
        RowSpan = $RowSpan
        IsLocked = $IsLocked
        AllowOverlap = $AllowOverlap
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

function Get-AreaPreservingPbiLayout {
    param(
        [Parameter(Mandatory=$true)]$Analysis,
        [Parameter(Mandatory=$true)][double]$ContentLeft,
        [Parameter(Mandatory=$true)][double]$ContentTop,
        [Parameter(Mandatory=$true)][double]$ContentRight,
        [Parameter(Mandatory=$true)][double]$ContentBottom,
        [Parameter(Mandatory=$true)][double]$Gap,
        [Parameter(Mandatory=$true)][double]$Margin
    )

    $managed = @($Analysis.Items | Where-Object { -not ($_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked) })
    $locked = @($Analysis.Items | Where-Object { $_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked })

    if ($managed.Count -eq 0) {
        throw 'No managed visuals are available for Smart Align.'
    }

    $contentWidth = $ContentRight - $ContentLeft
    $contentHeight = $ContentBottom - $ContentTop
    if ($contentWidth -le 0 -or $contentHeight -le 0) {
        throw 'No usable content rectangle is available for Smart Align.'
    }

    $minRow = [int](($managed | Measure-Object -Property Row -Minimum).Minimum)
    $topItems = @($managed | Where-Object { [int]$_.Row -eq $minRow } | Sort-Object X)
    $lowerItems = @($managed | Where-Object { [int]$_.Row -gt $minRow })

    if (@($topItems | Where-Object { [int]$_.RowSpan -gt 1 }).Count -gt 0) {
        return $null
    }

    $totalManagedArea = Get-AreaSum -Items $managed
    $topArea = Get-AreaSum -Items $topItems

    $topHeight = $contentHeight

    if ($lowerItems.Count -gt 0) {
        $verticalUsable = $contentHeight - $Gap
        if ($verticalUsable -le 0) { return $null }

        $topRatio = if ($totalManagedArea -gt 0) { $topArea / $totalManagedArea } else { 0.20 }
        $topHeight = $verticalUsable * $topRatio

        $topOriginalMedianHeight = Get-MedianNumber -Values ([double[]]@($topItems | ForEach-Object { $_.Height }))
        if ($topOriginalMedianHeight -gt 0) {
            $topHeight = [Math]::Max($topHeight,[Math]::Min($verticalUsable * 0.35,$topOriginalMedianHeight))
        }

        $topHeight = [Math]::Min($topHeight,$verticalUsable * 0.45)
        $topHeight = [Math]::Max(24.0,$topHeight)
    }

    $proposed = @()
    $verticalAnchorSnapCount = 0

    # Top horizontal band: same Y and height, exact gaps, widths proportional
    # to the original occupied area.
    $topWidths = @(Get-ProportionalLengths -Items $topItems -TotalLength $contentWidth -Gap $Gap)
    $cursorX = $ContentLeft

    for ($i = 0; $i -lt $topItems.Count; $i++) {
        $item = $topItems[$i]
        $width = [double]$topWidths[$i]
        $proposed += New-ProposedItem -Item $item -X $cursorX -Y $ContentTop -Width $width -Height $topHeight -Column ([int]$item.Column) -Row ([int]$item.Row) -ColumnSpan ([int]$item.ColumnSpan) -RowSpan 1
        $cursorX += $width + $Gap
    }

    if ($lowerItems.Count -gt 0) {
        $belowTop = $ContentTop + $topHeight + $Gap
        $belowHeight = $ContentBottom - $belowTop
        if ($belowHeight -le 0) { return $null }

        $minLowerColumn = [int](($lowerItems | Measure-Object -Property Column -Minimum).Minimum)
        $leftItems = @($lowerItems | Where-Object { [int]$_.Column -eq $minLowerColumn } | Sort-Object Y)
        $mainItems = @($lowerItems | Where-Object { [int]$_.Column -gt $minLowerColumn })

        if ($mainItems.Count -eq 0) {
            $leftHeights = @(Get-ProportionalLengths -Items $leftItems -TotalLength $belowHeight -Gap $Gap)
            $leftHeightAnchors = @{}
            $cursorY = $belowTop

            for ($i = 0; $i -lt $leftItems.Count; $i++) {
                $item = $leftItems[$i]
                $height = [double]$leftHeights[$i]
                $proposed += New-ProposedItem -Item $item -X $ContentLeft -Y $cursorY -Width $contentWidth -Height $height -Column ([int]$item.Column) -Row ([int]$item.Row) -ColumnSpan ([int]$item.ColumnSpan) -RowSpan ([int]$item.RowSpan)
                $cursorY += $height + $Gap
            }
        }
        else {
            # Left stack: one aligned X/Width, exact vertical gaps, original
            # area proportions decide each visual's height.
            $leftArea = Get-AreaSum -Items $leftItems
            $mainArea = Get-AreaSum -Items $mainItems
            $belowArea = $leftArea + $mainArea
            $horizontalUsable = $contentWidth - $Gap
            if ($horizontalUsable -le 0) { return $null }

            $leftRatio = if ($belowArea -gt 0) { $leftArea / $belowArea } else { 0.20 }
            $leftWidth = $horizontalUsable * $leftRatio

            $leftOriginalMedianWidth = Get-MedianNumber -Values ([double[]]@($leftItems | ForEach-Object { $_.Width }))
            $topLeftOriginalWidth = if ($topItems.Count -gt 0) { [double]$topItems[0].Width } else { 0.0 }
            $topLeftProposedWidth = if ($topWidths.Count -gt 0) { [double]$topWidths[0] } else { 0.0 }
            $leftWidthAnchoredToTop = $false

            if ($leftOriginalMedianWidth -gt 0 -and $topLeftOriginalWidth -gt 0 -and
                (Test-NearAnchorDimension -Value $leftOriginalMedianWidth -Anchor $topLeftOriginalWidth -Gap $Gap)) {
                # Top is the primary horizontal anchor. If the left stack was
                # already almost the same width, preserve that alignment exactly
                # and let the inner content absorb the remaining width.
                $leftWidth = $topLeftProposedWidth
                $leftWidthAnchoredToTop = $true
            }
            elseif ($leftOriginalMedianWidth -gt 0) {
                $leftWidth = [Math]::Max($leftWidth,[Math]::Min($horizontalUsable * 0.40,$leftOriginalMedianWidth))
            }

            $leftWidth = [Math]::Min($leftWidth,$horizontalUsable * 0.45)
            $leftWidth = [Math]::Max(30.0,$leftWidth)

            $mainLeft = $ContentLeft + $leftWidth + $Gap
            $mainWidth = $ContentRight - $mainLeft
            if ($mainWidth -le 0) { return $null }

            $leftHeights = @(Get-ProportionalLengths -Items $leftItems -TotalLength $belowHeight -Gap $Gap)
            $leftHeightAnchors = @{}
            $cursorY = $belowTop

            for ($i = 0; $i -lt $leftItems.Count; $i++) {
                $item = $leftItems[$i]
                $height = [double]$leftHeights[$i]
                $proposed += New-ProposedItem -Item $item -X $ContentLeft -Y $cursorY -Width $leftWidth -Height $height -Column ([int]$item.Column) -Row ([int]$item.Row) -ColumnSpan 1 -RowSpan ([int]$item.RowSpan)

                if ([int]$item.RowSpan -eq 1) {
                    $leftHeightAnchors[[string][int]$item.Row] = [pscustomobject]@{
                        OriginalHeight = [double]$item.Height
                        ProposedHeight = [double]$height
                    }
                }

                $cursorY += $height + $Gap
            }

            # Inner content: preserve original row order. Row height demand comes
            # from original area / usable row width. Inside each row, widths are
            # proportional to original area, so a small visual stays small and a
            # dominant visual stays dominant without overlap.
            $rowNumbers = @($mainItems | Select-Object -ExpandProperty Row -Unique | Sort-Object)
            $rowGroups = @()

            foreach ($rowNumber in $rowNumbers) {
                $rowItems = @($mainItems | Where-Object { [int]$_.Row -eq [int]$rowNumber } | Sort-Object X)

                if (@($rowItems | Where-Object { [int]$_.RowSpan -gt 1 }).Count -gt 0) {
                    return $null
                }

                $rowArea = Get-AreaSum -Items $rowItems
                $rowUsableWidth = $mainWidth - (($rowItems.Count - 1) * $Gap)
                if ($rowUsableWidth -le 0) { return $null }

                $rowOriginalMedianHeight = Get-MedianNumber -Values ([double[]]@($rowItems | ForEach-Object { $_.Height }))
                $anchorHeight = $null
                $rowKey = [string][int]$rowNumber

                if ($leftHeightAnchors.ContainsKey($rowKey)) {
                    $leftAnchor = $leftHeightAnchors[$rowKey]
                    if (Test-NearAnchorDimension -Value $rowOriginalMedianHeight -Anchor ([double]$leftAnchor.OriginalHeight) -Gap $Gap) {
                        $anchorHeight = [double]$leftAnchor.ProposedHeight
                    }
                }

                $rowGroups += [pscustomobject]@{
                    Row = [int]$rowNumber
                    Items = $rowItems
                    Area = $rowArea
                    UsableWidth = $rowUsableWidth
                    DemandHeight = [Math]::Max(1.0,($rowArea / $rowUsableWidth))
                    AnchorHeight = $anchorHeight
                }
            }

            $mainUsableHeight = $belowHeight - (($rowGroups.Count - 1) * $Gap)
            if ($mainUsableHeight -le 0) { return $null }

            $anchoredHeightTotal = 0.0
            $flexDemandTotal = 0.0
            foreach ($rowGroup in $rowGroups) {
                if ($null -ne $rowGroup.AnchorHeight) {
                    $anchoredHeightTotal += [double]$rowGroup.AnchorHeight
                }
                else {
                    $flexDemandTotal += [double]$rowGroup.DemandHeight
                }
            }

            # If the primary-left height anchors cannot fit, fall back to
            # proportional heights rather than force an invalid layout.
            $useHeightAnchors = ($anchoredHeightTotal -le ($mainUsableHeight + 0.01))
            if (-not $useHeightAnchors) {
                $anchoredHeightTotal = 0.0
                $flexDemandTotal = [double](($rowGroups | Measure-Object -Property DemandHeight -Sum).Sum)
            }

            if ($flexDemandTotal -le 0 -and $anchoredHeightTotal -le 0) { return $null }

            $remainingHeight = $mainUsableHeight - $anchoredHeightTotal
            $cursorY = $belowTop

            foreach ($rowGroup in $rowGroups) {
                $rowHeight = 0.0

                if ($useHeightAnchors -and $null -ne $rowGroup.AnchorHeight) {
                    $rowHeight = [double]$rowGroup.AnchorHeight
                    $verticalAnchorSnapCount++
                }
                elseif ($flexDemandTotal -gt 0) {
                    $rowHeight = $remainingHeight * ([double]$rowGroup.DemandHeight / $flexDemandTotal)
                }
                else {
                    $rowHeight = $remainingHeight / [Math]::Max(1,$rowGroups.Count)
                }

                $rowItems = @($rowGroup.Items)
                $rowWidths = @(Get-ProportionalLengths -Items $rowItems -TotalLength $mainWidth -Gap $Gap)
                $cursorX = $mainLeft

                for ($i = 0; $i -lt $rowItems.Count; $i++) {
                    $item = $rowItems[$i]
                    $width = [double]$rowWidths[$i]
                    $proposed += New-ProposedItem -Item $item -X $cursorX -Y $cursorY -Width $width -Height $rowHeight -Column ([int]$item.Column) -Row ([int]$item.Row) -ColumnSpan ([int]$item.ColumnSpan) -RowSpan 1
                    $cursorX += $width + $Gap
                }

                $cursorY += $rowHeight + $Gap
            }
        }
    }

    foreach ($item in $locked) {
        $reason = $null
        if ($item.PSObject.Properties.Name -contains 'ProtectionReason') { $reason = $item.ProtectionReason }
        $proposed += New-ProposedItem -Item $item -X ([double]$item.X) -Y ([double]$item.Y) -Width ([double]$item.Width) -Height ([double]$item.Height) -Column 0 -Row 0 -ColumnSpan 1 -RowSpan 1 -IsLocked $true -AllowOverlap ([bool]$item.AllowOverlap) -ProtectionReason $reason
    }

    $originalAreaTotal = Get-AreaSum -Items $managed
    $proposedManaged = @($proposed | Where-Object { -not $_.IsLocked })
    $proposedAreaTotal = 0.0
    foreach ($item in $proposedManaged) { $proposedAreaTotal += [double]$item.Width * [double]$item.Height }

    $maxShareDelta = 0.0
    if ($originalAreaTotal -gt 0 -and $proposedAreaTotal -gt 0) {
        foreach ($item in $proposedManaged) {
            $originalShare = ([double]$item.OldWidth * [double]$item.OldHeight) / $originalAreaTotal
            $newShare = ([double]$item.Width * [double]$item.Height) / $proposedAreaTotal
            $delta = [Math]::Abs($newShare - $originalShare) * 100.0
            $maxShareDelta = [Math]::Max($maxShareDelta,$delta)
        }
    }

    [pscustomobject]@{
        PageWidth = [double]$Analysis.PageWidth
        PageHeight = [double]$Analysis.PageHeight
        Margin = $Margin
        Gap = $Gap
        ContentLeft = [Math]::Round($ContentLeft,3)
        ContentTop = [Math]::Round($ContentTop,3)
        ContentRight = [Math]::Round($ContentRight,3)
        ContentBottom = [Math]::Round($ContentBottom,3)
        Columns = [int]$Analysis.ColumnCount
        Rows = [int]$Analysis.RowCount
        LayoutStrategy = 'Area Preserve'
        AnchorSnapUsed = [bool]($null -ne (Get-Variable -Name leftWidthAnchoredToTop -Scope 0 -ErrorAction SilentlyContinue) -and $leftWidthAnchoredToTop)
        VerticalAnchorSnapCount = [int]$verticalAnchorSnapCount
        MaxAreaShareDeltaPercent = [Math]::Round($maxShareDelta,2)
        Items = $proposed
        ChangedCount = @($proposed | Where-Object { $_.Changed }).Count
    }
}

function Get-CappedProportionalLengths {
    param(
        [Parameter(Mandatory=$true)][double[]]$SourceLengths,
        [Parameter(Mandatory=$true)][double]$TotalLength,
        [Parameter(Mandatory=$true)][double]$Gap,
        [double]$MaxGrowth = 1.40
    )

    if ($SourceLengths.Count -eq 0) { return @() }

    $usable = $TotalLength - (($SourceLengths.Count - 1) * $Gap)
    if ($usable -le 0) { return @() }

    $sourceTotal = [double](($SourceLengths | Measure-Object -Sum).Sum)
    if ($sourceTotal -le 0) { return @() }

    $scale = $usable / $sourceTotal
    if ($scale -gt $MaxGrowth) { $scale = $MaxGrowth }

    $result = @()
    foreach ($length in $SourceLengths) {
        $result += [Math]::Max(1.0,([double]$length * $scale))
    }
    return @($result)
}

function Get-AnchorIndex {
    param(
        [Parameter(Mandatory=$true)][double]$Value,
        [Parameter(Mandatory=$true)][double[]]$Starts
    )

    if ($Starts.Count -eq 0) { return 0 }
    $best = 0
    $bestDistance = [double]::MaxValue
    for ($i = 0; $i -lt $Starts.Count; $i++) {
        $distance = [Math]::Abs($Value - [double]$Starts[$i])
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $best = $i
        }
    }
    return $best
}

function Get-AnchorSpan {
    param(
        [Parameter(Mandatory=$true)][int]$StartIndex,
        [Parameter(Mandatory=$true)][double]$EndCoordinate,
        [Parameter(Mandatory=$true)][double[]]$Starts,
        [Parameter(Mandatory=$true)][double]$Slack
    )

    if ($Starts.Count -eq 0) { return 1 }
    $span = 1
    for ($i = $StartIndex + 1; $i -lt $Starts.Count; $i++) {
        if ([double]$Starts[$i] -lt ($EndCoordinate - $Slack)) { $span++ } else { break }
    }
    return [Math]::Max(1,$span)
}

function Get-FrameAnchoredPbiLayout {
    param(
        [Parameter(Mandatory=$true)]$Analysis,
        [Parameter(Mandatory=$true)][double]$ContentLeft,
        [Parameter(Mandatory=$true)][double]$ContentTop,
        [Parameter(Mandatory=$true)][double]$ContentRight,
        [Parameter(Mandatory=$true)][double]$ContentBottom,
        [Parameter(Mandatory=$true)][double]$Gap,
        [Parameter(Mandatory=$true)][double]$Margin
    )

    $managed = @($Analysis.Items | Where-Object { -not ($_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked) })
    $locked = @($Analysis.Items | Where-Object { $_.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$_.IsLocked })
    if ($managed.Count -lt 2) { return $null }

    $medianHeight = Get-MedianNumber -Values ([double[]]@($managed | ForEach-Object { $_.Height }))
    $topY = [double](($managed | Measure-Object -Property Y -Minimum).Minimum)
    $topTolerance = [Math]::Max(($Gap * 2.0),($medianHeight * 0.35))
    $topCandidates = @($managed | Where-Object { [Math]::Abs([double]$_.Y - $topY) -le $topTolerance } | Sort-Object X)
    if ($topCandidates.Count -lt 2) { return $null }

    $topMedianHeight = Get-MedianNumber -Values ([double[]]@($topCandidates | ForEach-Object { $_.Height }))
    $topItems = @($topCandidates | Where-Object { [double]$_.Height -le ([Math]::Max(1.0,$topMedianHeight) * 2.0) } | Sort-Object X)
    if ($topItems.Count -lt 2) { return $null }

    $contentWidth = $ContentRight - $ContentLeft
    $contentHeight = $ContentBottom - $ContentTop
    if ($contentWidth -le 0 -or $contentHeight -le 0) { return $null }

    # TOP is the primary horizontal anchor. Preserve original width ratios and
    # spend only the configured gaps between them.
    $topSourceWidths = [double[]]@($topItems | ForEach-Object { [double]$_.Width })
    $topUsableWidth = $contentWidth - (($topItems.Count - 1) * $Gap)
    if ($topUsableWidth -le 0) { return $null }
    $topSourceTotal = [double](($topSourceWidths | Measure-Object -Sum).Sum)
    if ($topSourceTotal -le 0) { return $null }

    $columnWidths = @()
    foreach ($sourceWidth in $topSourceWidths) {
        $columnWidths += ($topUsableWidth * ([double]$sourceWidth / $topSourceTotal))
    }

    $topHeight = [Math]::Min([Math]::Max(8.0,$topMedianHeight),($contentHeight * 0.28))
    $belowTop = $ContentTop + $topHeight + $Gap
    $belowHeight = $ContentBottom - $belowTop
    if ($belowHeight -le 0) { return $null }

    $topIds = @{}
    foreach ($item in $topItems) { $topIds[[string]$item.Id] = $true }
    $lowerItems = @($managed | Where-Object { -not $topIds.ContainsKey([string]$_.Id) })
    if ($lowerItems.Count -eq 0) { return $null }

    # LEFT is the primary vertical anchor. Its original height proportions
    # define row tracks. Growth is capped so a sparse page cannot create
    # unnaturally tall cards.
    $medianWidth = Get-MedianNumber -Values ([double[]]@($lowerItems | ForEach-Object { $_.Width }))
    $leftX = [double](($lowerItems | Measure-Object -Property X -Minimum).Minimum)
    $leftTolerance = [Math]::Max(($Gap * 2.0),($medianWidth * 0.18))
    $leftItems = @($lowerItems | Where-Object { [Math]::Abs([double]$_.X - $leftX) -le $leftTolerance } | Sort-Object Y)
    if ($leftItems.Count -eq 0) { return $null }

    $rowSourceHeights = [double[]]@($leftItems | ForEach-Object { [double]$_.Height })
    $rowHeights = @(Get-CappedProportionalLengths -SourceLengths $rowSourceHeights -TotalLength $belowHeight -Gap $Gap -MaxGrowth 1.40)
    if ($rowHeights.Count -ne $leftItems.Count) { return $null }

    $sourceColumnStarts = [double[]]@($topItems | ForEach-Object { [double]$_.X })
    $sourceRowStarts = [double[]]@($leftItems | ForEach-Object { [double]$_.Y })
    $columnSlack = [Math]::Max(1.0,$Gap * 0.25)
    $rowSlack = [Math]::Max(1.0,$Gap * 0.25)

    $columnXs = @()
    $cursorX = $ContentLeft
    for ($i = 0; $i -lt $columnWidths.Count; $i++) {
        $columnXs += $cursorX
        $cursorX += [double]$columnWidths[$i] + $Gap
    }

    $rowYs = @()
    $cursorY = $belowTop
    for ($i = 0; $i -lt $rowHeights.Count; $i++) {
        $rowYs += $cursorY
        $cursorY += [double]$rowHeights[$i] + $Gap
    }

    $proposed = @()

    # Place top anchors first.
    for ($i = 0; $i -lt $topItems.Count; $i++) {
        $item = $topItems[$i]
        $proposed += New-ProposedItem -Item $item -X ([double]$columnXs[$i]) -Y $ContentTop -Width ([double]$columnWidths[$i]) -Height $topHeight -Column $i -Row 0 -ColumnSpan 1 -RowSpan 1
    }

    # Everything below the top row snaps to the top/left anchor tracks.
    foreach ($item in $lowerItems) {
        $col = Get-AnchorIndex -Value ([double]$item.X) -Starts $sourceColumnStarts
        $row = Get-AnchorIndex -Value ([double]$item.Y) -Starts $sourceRowStarts

        $colSpan = Get-AnchorSpan -StartIndex $col -EndCoordinate ([double]$item.X + [double]$item.Width) -Starts $sourceColumnStarts -Slack $columnSlack
        $rowSpan = Get-AnchorSpan -StartIndex $row -EndCoordinate ([double]$item.Y + [double]$item.Height) -Starts $sourceRowStarts -Slack $rowSlack

        $colSpan = [Math]::Min([Math]::Max(1,$colSpan),$columnWidths.Count - $col)
        $rowSpan = [Math]::Min([Math]::Max(1,$rowSpan),$rowHeights.Count - $row)

        $width = 0.0
        for ($i = $col; $i -lt ($col + $colSpan); $i++) { $width += [double]$columnWidths[$i] }
        if ($colSpan -gt 1) { $width += (($colSpan - 1) * $Gap) }

        $height = 0.0
        for ($i = $row; $i -lt ($row + $rowSpan); $i++) { $height += [double]$rowHeights[$i] }
        if ($rowSpan -gt 1) { $height += (($rowSpan - 1) * $Gap) }

        $proposed += New-ProposedItem -Item $item -X ([double]$columnXs[$col]) -Y ([double]$rowYs[$row]) -Width $width -Height $height -Column $col -Row ($row + 1) -ColumnSpan $colSpan -RowSpan $rowSpan
    }

    foreach ($item in $locked) {
        $reason = $null
        if ($item.PSObject.Properties.Name -contains 'ProtectionReason') { $reason = $item.ProtectionReason }
        $proposed += New-ProposedItem -Item $item -X ([double]$item.X) -Y ([double]$item.Y) -Width ([double]$item.Width) -Height ([double]$item.Height) -Column 0 -Row 0 -ColumnSpan 1 -RowSpan 1 -IsLocked $true -AllowOverlap ([bool]$item.AllowOverlap) -ProtectionReason $reason
    }

    [pscustomobject]@{
        PageWidth = [double]$Analysis.PageWidth
        PageHeight = [double]$Analysis.PageHeight
        Margin = $Margin
        Gap = $Gap
        ContentLeft = [Math]::Round($ContentLeft,3)
        ContentTop = [Math]::Round($ContentTop,3)
        ContentRight = [Math]::Round($ContentRight,3)
        ContentBottom = [Math]::Round($ContentBottom,3)
        Columns = $columnWidths.Count
        Rows = $rowHeights.Count + 1
        LayoutStrategy = 'Frame Anchors'
        TopAnchorCount = $topItems.Count
        LeftAnchorCount = $leftItems.Count
        TopWidthRatioPreserved = $true
        LeftHeightGrowthCap = 1.40
        MaxAreaShareDeltaPercent = $null
        Items = $proposed
        ChangedCount = @($proposed | Where-Object { $_.Changed }).Count
    }
}
function Get-ScaledTrackSizes {
    param(
        [int]$TrackCount,
        [double]$AvailableSize,
        [double]$Gap,
        [object[]]$Weights
    )

    $usable = $AvailableSize - (($TrackCount - 1) * $Gap)
    if ($usable -le 0) { throw 'Configured gap leaves no usable space for detected tracks.' }

    $rawWeights = @()
    for ($i = 0; $i -lt $TrackCount; $i++) {
        $value = 1.0
        if ($null -ne $Weights -and $i -lt $Weights.Count) {
            $candidate = [double]$Weights[$i]
            if ($candidate -gt 0) { $value = $candidate }
        }
        $rawWeights += $value
    }

    $totalWeight = [double](($rawWeights | Measure-Object -Sum).Sum)
    if ($totalWeight -le 0) { $totalWeight = [double]$TrackCount }

    $scaled = @()
    foreach ($weight in $rawWeights) {
        $scaled += [double]($usable * ([double]$weight / $totalWeight))
    }
    return @($scaled)
}

function Get-TrackOffset {
    param([double]$Origin,[double[]]$TrackSizes,[int]$Index,[double]$Gap)
    $offset = $Origin
    for ($i = 0; $i -lt $Index; $i++) { $offset += [double]$TrackSizes[$i] + $Gap }
    return $offset
}

function Get-SpannedTrackSize {
    param([double[]]$TrackSizes,[int]$StartIndex,[int]$Span,[double]$Gap)
    $size = 0.0
    for ($i = $StartIndex; $i -lt ($StartIndex + $Span); $i++) { $size += [double]$TrackSizes[$i] }
    if ($Span -gt 1) { $size += ($Span - 1) * $Gap }
    return $size
}

function Get-WeightedTrackPbiLayout {
    param(
        $Analysis,
        [double]$ContentLeft,
        [double]$ContentTop,
        [double]$ContentRight,
        [double]$ContentBottom,
        [double]$Gap,
        [double]$Margin
    )

    $columns = [Math]::Max(1,[int]$Analysis.ColumnCount)
    $rows = [Math]::Max(1,[int]$Analysis.RowCount)
    $contentWidth = $ContentRight - $ContentLeft
    $contentHeight = $ContentBottom - $ContentTop

    $columnSizes = [double[]]@(Get-ScaledTrackSizes -TrackCount $columns -AvailableSize $contentWidth -Gap $Gap -Weights (Get-AnalysisArray -Analysis $Analysis -Name 'ColumnWeights'))
    $rowSizes = [double[]]@(Get-ScaledTrackSizes -TrackCount $rows -AvailableSize $contentHeight -Gap $Gap -Weights (Get-AnalysisArray -Analysis $Analysis -Name 'RowWeights'))
    $proposed = @()

    foreach ($item in @($Analysis.Items)) {
        $isLocked = ($item.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$item.IsLocked)

        if ($isLocked) {
            $reason = $null
            if ($item.PSObject.Properties.Name -contains 'ProtectionReason') { $reason = $item.ProtectionReason }
            $proposed += New-ProposedItem -Item $item -X ([double]$item.X) -Y ([double]$item.Y) -Width ([double]$item.Width) -Height ([double]$item.Height) -Column 0 -Row 0 -ColumnSpan 1 -RowSpan 1 -IsLocked $true -AllowOverlap ([bool]$item.AllowOverlap) -ProtectionReason $reason
            continue
        }

        $col = [Math]::Min([Math]::Max(0,[int]$item.Column),$columns - 1)
        $row = [Math]::Min([Math]::Max(0,[int]$item.Row),$rows - 1)
        $colSpan = [Math]::Min([Math]::Max(1,[int]$item.ColumnSpan),$columns - $col)
        $rowSpan = [Math]::Min([Math]::Max(1,[int]$item.RowSpan),$rows - $row)

        $x = Get-TrackOffset -Origin $ContentLeft -TrackSizes $columnSizes -Index $col -Gap $Gap
        $y = Get-TrackOffset -Origin $ContentTop -TrackSizes $rowSizes -Index $row -Gap $Gap
        $width = Get-SpannedTrackSize -TrackSizes $columnSizes -StartIndex $col -Span $colSpan -Gap $Gap
        $height = Get-SpannedTrackSize -TrackSizes $rowSizes -StartIndex $row -Span $rowSpan -Gap $Gap

        $proposed += New-ProposedItem -Item $item -X $x -Y $y -Width $width -Height $height -Column $col -Row $row -ColumnSpan $colSpan -RowSpan $rowSpan
    }

    [pscustomobject]@{
        PageWidth = [double]$Analysis.PageWidth
        PageHeight = [double]$Analysis.PageHeight
        Margin = $Margin
        Gap = $Gap
        ContentLeft = [Math]::Round($ContentLeft,3)
        ContentTop = [Math]::Round($ContentTop,3)
        ContentRight = [Math]::Round($ContentRight,3)
        ContentBottom = [Math]::Round($ContentBottom,3)
        Columns = $columns
        Rows = $rows
        LayoutStrategy = 'Weighted Tracks'
        MaxAreaShareDeltaPercent = $null
        Items = $proposed
        ChangedCount = @($proposed | Where-Object { $_.Changed }).Count
    }
}

function Get-SmartPbiLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Analysis,
        [ValidateRange(0,500)][double]$Margin = 5,
        [ValidateRange(0,500)][double]$Gap = 5
    )

    if ($Analysis.PageWidth -le 0 -or $Analysis.PageHeight -le 0) {
        throw 'Page width and height must be positive before layout can be calculated.'
    }

    $reservedLeft = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedLeft' -Default 0
    $reservedTop = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedTop' -Default 0
    $reservedRight = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedRight' -Default ([double]$Analysis.PageWidth)
    $reservedBottom = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedBottom' -Default ([double]$Analysis.PageHeight)

    $contentLeft = if ($reservedLeft -gt 0) { $reservedLeft + $Gap } else { $Margin }
    $contentTop = if ($reservedTop -gt 0) { $reservedTop + $Gap } else { $Margin }
    $contentRight = if ($reservedRight -lt [double]$Analysis.PageWidth) { $reservedRight - $Gap } else { [double]$Analysis.PageWidth - $Margin }
    $contentBottom = if ($reservedBottom -lt [double]$Analysis.PageHeight) { $reservedBottom - $Gap } else { [double]$Analysis.PageHeight - $Margin }

    if (($contentRight - $contentLeft) -le 0 -or ($contentBottom - $contentTop) -le 0) {
        throw 'Protected header/footer/sidebar regions leave no usable content area for Smart Align.'
    }

    # Primary strategy: TOP widths define horizontal tracks; LEFT heights define
    # vertical tracks. This matches the report-authoring pattern used by the
    # alignment service and preserves those original proportions.
    $frameLayout = Get-FrameAnchoredPbiLayout -Analysis $Analysis -ContentLeft $contentLeft -ContentTop $contentTop -ContentRight $contentRight -ContentBottom $contentBottom -Gap $Gap -Margin $Margin
    if ($null -ne $frameLayout) { return $frameLayout }

    $areaLayout = Get-AreaPreservingPbiLayout -Analysis $Analysis -ContentLeft $contentLeft -ContentTop $contentTop -ContentRight $contentRight -ContentBottom $contentBottom -Gap $Gap -Margin $Margin
    if ($null -ne $areaLayout) { return $areaLayout }

    return Get-WeightedTrackPbiLayout -Analysis $Analysis -ContentLeft $contentLeft -ContentTop $contentTop -ContentRight $contentRight -ContentBottom $contentBottom -Gap $Gap -Margin $Margin
}

Export-ModuleMember -Function Get-SmartPbiLayout
