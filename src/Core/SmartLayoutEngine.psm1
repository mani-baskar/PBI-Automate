Set-StrictMode -Version 2.0

function Get-SmartPbiLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Analysis,[ValidateRange(0,500)][double]$Margin=5,[ValidateRange(0,500)][double]$Gap=5)
    if ($Analysis.PageWidth -le 0 -or $Analysis.PageHeight -le 0) { throw 'Page width and height must be positive before layout can be calculated.' }
    $columns=[Math]::Max(1,[int]$Analysis.ColumnCount); $rows=[Math]::Max(1,[int]$Analysis.RowCount)
    $usableWidth=$Analysis.PageWidth-(2*$Margin)-(($columns-1)*$Gap)
    $usableHeight=$Analysis.PageHeight-(2*$Margin)-(($rows-1)*$Gap)
    if ($usableWidth -le 0 -or $usableHeight -le 0) { throw 'Configured margin/gap is too large for this page.' }
    $cellWidth=$usableWidth/$columns; $cellHeight=$usableHeight/$rows
    $proposed=@()
    foreach ($item in @($Analysis.Items)) {
        $col=[Math]::Min([Math]::Max(0,[int]$item.Column),$columns-1); $row=[Math]::Min([Math]::Max(0,[int]$item.Row),$rows-1)
        $colSpan=[Math]::Min([Math]::Max(1,[int]$item.ColumnSpan),$columns-$col); $rowSpan=[Math]::Min([Math]::Max(1,[int]$item.RowSpan),$rows-$row)
        $x=$Margin+($col*($cellWidth+$Gap)); $y=$Margin+($row*($cellHeight+$Gap))
        $width=($cellWidth*$colSpan)+($Gap*($colSpan-1)); $height=($cellHeight*$rowSpan)+($Gap*($rowSpan-1))
        $proposed += [pscustomobject]@{ Id=$item.Id; VisualType=$item.VisualType; FilePath=$item.FilePath; OldX=[double]$item.X; OldY=[double]$item.Y; OldWidth=[double]$item.Width; OldHeight=[double]$item.Height; X=[Math]::Round($x,3); Y=[Math]::Round($y,3); Width=[Math]::Round($width,3); Height=[Math]::Round($height,3); Column=$col; Row=$row; ColumnSpan=$colSpan; RowSpan=$rowSpan; Changed=([Math]::Abs($item.X-$x) -gt 0.001 -or [Math]::Abs($item.Y-$y) -gt 0.001 -or [Math]::Abs($item.Width-$width) -gt 0.001 -or [Math]::Abs($item.Height-$height) -gt 0.001) }
    }
    [pscustomobject]@{ PageWidth=[double]$Analysis.PageWidth; PageHeight=[double]$Analysis.PageHeight; Margin=$Margin; Gap=$Gap; Columns=$columns; Rows=$rows; CellWidth=[Math]::Round($cellWidth,3); CellHeight=[Math]::Round($cellHeight,3); Items=$proposed; ChangedCount=@($proposed | Where-Object { $_.Changed }).Count }
}

Export-ModuleMember -Function Get-SmartPbiLayout
