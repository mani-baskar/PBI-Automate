Set-StrictMode -Version 2.0

function Read-JsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('JSON file not found: {0}' -f $Path) }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { throw ('Invalid JSON in "{0}": {1}' -f $Path, $_.Exception.Message) }
}

function Get-OptionalPropertyValue {
    param([Parameter(Mandatory=$true)]$Object,[Parameter(Mandatory=$true)][string]$Name,$Default=$null)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function Get-PbiPages {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ReportFolder)
    $pagesDir = Join-Path $ReportFolder 'definition\pages'
    if (-not (Test-Path -LiteralPath $pagesDir -PathType Container)) { throw 'Enhanced PBIR pages folder not found.' }
    $pagesJsonPath = Join-Path $pagesDir 'pages.json'
    $pagesMeta = $null
    if (Test-Path -LiteralPath $pagesJsonPath -PathType Leaf) { $pagesMeta = Read-JsonFile -Path $pagesJsonPath }
    $order = @()
    if ($null -ne $pagesMeta) {
        foreach ($candidate in @('pageOrder','pages')) {
            if ($pagesMeta.PSObject.Properties.Name -contains $candidate) {
                foreach ($entry in @($pagesMeta.$candidate)) {
                    if ($entry -is [string]) { $order += [string]$entry }
                    elseif ($null -ne $entry -and $entry.PSObject.Properties.Name -contains 'name') { $order += [string]$entry.name }
                }
                if ($order.Count -gt 0) { break }
            }
        }
    }
    $pages = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $pagesDir -Directory -ErrorAction Stop)) {
        $pagePath = Join-Path $dir.FullName 'page.json'
        if (-not (Test-Path -LiteralPath $pagePath -PathType Leaf)) { continue }
        $page = Read-JsonFile -Path $pagePath
        $name = [string](Get-OptionalPropertyValue -Object $page -Name 'name' -Default $dir.Name)
        $displayName = [string](Get-OptionalPropertyValue -Object $page -Name 'displayName' -Default $name)
        $width = [double](Get-OptionalPropertyValue -Object $page -Name 'width' -Default 0)
        $height = [double](Get-OptionalPropertyValue -Object $page -Name 'height' -Default 0)
        $orderIndex = [int]::MaxValue
        for ($i=0; $i -lt $order.Count; $i++) { if ($order[$i] -eq $name -or $order[$i] -eq $dir.Name) { $orderIndex=$i; break } }
        $pages += [pscustomobject]@{ Id=$dir.Name; Name=$name; DisplayName=$displayName; Width=$width; Height=$height; PageFolder=$dir.FullName; PageJson=$pagePath; OrderIndex=$orderIndex }
    }
    return @($pages | Sort-Object OrderIndex, DisplayName)
}

function Get-PbiPageVisuals {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$PageFolder)
    $visualsDir = Join-Path $PageFolder 'visuals'
    if (-not (Test-Path -LiteralPath $visualsDir -PathType Container)) { return @() }
    $result = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $visualsDir -Directory -ErrorAction Stop)) {
        $visualPath = Join-Path $dir.FullName 'visual.json'
        if (-not (Test-Path -LiteralPath $visualPath -PathType Leaf)) { continue }
        $visual = Read-JsonFile -Path $visualPath
        if (-not ($visual.PSObject.Properties.Name -contains 'position')) { continue }
        $p = $visual.position
        $visualType = $null
        if ($visual.PSObject.Properties.Name -contains 'visual' -and $null -ne $visual.visual -and $visual.visual.PSObject.Properties.Name -contains 'visualType') { $visualType=[string]$visual.visual.visualType }
        $x=[double](Get-OptionalPropertyValue -Object $p -Name 'x' -Default 0); $y=[double](Get-OptionalPropertyValue -Object $p -Name 'y' -Default 0)
        $w=[double](Get-OptionalPropertyValue -Object $p -Name 'width' -Default 0); $h=[double](Get-OptionalPropertyValue -Object $p -Name 'height' -Default 0)
        if ($w -le 0 -or $h -le 0) { continue }
        $result += [pscustomobject]@{ Id=$dir.Name; VisualType=$visualType; FilePath=$visualPath; X=$x; Y=$y; Width=$w; Height=$h; Right=$x+$w; Bottom=$y+$h; CenterX=$x+($w/2.0); CenterY=$y+($h/2.0) }
    }
    return @($result | Sort-Object Y, X)
}

function Get-PbiPageSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Page)
    $visuals=@(Get-PbiPageVisuals -PageFolder $Page.PageFolder); $width=[double]$Page.Width; $height=[double]$Page.Height
    if ($width -le 0 -and $visuals.Count -gt 0) { $width=[Math]::Ceiling(($visuals | Measure-Object -Property Right -Maximum).Maximum) }
    if ($height -le 0 -and $visuals.Count -gt 0) { $height=[Math]::Ceiling(($visuals | Measure-Object -Property Bottom -Maximum).Maximum) }
    [pscustomobject]@{ Id=$Page.Id; Name=$Page.Name; DisplayName=$Page.DisplayName; Width=$width; Height=$height; PageFolder=$Page.PageFolder; Visuals=$visuals }
}

Export-ModuleMember -Function Get-PbiPages, Get-PbiPageVisuals, Get-PbiPageSnapshot
