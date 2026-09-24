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
                $clusters[$i].Values += $value
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
        if ([double]$Visual.Y -le ($PageHeight * 0.20)) {
            return 'TopChrome'
        }

        if ([double]$Visual.Bottom -ge ($PageHeight * 0.80)) {
            return 'BottomChrome'
        }

        return 'StructuralChrome'
    }

    if ($isTallChrome) {
        if ([double]$Visual.X -le ($PageWidth * 0.20)) {
            return 'LeftChrome'
        }

        if ([double]$Visual.Right -ge ($PageWidth * 0.80)) {
            return 'RightChrome'
        }

        return 'StructuralChrome'
    }

    return $null
}

function Get-PbiLayoutAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$PageSnapshot,
        [double]$MinimumTolerance = 3,
        [double]$MaximumTolerance = 24
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
            'TopChrome' {
                $reservedTop = [Math]::Max($reservedTop,[double]$visual.Bottom)
            }
            'BottomChrome' {
                $reservedBottom = [Math]::Min($reservedBottom,[double]$visual.Y)
            }
            'LeftChrome' {
                $reservedLeft = [Math]::Max($reservedLeft,[double]$visual.Right)
            }
            'RightChrome' {
                $reservedRight = [Math]::Min($reservedRight,[double]$visual.X)
            }
        }
    }

    if ($visuals.Count -eq 0) {
        throw 'No layout-managed visuals remain after protecting background, structural, grouped, or hidden visuals.'
    }

    $medianWidth = Get-MedianValue -Values ([double[]]@($visuals | ForEach-Object { $_.Width }))
    $medianHeight = Get-MedianValue -Values ([double[]]@($visuals | ForEach-Object { $_.Height }))

    $xTolerance = [Math]::Min($MaximumTolerance,[Math]::Max($MinimumTolerance,$medianWidth * 0.08))
    $yTolerance = [Math]::Min($MaximumTolerance,[Math]::Max($MinimumTolerance,$medianHeight * 0.08))

    $columnClusters = @(Get-ClusterStarts -Values ([double[]]@($visuals | ForEach-Object { $_.X })) -Tolerance $xTolerance)
    $rowClusters = @(Get-ClusterStarts -Values ([double[]]@($visuals | ForEach-Object { $_.Y })) -Tolerance $yTolerance)

    $items = @()

    foreach ($v in $visuals) {
        $col = 0
        $bestX = [double]::MaxValue

        for ($i = 0; $i -lt $columnClusters.Count; $i++) {
            $distance = [Math]::Abs($v.X - $columnClusters[$i].Center)
            if ($distance -lt $bestX) {
                $bestX = $distance
                $col = $i
            }
        }

        $row = 0
        $bestY = [double]::MaxValue

        for ($i = 0; $i -lt $rowClusters.Count; $i++) {
            $distance = [Math]::Abs($v.Y - $rowClusters[$i].Center)
            if ($distance -lt $bestY) {
                $bestY = $distance
                $row = $i
            }
        }

        $colSpan = 1
        if ($medianWidth -gt 0) {
            $colSpan = [Math]::Max(1,[int][Math]::Round($v.Width / $medianWidth))
        }

        $rowSpan = 1
        if ($medianHeight -gt 0) {
            $rowSpan = [Math]::Max(1,[int][Math]::Round($v.Height / $medianHeight))
        }

        if ($columnClusters.Count -gt 0) {
            $colSpan = [Math]::Min($colSpan,$columnClusters.Count - $col)
        }

        if ($rowClusters.Count -gt 0) {
            $rowSpan = [Math]::Min($rowSpan,$rowClusters.Count - $row)
        }

        $items += [pscustomobject]@{
            Id = $v.Id
            VisualType = $v.VisualType
            FilePath = $v.FilePath
            SourceHash = $v.FileHash
            ParentGroupName = $v.ParentGroupName
            IsVisualGroup = $v.IsVisualGroup
            IsHidden = $v.IsHidden
            ProtectionReason = $null
            X = $v.X
            Y = $v.Y
            Width = $v.Width
            Height = $v.Height
            Column = $col
            Row = $row
            ColumnSpan = [Math]::Max(1,$colSpan)
            RowSpan = [Math]::Max(1,$rowSpan)
            IsLarge = (($v.Width -gt ($medianWidth * 1.6)) -or ($v.Height -gt ($medianHeight * 1.6)))
            IsLocked = $false
            AllowOverlap = $false
        }
    }

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
            X = $v.X
            Y = $v.Y
            Width = $v.Width
            Height = $v.Height
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
        ColumnTolerance = $xTolerance
        RowTolerance = $yTolerance
        ColumnCount = [Math]::Max(1,$columnClusters.Count)
        RowCount = [Math]::Max(1,$rowClusters.Count)
        ColumnStarts = @($columnClusters | ForEach-Object { $_.Center })
        RowStarts = @($rowClusters | ForEach-Object { $_.Center })
        Items = $items
    }
}

Export-ModuleMember -Function Get-PbiLayoutAnalysis
