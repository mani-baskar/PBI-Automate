Set-StrictMode -Version 2.0

function Get-MedianValue {
    param([double[]]$Values)

    $items = @($Values | Sort-Object)
    if ($items.Count -eq 0) { return 0.0 }

    $mid = [int][Math]::Floor($items.Count / 2)
    if (($items.Count % 2) -eq 1) { return [double]$items[$mid] }

    return ([double]$items[$mid - 1] + [double]$items[$mid]) / 2.0
}

function Get-ClusterStarts {
    param(
        [double[]]$Values,
        [double]$Tolerance
    )

    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return @() }

    $clusters = @()

    foreach ($value in $sorted) {
        $matched = $false

        for ($i = 0; $i -lt $clusters.Count; $i++) {
            if ([Math]::Abs($value - $clusters[$i].Center) -le $Tolerance) {
                $clusters[$i].Values += [double]$value
                $clusters[$i].Center = Get-MedianValue -Values ([double[]]$clusters[$i].Values)
                $matched = $true
                break
            }
        }

        if (-not $matched) {
            $clusters += [pscustomobject]@{
                Center = [double]$value
                Values = @([double]$value)
            }
        }
    }

    return @($clusters | Sort-Object Center)
}

function Get-AdaptiveStartTolerance {
    param(
        [double[]]$Values,
        [double]$BaseSize,
        [double]$MinimumTolerance,
        [double]$MaximumTolerance,
        [double]$BaseRatio = 0.30,
        [double]$NearbyGapRatio = 0.50
    )

    if ($BaseSize -le 0) {
        return [Math]::Max($MinimumTolerance,1.0)
    }

    # Start with a size-relative tolerance instead of a tiny fixed pixel value.
    # PBIR coordinates are page units; on a 1920-wide canvas a 40-80 unit drift
    # can still visually represent the same intended row/column.
    $tolerance = [Math]::Max($MinimumTolerance,$BaseSize * $BaseRatio)
    $sizeCap = [Math]::Max($MinimumTolerance,$BaseSize * 0.55)

    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -gt 1) {
        $smallGapLimit = $BaseSize * $NearbyGapRatio

        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $gap = [Math]::Abs([double]$sorted[$i] - [double]$sorted[$i - 1])

            # Repeated intended starts commonly differ by a small amount.
            # Use those observed near-duplicates to learn the page's real drift,
            # but never allow the tolerance to approach a full peer visual size.
            if ($gap -gt 0.001 -and $gap -le $smallGapLimit) {
                $tolerance = [Math]::Max($tolerance,$gap * 1.25)
            }
        }
    }

    return [Math]::Min($MaximumTolerance,[Math]::Min($sizeCap,$tolerance))
}

function Get-NearestClusterIndex {
    param(
        [Parameter(Mandatory=$true)][double]$Value,
        [Parameter(Mandatory=$true)][object[]]$Clusters
    )

    if ($Clusters.Count -eq 0) { return 0 }

    $bestIndex = 0
    $bestDistance = [double]::MaxValue

    for ($i = 0; $i -lt $Clusters.Count; $i++) {
        $distance = [Math]::Abs($Value - [double]$Clusters[$i].Center)
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestIndex = $i
        }
    }

    return $bestIndex
}

function Get-SpanFromTrackStarts {
    param(
        [Parameter(Mandatory=$true)][int]$StartIndex,
        [Parameter(Mandatory=$true)][double]$EndCoordinate,
        [Parameter(Mandatory=$true)][object[]]$Clusters,
        [Parameter(Mandatory=$true)][double]$Tolerance
    )

    if ($Clusters.Count -eq 0) { return 1 }

    $span = 1
    $edgeSlack = [Math]::Max(1.0,$Tolerance * 0.20)

    for ($i = $StartIndex + 1; $i -lt $Clusters.Count; $i++) {
        # A visual spans a later track only when that track genuinely begins
        # inside the visual's original rectangle. This avoids the old
        # width/median heuristic that caused oversized row/column spans.
        if ([double]$Clusters[$i].Center -lt ($EndCoordinate - $edgeSlack)) {
            $span++
        }
        else {
            break
        }
    }

    return [Math]::Max(1,$span)
}

function Get-TrackWeights {
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [Parameter(Mandatory=$true)][int]$TrackCount,
        [Parameter(Mandatory=$true)][ValidateSet('Column','Row')][string]$Axis,
        [Parameter(Mandatory=$true)][double]$Fallback
    )

    $weights = @()

    for ($track = 0; $track -lt $TrackCount; $track++) {
        $values = @()

        foreach ($item in $Items) {
            if ($Axis -eq 'Column') {
                if ([int]$item.Column -eq $track -and [int]$item.ColumnSpan -eq 1) {
                    $values += [double]$item.Width
                }
            }
            else {
                if ([int]$item.Row -eq $track -and [int]$item.RowSpan -eq 1) {
                    $values += [double]$item.Height
                }
            }
        }

        if ($values.Count -gt 0) {
            $weights += [double](Get-MedianValue -Values ([double[]]$values))
        }
        else {
            $weights += [double]$Fallback
        }
    }

    # If all column peers are already roughly the same size, make them exactly
    # equal. This is the expected behavior for KPI/card rows.
    if ($Axis -eq 'Column' -and $weights.Count -gt 1) {
        $positive = @($weights | Where-Object { $_ -gt 0 })
        if ($positive.Count -gt 0) {
            $min = ($positive | Measure-Object -Minimum).Minimum
            $max = ($positive | Measure-Object -Maximum).Maximum
            if ($min -gt 0 -and ($max / $min) -le 1.25) {
                $peerMedian = Get-MedianValue -Values ([double[]]$positive)
                $weights = @(1..$TrackCount | ForEach-Object { [double]$peerMedian })
            }
        }
    }

    return @($weights)
}

function Get-VisualProtectionReason {
    param(
        [Parameter(Mandatory=$true)]$Visual,
        [Parameter(Mandatory=$true)][double]$PageWidth,
        [Parameter(Mandatory=$true)][double]$PageHeight
    )

    if ($Visual.PSObject.Properties.Name -contains 'IsHidden' -and [bool]$Visual.IsHidden) {
        return 'Hidden'
    }

    if ($Visual.PSObject.Properties.Name -contains 'IsVisualGroup' -and [bool]$Visual.IsVisualGroup) {
        return 'VisualGroup'
    }

    if ($Visual.PSObject.Properties.Name -contains 'ParentGroupName' -and
        -not [string]::IsNullOrWhiteSpace([string]$Visual.ParentGroupName)) {
        return 'GroupedChild'
    }

    if ($PageWidth -le 0 -or $PageHeight -le 0) {
        return $null
    }

    $widthRatio = [double]$Visual.Width / $PageWidth
    $heightRatio = [double]$Visual.Height / $PageHeight

    if ($widthRatio -ge 0.90 -and $heightRatio -ge 0.90) {
        return 'CanvasBackground'
    }

    $type = ([string]$Visual.VisualType).ToLowerInvariant()
    $structuralTypes = @(
        'textbox',
        'shape',
        'basicshape',
        'image',
        'button',
        'actionbutton',
        'navigationbutton',
        'pagenavigator',
        'bookmarknavigator'
    )

    if ($structuralTypes -notcontains $type) {
        return $null
    }

    $isWideChrome = ($widthRatio -ge 0.75 -and $heightRatio -le 0.18)
    $isTallChrome = ($heightRatio -ge 0.75 -and $widthRatio -le 0.18)

    if ($isWideChrome) {
        if ([double]$Visual.Y -le ($PageHeight * 0.20)) { return 'TopChrome' }
        if ([double]$Visual.Bottom -ge ($PageHeight * 0.80)) { return 'BottomChrome' }
        return 'StructuralChrome'
    }

    if ($isTallChrome) {
        if ([double]$Visual.X -le ($PageWidth * 0.20)) { return 'LeftChrome' }
        if ([double]$Visual.Right -ge ($PageWidth * 0.80)) { return 'RightChrome' }
        return 'StructuralChrome'
    }

    return $null
}

function Get-PbiLayoutAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$PageSnapshot,
        [double]$MinimumTolerance = 3,
        [double]$MaximumTolerance = 120
    )

    $allVisuals = @($PageSnapshot.Visuals)
    if ($allVisuals.Count -eq 0) {
        throw 'The selected page does not contain supported visual containers.'
    }

    $locked = @()
    $visuals = @()
    $protectionReasons = @{}

    $reservedLeft = 0.0
    $reservedTop = 0.0
    $reservedRight = [double]$PageSnapshot.Width
    $reservedBottom = [double]$PageSnapshot.Height

    foreach ($visual in $allVisuals) {
        $reason = Get-VisualProtectionReason -Visual $visual -PageWidth ([double]$PageSnapshot.Width) -PageHeight ([double]$PageSnapshot.Height)

        if ([string]::IsNullOrWhiteSpace([string]$reason)) {
            $visuals += $visual
            continue
        }

        $locked += $visual
        $protectionReasons[[string]$visual.Id] = $reason

        switch ($reason) {
            'TopChrome' { $reservedTop = [Math]::Max($reservedTop,[double]$visual.Bottom) }
            'BottomChrome' { $reservedBottom = [Math]::Min($reservedBottom,[double]$visual.Y) }
            'LeftChrome' { $reservedLeft = [Math]::Max($reservedLeft,[double]$visual.Right) }
            'RightChrome' { $reservedRight = [Math]::Min($reservedRight,[double]$visual.X) }
        }
    }

    if ($visuals.Count -eq 0) {
        throw 'No layout-managed visuals remain after protecting background, structural, grouped, or hidden visuals.'
    }

    $medianWidth = Get-MedianValue -Values ([double[]]@($visuals | ForEach-Object { $_.Width }))
    $medianHeight = Get-MedianValue -Values ([double[]]@($visuals | ForEach-Object { $_.Height }))

    $xValues = [double[]]@($visuals | ForEach-Object { [double]$_.X })
    $yValues = [double[]]@($visuals | ForEach-Object { [double]$_.Y })

    $xTolerance = Get-AdaptiveStartTolerance -Values $xValues -BaseSize $medianWidth -MinimumTolerance $MinimumTolerance -MaximumTolerance $MaximumTolerance -BaseRatio 0.30 -NearbyGapRatio 0.50
    $yTolerance = Get-AdaptiveStartTolerance -Values $yValues -BaseSize $medianHeight -MinimumTolerance $MinimumTolerance -MaximumTolerance $MaximumTolerance -BaseRatio 0.45 -NearbyGapRatio 0.55

    $columnClusters = @(Get-ClusterStarts -Values $xValues -Tolerance $xTolerance)
    $rowClusters = @(Get-ClusterStarts -Values $yValues -Tolerance $yTolerance)

    $managedItems = @()

    foreach ($v in $visuals) {
        $col = Get-NearestClusterIndex -Value ([double]$v.X) -Clusters $columnClusters
        $row = Get-NearestClusterIndex -Value ([double]$v.Y) -Clusters $rowClusters

        $colSpan = Get-SpanFromTrackStarts -StartIndex $col -EndCoordinate ([double]$v.Right) -Clusters $columnClusters -Tolerance $xTolerance
        $rowSpan = Get-SpanFromTrackStarts -StartIndex $row -EndCoordinate ([double]$v.Bottom) -Clusters $rowClusters -Tolerance $yTolerance

        $colSpan = [Math]::Min($colSpan,$columnClusters.Count - $col)
        $rowSpan = [Math]::Min($rowSpan,$rowClusters.Count - $row)

        $managedItems += [pscustomobject]@{
            Id = $v.Id
            VisualType = $v.VisualType
            FilePath = $v.FilePath
            SourceHash = $v.FileHash
            ParentGroupName = $v.ParentGroupName
            IsVisualGroup = $v.IsVisualGroup
            IsHidden = $v.IsHidden
            ProtectionReason = $null
            X = [double]$v.X
            Y = [double]$v.Y
            Width = [double]$v.Width
            Height = [double]$v.Height
            Column = [int]$col
            Row = [int]$row
            ColumnSpan = [Math]::Max(1,[int]$colSpan)
            RowSpan = [Math]::Max(1,[int]$rowSpan)
            IsLarge = ([int]$colSpan -gt 1 -or [int]$rowSpan -gt 1)
            IsLocked = $false
            AllowOverlap = $false
        }
    }

    $columnWeights = @(Get-TrackWeights -Items $managedItems -TrackCount ([Math]::Max(1,$columnClusters.Count)) -Axis Column -Fallback $medianWidth)
    $rowWeights = @(Get-TrackWeights -Items $managedItems -TrackCount ([Math]::Max(1,$rowClusters.Count)) -Axis Row -Fallback $medianHeight)

    $items = @($managedItems)

    foreach ($v in $locked) {
        $items += [pscustomobject]@{
            Id = $v.Id
            VisualType = $v.VisualType
            FilePath = $v.FilePath
            SourceHash = $v.FileHash
            ParentGroupName = $v.ParentGroupName
            IsVisualGroup = $v.IsVisualGroup
            IsHidden = $v.IsHidden
            ProtectionReason = [string]$protectionReasons[[string]$v.Id]
            X = [double]$v.X
            Y = [double]$v.Y
            Width = [double]$v.Width
            Height = [double]$v.Height
            Column = 0
            Row = 0
            ColumnSpan = 1
            RowSpan = 1
            IsLarge = $true
            IsLocked = $true
            AllowOverlap = $true
        }
    }

    [pscustomobject]@{
        PageWidth = [double]$PageSnapshot.Width
        PageHeight = [double]$PageSnapshot.Height
        VisualCount = $allVisuals.Count
        ManagedVisualCount = $visuals.Count
        LockedVisualCount = $locked.Count
        ReservedLeft = $reservedLeft
        ReservedTop = $reservedTop
        ReservedRight = $reservedRight
        ReservedBottom = $reservedBottom
        MedianWidth = $medianWidth
        MedianHeight = $medianHeight
        ColumnTolerance = [Math]::Round($xTolerance,3)
        RowTolerance = [Math]::Round($yTolerance,3)
        ColumnCount = [Math]::Max(1,$columnClusters.Count)
        RowCount = [Math]::Max(1,$rowClusters.Count)
        ColumnStarts = @($columnClusters | ForEach-Object { [double]$_.Center })
        RowStarts = @($rowClusters | ForEach-Object { [double]$_.Center })
        ColumnWeights = $columnWeights
        RowWeights = $rowWeights
        Items = $items
    }
}

Export-ModuleMember -Function Get-PbiLayoutAnalysis
