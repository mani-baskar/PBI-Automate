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

    $usableWidth = $contentWidth - (($columns - 1) * $Gap)
    $usableHeight = $contentHeight - (($rows - 1) * $Gap)

    if ($usableWidth -le 0 -or $usableHeight -le 0) {
        throw 'Configured margin/gap or protected regions leave insufficient space for the detected layout.'
    }

    $cellWidth = $usableWidth / $columns
    $cellHeight = $usableHeight / $rows
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

        $x = $contentLeft + ($col * ($cellWidth + $Gap))
        $y = $contentTop + ($row * ($cellHeight + $Gap))
        $width = ($cellWidth * $colSpan) + ($Gap * ($colSpan - 1))
        $height = ($cellHeight * $rowSpan) + ($Gap * ($rowSpan - 1))

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
                [Math]::Abs($item.X - $x) -gt 0.001 -or
                [Math]::Abs($item.Y - $y) -gt 0.001 -or
                [Math]::Abs($item.Width - $width) -gt 0.001 -or
                [Math]::Abs($item.Height - $height) -gt 0.001
            )
        }
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
        Columns = $columns
        Rows = $rows
        CellWidth = [Math]::Round($cellWidth,3)
        CellHeight = [Math]::Round($cellHeight,3)
        Items = $proposed
        ChangedCount = @($proposed | Where-Object { $_.Changed }).Count
    }
}

Export-ModuleMember -Function Get-SmartPbiLayout
