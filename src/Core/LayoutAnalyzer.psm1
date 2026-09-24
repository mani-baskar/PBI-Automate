Set-StrictMode -Version 2.0

function Get-MedianValue {
    param([double[]]$Values)
    $items=@($Values | Sort-Object); if ($items.Count -eq 0) { return 0.0 }
    $mid=[int][Math]::Floor($items.Count/2)
    if (($items.Count % 2) -eq 1) { return [double]$items[$mid] }
    return ([double]$items[$mid-1]+[double]$items[$mid])/2.0
}

function Get-ClusterStarts {
    param([double[]]$Values,[double]$Tolerance)
    $sorted=@($Values | Sort-Object); if ($sorted.Count -eq 0) { return @() }
    $clusters=@()
    foreach ($value in $sorted) {
        $matched=$false
        for ($i=0; $i -lt $clusters.Count; $i++) {
            if ([Math]::Abs($value-$clusters[$i].Center) -le $Tolerance) {
                $clusters[$i].Values += $value
                $clusters[$i].Center = Get-MedianValue -Values ([double[]]$clusters[$i].Values)
                $matched=$true; break
            }
        }
        if (-not $matched) { $clusters += [pscustomobject]@{ Center=[double]$value; Values=@([double]$value) } }
    }
    return @($clusters | Sort-Object Center)
}

function Get-PbiLayoutAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$PageSnapshot,[double]$MinimumTolerance=3,[double]$MaximumTolerance=24)
    $visuals=@($PageSnapshot.Visuals)
    if ($visuals.Count -eq 0) { throw 'The selected page does not contain supported visual containers.' }
    $medianWidth=Get-MedianValue -Values ([double[]]@($visuals | ForEach-Object { $_.Width }))
    $medianHeight=Get-MedianValue -Values ([double[]]@($visuals | ForEach-Object { $_.Height }))
    $xTolerance=[Math]::Min($MaximumTolerance,[Math]::Max($MinimumTolerance,$medianWidth*0.08))
    $yTolerance=[Math]::Min($MaximumTolerance,[Math]::Max($MinimumTolerance,$medianHeight*0.08))
    $columnClusters=@(Get-ClusterStarts -Values ([double[]]@($visuals | ForEach-Object { $_.X })) -Tolerance $xTolerance)
    $rowClusters=@(Get-ClusterStarts -Values ([double[]]@($visuals | ForEach-Object { $_.Y })) -Tolerance $yTolerance)
    $items=@()
    foreach ($v in $visuals) {
        $col=0; $bestX=[double]::MaxValue
        for ($i=0; $i -lt $columnClusters.Count; $i++) { $d=[Math]::Abs($v.X-$columnClusters[$i].Center); if ($d -lt $bestX) { $bestX=$d; $col=$i } }
        $row=0; $bestY=[double]::MaxValue
        for ($i=0; $i -lt $rowClusters.Count; $i++) { $d=[Math]::Abs($v.Y-$rowClusters[$i].Center); if ($d -lt $bestY) { $bestY=$d; $row=$i } }
        $colSpan=1; if ($medianWidth -gt 0) { $colSpan=[Math]::Max(1,[int][Math]::Round($v.Width/$medianWidth)) }
        $rowSpan=1; if ($medianHeight -gt 0) { $rowSpan=[Math]::Max(1,[int][Math]::Round($v.Height/$medianHeight)) }
        if ($columnClusters.Count -gt 0) { $colSpan=[Math]::Min($colSpan,$columnClusters.Count-$col) }
        if ($rowClusters.Count -gt 0) { $rowSpan=[Math]::Min($rowSpan,$rowClusters.Count-$row) }
        $items += [pscustomobject]@{ Id=$v.Id; VisualType=$v.VisualType; FilePath=$v.FilePath; SourceHash=$v.FileHash; X=$v.X; Y=$v.Y; Width=$v.Width; Height=$v.Height; Column=$col; Row=$row; ColumnSpan=[Math]::Max(1,$colSpan); RowSpan=[Math]::Max(1,$rowSpan); IsLarge=(($v.Width -gt ($medianWidth*1.6)) -or ($v.Height -gt ($medianHeight*1.6))) }
    }
    [pscustomobject]@{ PageWidth=[double]$PageSnapshot.Width; PageHeight=[double]$PageSnapshot.Height; VisualCount=$visuals.Count; MedianWidth=$medianWidth; MedianHeight=$medianHeight; ColumnTolerance=$xTolerance; RowTolerance=$yTolerance; ColumnCount=[Math]::Max(1,$columnClusters.Count); RowCount=[Math]::Max(1,$rowClusters.Count); ColumnStarts=@($columnClusters | ForEach-Object { $_.Center }); RowStarts=@($rowClusters | ForEach-Object { $_.Center }); Items=$items }
}

Export-ModuleMember -Function Get-PbiLayoutAnalysis
