Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-LayoutPreviewPanel {
    [CmdletBinding()]
    param([string]$Title='Preview')
    $panel = New-Object Windows.Forms.Panel
    $panel.Dock = 'Fill'
    $panel.BackColor = [Drawing.Color]::FromArgb(248,250,252)
    $panel.BorderStyle = 'FixedSingle'
    $panel.Tag = [pscustomobject]@{ Title=$Title; PageWidth=0.0; PageHeight=0.0; Items=@(); Mode='Current' }
    $panel.Add_Paint({
        param($sender,$e)
        $data = $sender.Tag
        $g = $e.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear($sender.BackColor)
        $titleFont = New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold)
        $itemFont = New-Object Drawing.Font('Segoe UI',7)
        try {
            $g.DrawString([string]$data.Title,$titleFont,[Drawing.Brushes]::DimGray,8,6)
            if ($data.PageWidth -le 0 -or $data.PageHeight -le 0) { return }
            $pad = 18.0; $top = 28.0
            $availableW = [Math]::Max(10,$sender.ClientSize.Width-(2*$pad))
            $availableH = [Math]::Max(10,$sender.ClientSize.Height-$top-$pad)
            $scale = [Math]::Min($availableW/$data.PageWidth,$availableH/$data.PageHeight)
            $pageW=$data.PageWidth*$scale; $pageH=$data.PageHeight*$scale
            $left=($sender.ClientSize.Width-$pageW)/2.0; $pageTop=$top+([Math]::Max(0,($availableH-$pageH)/2.0))
            $pageRect = New-Object Drawing.RectangleF([single]$left,[single]$pageTop,[single]$pageW,[single]$pageH)
            $g.FillRectangle([Drawing.Brushes]::White,$pageRect)
            $g.DrawRectangle([Drawing.Pens]::Silver,[int]$pageRect.X,[int]$pageRect.Y,[int]$pageRect.Width,[int]$pageRect.Height)
            foreach ($item in @($data.Items)) {
                $r = New-Object Drawing.RectangleF([single]($left+$item.X*$scale),[single]($pageTop+$item.Y*$scale),[single]($item.Width*$scale),[single]($item.Height*$scale))
                $fill = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(40,37,99,235))
                $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(37,99,235),1)
                try { $g.FillRectangle($fill,$r); $g.DrawRectangle($pen,[int]$r.X,[int]$r.Y,[int]$r.Width,[int]$r.Height) } finally { $fill.Dispose(); $pen.Dispose() }
                if ($r.Width -gt 28 -and $r.Height -gt 16) { $g.DrawString(([string]$item.Id).Substring(0,[Math]::Min(6,([string]$item.Id).Length)),$itemFont,[Drawing.Brushes]::MidnightBlue,$r.X+2,$r.Y+2) }
            }
        } finally { $titleFont.Dispose(); $itemFont.Dispose() }
    })
    return $panel
}

function Set-LayoutPreviewData {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Panel,[Parameter(Mandatory=$true)][double]$PageWidth,[Parameter(Mandatory=$true)][double]$PageHeight,[object[]]$Items,[string]$Title='Preview')
    $Panel.Tag = [pscustomobject]@{ Title=$Title; PageWidth=$PageWidth; PageHeight=$PageHeight; Items=@($Items) }
    $Panel.Invalidate()
}

Export-ModuleMember -Function New-LayoutPreviewPanel, Set-LayoutPreviewData
