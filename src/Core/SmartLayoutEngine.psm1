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

function Get-ScaledTrackSizes {
    param(
        [Parameter(Mandatory=$true)][int]$TrackCount,
        [Parameter(Mandatory=$true)][double]$AvailableSize,
        [Parameter(Mandatory=$true)][double]$Gap,
        [object[]]$Weights
    )

    if ($TrackCount -le 0) { return @() }

    $usable = $AvailableSize - (($TrackCount - 1) * $Gap)
    if ($usable -le 0) {
        throw 'Configured gap leaves no usable space for detected tracks.'
    }

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
    if ($totalWeight -le 0) {
        $rawWeights = @(1..$TrackCount | ForEach-Object { 1.0 })
        $totalWeight = [double]$TrackCount
    }

    $scaled = @()
    foreach ($weight in $rawWeights) {
        $scaled += [double]($usable * ([double]$weight / $totalWeight))
    }

    return @($scaled)
}

function Get-TrackOffset {
    param(
        [Parameter(Mandatory=$true)][double]$Origin,
        [Parameter(Mandatory=$true)][double[]]$TrackSizes,
        [Parameter(Mandatory=$true)][int]$Index,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    $offset = $Origin
    for ($i = 0; $i -lt $Index; $i++) {
        $offset += [double]$TrackSizes[$i] + $Gap
    }

    return $offset
}

function Get-SpannedTrackSize {
    param(
        [Parameter(Mandatory=$true)][double[]]$TrackSizes,
        [Parameter(Mandatory=$true)][int]$StartIndex,
        [Parameter(Mandatory=$true)][int]$Span,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    $size = 0.0
    for ($i = $StartIndex; $i -lt ($StartIndex + $Span); $i++) {
        $size += [double]$TrackSizes[$i]
    }

    if ($Span -gt 1) {
        $size += ($Span - 1) * $Gap
    }

    return $size
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

    $columns = [Math]::Max(1,[int]$Analysis.ColumnCount)
    $rows = [Math]::Max(1,[int]$Analysis.RowCount)

    $reservedLeft = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedLeft' -Default 0
    $reservedTop = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedTop' -Default 0
    $reservedRight = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedRight' -Default ([double]$Analysis.PageWidth)
    $reservedBottom = Get-AnalysisNumber -Analysis $Analysis -Name 'ReservedBottom' -Default ([double]$Analysis.PageHeight)

    $contentLeft = if ($reservedLeft -gt 0) { $reservedLeft + $Gap } else { $Margin }
    $contentTop = if ($reservedTop -gt 0) { $reservedTop + $Gap } else { $Margin }
    $contentRight = if ($reservedRight -lt [double]$Analysis.PageWidth) { $reservedRight - $Gap } else { [double]$Analysis.PageWidth - $Margin }
    $contentBottom = if ($reservedBottom -lt [double]$Analysis.PageHeight) { $reservedBottom - $Gap } else { [double]$Analysis.PageHeight - $Margin }

    $contentWidth = $contentRight - $contentLeft
    $contentHeight = $contentBottom - $contentTop

    if ($contentWidth -le 0 -or $contentHeight -le 0) {
        throw 'Protected header/footer/sidebar regions leave no usable content area for Smart Align.'
    }

    $columnWeights = Get-AnalysisArray -Analysis $Analysis -Name 'ColumnWeights'
    $rowWeights = Get-AnalysisArray -Analysis $Analysis -Name 'RowWeights'

    $columnSizes = [double[]]@(Get-ScaledTrackSizes -TrackCount $columns -AvailableSize $contentWidth -Gap $Gap -Weights $columnWeights)
    $rowSizes = [double[]]@(Get-ScaledTrackSizes -TrackCount $rows -AvailableSize $contentHeight -Gap $Gap -Weights $rowWeights)

    $proposed = @()

    foreach ($item in @($Analysis.Items)) {
        $isLocked = ($item.PSObject.Properties.Name -contains 'IsLocked' -and [bool]$item.IsLocked)
        $allowOverlap = ($item.PSObject.Properties.Name -contains 'AllowOverlap' -and [bool]$item.AllowOverlap)
        $protectionReason = $null

        if ($item.PSObject.Properties.Name -contains 'ProtectionReason') {
            $protectionReason = $item.ProtectionReason
        }

        if ($isLocked) {
            $proposed += [pscustomobject]@{
                Id = $item.Id
                VisualType = $item.VisualType
                FilePath = $item.FilePath
                SourceHash = $item.SourceHash
                ParentGroupName = $item.ParentGroupName
                IsVisualGroup = $item.IsVisualGroup
                IsHidden = $item.IsHidden
                ProtectionReason = $protectionReason
                OldX = [double]$item.X
                OldY = [double]$item.Y
                OldWidth = [double]$item.Width
                OldHeight = [double]$item.Height
                X = [double]$item.X
                Y = [double]$item.Y
                Width = [double]$item.Width
                Height = [double]$item.Height
                Column = 0
                Row = 0
                ColumnSpan = 1
                RowSpan = 1
                IsLocked = $true
                AllowOverlap = $allowOverlap
                Changed = $false
            }
            continue
        }

        $col = [Math]::Min([Math]::Max(0,[int]$item.Column),$columns - 1)
        $row = [Math]::Min([Math]::Max(0,[int]$item.Row),$rows - 1)

        $colSpan = [Math]::Min([Math]::Max(1,[int]$item.ColumnSpan),$columns - $col)
        $rowSpan = [Math]::Min([Math]::Max(1,[int]$item.RowSpan),$rows - $row)

        $x = Get-TrackOffset -Origin $contentLeft -TrackSizes $columnSizes -Index $col -Gap $Gap
        $y = Get-TrackOffset -Origin $contentTop -TrackSizes $rowSizes -Index $row -Gap $Gap
        $width = Get-SpannedTrackSize -TrackSizes $columnSizes -StartIndex $col -Span $colSpan -Gap $Gap
        $height = Get-SpannedTrackSize -TrackSizes $rowSizes -StartIndex $row -Span $rowSpan -Gap $Gap

        $proposed += [pscustomobject]@{
            Id = $item.Id
            VisualType = $item.VisualType
            FilePath = $item.FilePath
            SourceHash = $item.SourceHash
            ParentGroupName = $item.ParentGroupName
            IsVisualGroup = $item.IsVisualGroup
            IsHidden = $item.IsHidden
            ProtectionReason = $null
            OldX = [double]$item.X
            OldY = [double]$item.Y
            OldWidth = [double]$item.Width
            OldHeight = [double]$item.Height
            X = [Math]::Round($x,3)
            Y = [Math]::Round($y,3)
            Width = [Math]::Round($width,3)
            Height = [Math]::Round($height,3)
            Column = $col
            Row = $row
            ColumnSpan = $colSpan
            RowSpan = $rowSpan
            IsLocked = $false
            AllowOverlap = $false
            Changed = (
                [Math]::Abs([double]$item.X - $x) -gt 0.001 -or
                [Math]::Abs([double]$item.Y - $y) -gt 0.001 -or
                [Math]::Abs([double]$item.Width - $width) -gt 0.001 -or
                [Math]::Abs([double]$item.Height - $height) -gt 0.001
            )
        }
    }

    $cellWidth = [double](($columnSizes | Measure-Object -Average).Average)
    $cellHeight = [double](($rowSizes | Measure-Object -Average).Average)

    [pscustomobject]@{
        PageWidth = [double]$Analysis.PageWidth
        PageHeight = [double]$Analysis.PageHeight
        Margin = $Margin
        Gap = $Gap
        ContentLeft = [Math]::Round($contentLeft,3)
        ContentTop = [Math]::Round($contentTop,3)
        ContentRight = [Math]::Round($contentRight,3)
        ContentBottom = [Math]::Round($contentBottom,3)
        Columns = $columns
        Rows = $rows
        ColumnSizes = @($columnSizes | ForEach-Object { [Math]::Round($_,3) })
        RowSizes = @($rowSizes | ForEach-Object { [Math]::Round($_,3) })
        CellWidth = [Math]::Round($cellWidth,3)
        CellHeight = [Math]::Round($cellHeight,3)
        Items = $proposed
        ChangedCount = @($proposed | Where-Object { $_.Changed }).Count
    }
}

Export-ModuleMember -Function Get-SmartPbiLayout
