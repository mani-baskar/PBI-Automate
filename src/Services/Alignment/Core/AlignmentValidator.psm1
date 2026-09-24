Set-StrictMode -Version 2.0

function Test-RectangleOverlap {
    param($A,$B)
    return ($A.X -lt ($B.X + $B.Width)) -and (($A.X + $A.Width) -gt $B.X) -and ($A.Y -lt ($B.Y + $B.Height)) -and (($A.Y + $A.Height) -gt $B.Y)
}

function Test-IntentionalOverlapItem {
    param(
        [Parameter(Mandatory=$true)]$Item,
        [Parameter(Mandatory=$true)]$Layout
    )

    if ($Item.PSObject.Properties.Name -contains 'AllowOverlap' -and [bool]$Item.AllowOverlap) {
        return $true
    }

    $effectiveHidden = $false
    if ($Item.PSObject.Properties.Name -contains 'EffectiveHidden') {
        $effectiveHidden = [bool]$Item.EffectiveHidden
    }
    elseif ($Item.PSObject.Properties.Name -contains 'IsHidden') {
        $effectiveHidden = [bool]$Item.IsHidden
    }

    if ($effectiveHidden -or
        ($Item.PSObject.Properties.Name -contains 'IsVisualGroup' -and [bool]$Item.IsVisualGroup)) {
        return $true
    }

    if ([double]$Layout.PageWidth -le 0 -or [double]$Layout.PageHeight -le 0) {
        return $false
    }

    $widthRatio = [double]$Item.Width / [double]$Layout.PageWidth
    $heightRatio = [double]$Item.Height / [double]$Layout.PageHeight

    if ($widthRatio -ge 0.90 -and $heightRatio -ge 0.90) {
        return $true
    }

    $type = ([string]$Item.VisualType).ToLowerInvariant()
    $structuralTypes = @(
        'textbox',
        'shape',
        'basicshape',
        'image',
        'button',
        'actionbutton',
        'navigationbutton',
        'pagenavigator',
        'bookmarknavigator',
        'visualgroup'
    )

    if ($structuralTypes -notcontains $type) {
        return $false
    }

    return (($widthRatio -ge 0.75 -and $heightRatio -le 0.18) -or
            ($heightRatio -ge 0.75 -and $widthRatio -le 0.18))
}

function Test-PbiLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Layout)

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $items = @($Layout.Items)

    if ($Layout.PageWidth -le 0 -or $Layout.PageHeight -le 0) { $errors.Add('Page width and height must be positive.') }
    if ($items.Count -eq 0) { $errors.Add('No supported visual items were supplied.') }

    $ids = @{}
    foreach ($item in $items) {
        if ([string]::IsNullOrWhiteSpace([string]$item.Id)) { $errors.Add('A visual is missing its identifier.'); continue }
        if ($ids.ContainsKey([string]$item.Id)) { $errors.Add(('Duplicate visual identifier: {0}' -f $item.Id)) } else { $ids[[string]$item.Id] = $true }
        foreach ($name in @('X','Y','Width','Height')) {
            $value = [double]$item.$name
            if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { $errors.Add(('{0}: {1} is not a finite number.' -f $item.Id,$name)) }
        }
        if ($item.X -lt 0 -or $item.Y -lt 0) { $errors.Add(('{0}: visual starts outside the page.' -f $item.Id)) }
        if ($item.Width -le 0 -or $item.Height -le 0) { $errors.Add(('{0}: width/height must be positive.' -f $item.Id)) }
        if (($item.X + $item.Width) -gt ($Layout.PageWidth + 0.01)) { $errors.Add(('{0}: visual exceeds page width.' -f $item.Id)) }
        if (($item.Y + $item.Height) -gt ($Layout.PageHeight + 0.01)) { $errors.Add(('{0}: visual exceeds page height.' -f $item.Id)) }
        if (-not (Test-Path -LiteralPath $item.FilePath -PathType Leaf)) {
            $errors.Add(('{0}: source visual.json no longer exists.' -f $item.Id))
        } elseif ($item.PSObject.Properties.Name -contains 'SourceHash' -and -not [string]::IsNullOrWhiteSpace([string]$item.SourceHash)) {
            $currentHash = (Get-FileHash -LiteralPath $item.FilePath -Algorithm SHA256).Hash
            if ($currentHash -ne [string]$item.SourceHash) {
                $errors.Add(('{0}: visual.json changed after analysis. Re-analyze before applying.' -f $item.Id))
            }
        } elseif ($item.PSObject.Properties.Name -contains 'FileHash' -and -not [string]::IsNullOrWhiteSpace([string]$item.FileHash)) {
            $currentHash = (Get-FileHash -LiteralPath $item.FilePath -Algorithm SHA256).Hash
            if ($currentHash -ne [string]$item.FileHash) {
                $errors.Add(('{0}: visual.json changed while validating. Reload the page.' -f $item.Id))
            }
        }
    }

    for ($i=0; $i -lt $items.Count; $i++) {
        for ($j=$i+1; $j -lt $items.Count; $j++) {
            $allowA = Test-IntentionalOverlapItem -Item $items[$i] -Layout $Layout
            $allowB = Test-IntentionalOverlapItem -Item $items[$j] -Layout $Layout

            if (-not $allowA -and -not $allowB -and (Test-RectangleOverlap -A $items[$i] -B $items[$j])) {
                $errors.Add(('Overlap detected between {0} and {1}.' -f $items[$i].Id,$items[$j].Id))
            }
        }
    }

    [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors)
        Warnings = @($warnings)
        VisualCount = $items.Count
    }
}

Export-ModuleMember -Function Test-PbiLayout
