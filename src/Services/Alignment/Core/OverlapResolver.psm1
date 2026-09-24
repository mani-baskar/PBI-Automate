Set-StrictMode -Version 2.0

function Test-AlignmentRectOverlap {
    param(
        [Parameter(Mandatory=$true)]$A,
        [Parameter(Mandatory=$true)]$B,
        [double]$Gap = 0
    )

    return (
        ([double]$A.X -lt ([double]$B.X + [double]$B.Width + $Gap)) -and
        (([double]$A.X + [double]$A.Width + $Gap) -gt [double]$B.X) -and
        ([double]$A.Y -lt ([double]$B.Y + [double]$B.Height + $Gap)) -and
        (([double]$A.Y + [double]$A.Height + $Gap) -gt [double]$B.Y)
    )
}

function Get-AlignmentOverlapPairs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [double]$Gap = 0
    )

    $pairs = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        for ($j = $i + 1; $j -lt $Items.Count; $j++) {
            if (Test-AlignmentRectOverlap -A $Items[$i] -B $Items[$j] -Gap $Gap) {
                $pairs += [pscustomobject]@{
                    A = $Items[$i]
                    B = $Items[$j]
                }
            }
        }
    }

    return @($pairs)
}

function Test-AlignmentPlacementFree {
    param(
        [Parameter(Mandatory=$true)]$Candidate,
        [Parameter(Mandatory=$true)][object[]]$Placed,
        [Parameter(Mandatory=$true)][double]$Left,
        [Parameter(Mandatory=$true)][double]$Top,
        [Parameter(Mandatory=$true)][double]$Right,
        [Parameter(Mandatory=$true)][double]$Bottom,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    if ([double]$Candidate.X -lt ($Left - 0.001) -or
        [double]$Candidate.Y -lt ($Top - 0.001) -or
        ([double]$Candidate.X + [double]$Candidate.Width) -gt ($Right + 0.001) -or
        ([double]$Candidate.Y + [double]$Candidate.Height) -gt ($Bottom + 0.001)) {
        return $false
    }

    foreach ($other in @($Placed)) {
        if (Test-AlignmentRectOverlap -A $Candidate -B $other -Gap $Gap) {
            return $false
        }
    }

    return $true
}

function Get-AlignmentCandidateCoordinates {
    param(
        [Parameter(Mandatory=$true)]$Item,
        [Parameter(Mandatory=$true)][object[]]$Placed,
        [Parameter(Mandatory=$true)][double]$Left,
        [Parameter(Mandatory=$true)][double]$Top,
        [Parameter(Mandatory=$true)][double]$Right,
        [Parameter(Mandatory=$true)][double]$Bottom,
        [Parameter(Mandatory=$true)][double]$Gap,
        [Parameter(Mandatory=$true)][double]$Width,
        [Parameter(Mandatory=$true)][double]$Height
    )

    $xs = New-Object System.Collections.Generic.List[double]
    $ys = New-Object System.Collections.Generic.List[double]

    foreach ($x in @([double]$Item.X,$Left,($Right - $Width))) {
        if (-not $xs.Contains([double]$x)) { $xs.Add([double]$x) }
    }
    foreach ($y in @([double]$Item.Y,$Top,($Bottom - $Height))) {
        if (-not $ys.Contains([double]$y)) { $ys.Add([double]$y) }
    }

    foreach ($other in @($Placed)) {
        foreach ($x in @(
            ([double]$other.X + [double]$other.Width + $Gap),
            ([double]$other.X - $Width - $Gap)
        )) {
            if (-not $xs.Contains([double]$x)) { $xs.Add([double]$x) }
        }

        foreach ($y in @(
            ([double]$other.Y + [double]$other.Height + $Gap),
            ([double]$other.Y - $Height - $Gap)
        )) {
            if (-not $ys.Contains([double]$y)) { $ys.Add([double]$y) }
        }
    }

    $candidates = @()

    foreach ($x in $xs) {
        foreach ($y in $ys) {
            $clampedX = [Math]::Max($Left,[Math]::Min(($Right - $Width),[double]$x))
            $clampedY = [Math]::Max($Top,[Math]::Min(($Bottom - $Height),[double]$y))

            if (($Right - $Width) -lt $Left -or ($Bottom - $Height) -lt $Top) {
                continue
            }

            $distanceX = $clampedX - [double]$Item.X
            $distanceY = $clampedY - [double]$Item.Y

            $candidates += [pscustomobject]@{
                X = $clampedX
                Y = $clampedY
                Width = $Width
                Height = $Height
                Distance = [Math]::Sqrt(($distanceX * $distanceX) + ($distanceY * $distanceY))
            }
        }
    }

    return @($candidates | Sort-Object Distance, Y, X)
}

function Find-NearestFreeAlignmentPlacement {
    param(
        [Parameter(Mandatory=$true)]$Item,
        [Parameter(Mandatory=$true)][object[]]$Placed,
        [Parameter(Mandatory=$true)][double]$Left,
        [Parameter(Mandatory=$true)][double]$Top,
        [Parameter(Mandatory=$true)][double]$Right,
        [Parameter(Mandatory=$true)][double]$Bottom,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    # Preserve size first. Only shrink when the current content area genuinely
    # cannot accommodate the visual without an overlap.
    $scales = @(1.00,0.95,0.90,0.85,0.80,0.75,0.70,0.65,0.60,0.55,0.50,0.45,0.40)

    foreach ($scale in $scales) {
        $width = [double]$Item.Width * $scale
        $height = [double]$Item.Height * $scale

        if ($width -le 1 -or $height -le 1) { continue }
        if ($width -gt ($Right - $Left) -or $height -gt ($Bottom - $Top)) { continue }

        $candidates = @(Get-AlignmentCandidateCoordinates -Item $Item -Placed $Placed -Left $Left -Top $Top -Right $Right -Bottom $Bottom -Gap $Gap -Width $width -Height $height)

        foreach ($candidate in $candidates) {
            if (Test-AlignmentPlacementFree -Candidate $candidate -Placed $Placed -Left $Left -Top $Top -Right $Right -Bottom $Bottom -Gap $Gap) {
                return [pscustomobject]@{
                    Found = $true
                    X = [double]$candidate.X
                    Y = [double]$candidate.Y
                    Width = [double]$candidate.Width
                    Height = [double]$candidate.Height
                    Scale = [double]$scale
                    Distance = [double]$candidate.Distance
                }
            }
        }
    }

    return [pscustomobject]@{
        Found = $false
        X = [double]$Item.X
        Y = [double]$Item.Y
        Width = [double]$Item.Width
        Height = [double]$Item.Height
        Scale = 1.0
        Distance = 0.0
    }
}

function Get-CompactShelfAlignmentPlacements {
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [Parameter(Mandatory=$true)][double]$Left,
        [Parameter(Mandatory=$true)][double]$Top,
        [Parameter(Mandatory=$true)][double]$Right,
        [Parameter(Mandatory=$true)][double]$Bottom,
        [Parameter(Mandatory=$true)][double]$Gap
    )

    $ordered = @($Items | Sort-Object Y, X, @{Expression={ [double]$_.Width * [double]$_.Height };Descending=$true})
    $scales = @(1.00,0.95,0.90,0.85,0.80,0.75,0.70,0.65,0.60,0.55,0.50,0.45,0.40,0.35,0.30,0.25)

    foreach ($scale in $scales) {
        $cursorX = $Left
        $cursorY = $Top
        $rowHeight = 0.0
        $placements = @{}
        $failed = $false

        foreach ($item in $ordered) {
            $width = [double]$item.Width * $scale
            $height = [double]$item.Height * $scale

            if ($width -gt ($Right - $Left) -or $height -gt ($Bottom - $Top) -or $width -le 1 -or $height -le 1) {
                $failed = $true
                break
            }

            if (($cursorX + $width) -gt ($Right + 0.001) -and $cursorX -gt ($Left + 0.001)) {
                $cursorX = $Left
                $cursorY += $rowHeight + $Gap
                $rowHeight = 0.0
            }

            if (($cursorY + $height) -gt ($Bottom + 0.001)) {
                $failed = $true
                break
            }

            $placements[[string]$item.Id] = [pscustomobject]@{
                Id = $item.Id
                X = [double]$cursorX
                Y = [double]$cursorY
                Width = $width
                Height = $height
            }

            $cursorX += $width + $Gap
            $rowHeight = [Math]::Max($rowHeight,$height)
        }

        if (-not $failed -and $placements.Count -eq $ordered.Count) {
            return [pscustomobject]@{
                Found = $true
                Scale = [double]$scale
                Placements = $placements
            }
        }
    }

    return [pscustomobject]@{
        Found = $false
        Scale = 1.0
        Placements = @{}
    }
}

function Copy-AlignmentSnapshotVisual {
    param(
        [Parameter(Mandatory=$true)]$Visual,
        [Parameter(Mandatory=$true)][double]$X,
        [Parameter(Mandatory=$true)][double]$Y,
        [Parameter(Mandatory=$true)][double]$Width,
        [Parameter(Mandatory=$true)][double]$Height
    )

    [pscustomobject]@{
        Id = $Visual.Id
        ObjectName = $(if ($Visual.PSObject.Properties.Name -contains 'ObjectName') { $Visual.ObjectName } else { $Visual.Id })
        VisualType = $Visual.VisualType
        FilePath = $Visual.FilePath
        FileHash = $Visual.FileHash
        ParentGroupName = $Visual.ParentGroupName
        IsVisualGroup = $Visual.IsVisualGroup
        GroupMode = $(if ($Visual.PSObject.Properties.Name -contains 'GroupMode') { $Visual.GroupMode } else { '' })
        IsHidden = $Visual.IsHidden
        EffectiveHidden = $(if ($Visual.PSObject.Properties.Name -contains 'EffectiveHidden') { [bool]$Visual.EffectiveHidden } else { [bool]$Visual.IsHidden })
        HiddenReason = $(if ($Visual.PSObject.Properties.Name -contains 'HiddenReason') { $Visual.HiddenReason } else { '' })
        OriginalX = $(if ($Visual.PSObject.Properties.Name -contains 'OriginalX') { [double]$Visual.OriginalX } else { [double]$Visual.X })
        OriginalY = $(if ($Visual.PSObject.Properties.Name -contains 'OriginalY') { [double]$Visual.OriginalY } else { [double]$Visual.Y })
        OriginalWidth = $(if ($Visual.PSObject.Properties.Name -contains 'OriginalWidth') { [double]$Visual.OriginalWidth } else { [double]$Visual.Width })
        OriginalHeight = $(if ($Visual.PSObject.Properties.Name -contains 'OriginalHeight') { [double]$Visual.OriginalHeight } else { [double]$Visual.Height })
        X = [Math]::Round($X,3)
        Y = [Math]::Round($Y,3)
        Width = [Math]::Round($Width,3)
        Height = [Math]::Round($Height,3)
        Right = [Math]::Round(($X + $Width),3)
        Bottom = [Math]::Round(($Y + $Height),3)
        CenterX = [Math]::Round(($X + ($Width / 2.0)),3)
        CenterY = [Math]::Round(($Y + ($Height / 2.0)),3)
    }
}

function Resolve-PbiSnapshotOverlaps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$PageSnapshot,
        [Parameter(Mandatory=$true)]$InitialAnalysis,
        [ValidateRange(0,500)][double]$Margin = 5,
        [ValidateRange(0,500)][double]$Gap = 5
    )

    $managed = @($InitialAnalysis.Items | Where-Object { -not [bool]$_.IsLocked })
    $overlapPairs = @(Get-AlignmentOverlapPairs -Items $managed -Gap 0)

    if ($overlapPairs.Count -eq 0) {
        return [pscustomobject]@{
            Snapshot = $PageSnapshot
            HadOverlaps = $false
            InitialOverlapPairCount = 0
            RemainingOverlapPairCount = 0
            MovedCount = 0
            ResizedCount = 0
            Resolved = $true
            UsedCompactFallback = $false
            Actions = @()
        }
    }

    $contentLeft = if ([double]$InitialAnalysis.ReservedLeft -gt 0) { [double]$InitialAnalysis.ReservedLeft + $Gap } else { $Margin }
    $contentTop = if ([double]$InitialAnalysis.ReservedTop -gt 0) { [double]$InitialAnalysis.ReservedTop + $Gap } else { $Margin }
    $contentRight = if ([double]$InitialAnalysis.ReservedRight -lt [double]$InitialAnalysis.PageWidth) { [double]$InitialAnalysis.ReservedRight - $Gap } else { [double]$InitialAnalysis.PageWidth - $Margin }
    $contentBottom = if ([double]$InitialAnalysis.ReservedBottom -lt [double]$InitialAnalysis.PageHeight) { [double]$InitialAnalysis.ReservedBottom - $Gap } else { [double]$InitialAnalysis.PageHeight - $Margin }

    if ($contentRight -le $contentLeft -or $contentBottom -le $contentTop) {
        throw 'Overlap normalization cannot find a usable content area after protected regions are reserved.'
    }

    $managedById = @{}
    foreach ($item in $managed) { $managedById[[string]$item.Id] = $item }

    # Stable top-left order means an already-correct primary visual wins.
    # Later overlapping visuals move around it rather than shifting both.
    $ordered = @($managed | Sort-Object Y, X, @{Expression={ [double]$_.Width * [double]$_.Height };Descending=$true})
    $placed = @()
    $normalized = @{}
    $actions = @()
    $movedCount = 0
    $resizedCount = 0

    foreach ($item in $ordered) {
        $originalCandidate = [pscustomobject]@{
            X = [double]$item.X
            Y = [double]$item.Y
            Width = [double]$item.Width
            Height = [double]$item.Height
        }

        if (Test-AlignmentPlacementFree -Candidate $originalCandidate -Placed $placed -Left $contentLeft -Top $contentTop -Right $contentRight -Bottom $contentBottom -Gap 0) {
            $placement = [pscustomobject]@{
                Found = $true
                X = [double]$item.X
                Y = [double]$item.Y
                Width = [double]$item.Width
                Height = [double]$item.Height
                Scale = 1.0
                Distance = 0.0
            }
        }
        else {
            $placement = Find-NearestFreeAlignmentPlacement -Item $item -Placed $placed -Left $contentLeft -Top $contentTop -Right $contentRight -Bottom $contentBottom -Gap $Gap
        }

        if (-not $placement.Found) {
            # Keep the original geometry in the virtual snapshot. The service
            # will report the unresolved pair and final Apply remains blocked.
            $placement = [pscustomobject]@{
                Found = $false
                X = [double]$item.X
                Y = [double]$item.Y
                Width = [double]$item.Width
                Height = [double]$item.Height
                Scale = 1.0
                Distance = 0.0
            }
        }

        $placedItem = [pscustomobject]@{
            Id = $item.Id
            X = [double]$placement.X
            Y = [double]$placement.Y
            Width = [double]$placement.Width
            Height = [double]$placement.Height
        }
        $placed += $placedItem
        $normalized[[string]$item.Id] = $placedItem

        $moved = ([Math]::Abs([double]$item.X - [double]$placement.X) -gt 0.001 -or
                  [Math]::Abs([double]$item.Y - [double]$placement.Y) -gt 0.001)
        $resized = ([Math]::Abs([double]$item.Width - [double]$placement.Width) -gt 0.001 -or
                    [Math]::Abs([double]$item.Height - [double]$placement.Height) -gt 0.001)

        if ($moved) { $movedCount++ }
        if ($resized) { $resizedCount++ }

        if ($moved -or $resized -or -not $placement.Found) {
            $actions += [pscustomobject]@{
                Id = $item.Id
                Resolved = [bool]$placement.Found
                OldX = [double]$item.X
                OldY = [double]$item.Y
                OldWidth = [double]$item.Width
                OldHeight = [double]$item.Height
                X = [double]$placement.X
                Y = [double]$placement.Y
                Width = [double]$placement.Width
                Height = [double]$placement.Height
                Scale = [double]$placement.Scale
                Distance = [double]$placement.Distance
            }
        }
    }

    $usedCompactFallback = $false

    $provisionalManaged = @()
    foreach ($item in $managed) {
        $g = $normalized[[string]$item.Id]
        $provisionalManaged += [pscustomobject]@{
            Id = $item.Id
            X = [double]$g.X
            Y = [double]$g.Y
            Width = [double]$g.Width
            Height = [double]$g.Height
        }
    }

    $provisionalRemaining = @(Get-AlignmentOverlapPairs -Items $provisionalManaged -Gap 0)

    if ($provisionalRemaining.Count -gt 0) {
        # No nearest same-size/shrunk slot was sufficient. Compact all active
        # content visuals into the available content rectangle as a last resort,
        # preserving their relative reading order and aspect ratios.
        $compact = Get-CompactShelfAlignmentPlacements -Items $managed -Left $contentLeft -Top $contentTop -Right $contentRight -Bottom $contentBottom -Gap $Gap

        if ($compact.Found) {
            $usedCompactFallback = $true
            $normalized = $compact.Placements
            $actions = @()
            $movedCount = 0
            $resizedCount = 0

            foreach ($item in $managed) {
                $g = $normalized[[string]$item.Id]
                $moved = ([Math]::Abs([double]$item.X - [double]$g.X) -gt 0.001 -or
                          [Math]::Abs([double]$item.Y - [double]$g.Y) -gt 0.001)
                $resized = ([Math]::Abs([double]$item.Width - [double]$g.Width) -gt 0.001 -or
                            [Math]::Abs([double]$item.Height - [double]$g.Height) -gt 0.001)

                if ($moved) { $movedCount++ }
                if ($resized) { $resizedCount++ }

                if ($moved -or $resized) {
                    $actions += [pscustomobject]@{
                        Id = $item.Id
                        Resolved = $true
                        OldX = [double]$item.X
                        OldY = [double]$item.Y
                        OldWidth = [double]$item.Width
                        OldHeight = [double]$item.Height
                        X = [double]$g.X
                        Y = [double]$g.Y
                        Width = [double]$g.Width
                        Height = [double]$g.Height
                        Scale = [double]$compact.Scale
                        Distance = [Math]::Sqrt(
                            ([double]$g.X - [double]$item.X) * ([double]$g.X - [double]$item.X) +
                            ([double]$g.Y - [double]$item.Y) * ([double]$g.Y - [double]$item.Y)
                        )
                    }
                }
            }
        }
    }

    $newVisuals = @()

    foreach ($visual in @($PageSnapshot.Visuals)) {
        if ($normalized.ContainsKey([string]$visual.Id)) {
            $g = $normalized[[string]$visual.Id]
            $newVisuals += Copy-AlignmentSnapshotVisual -Visual $visual -X ([double]$g.X) -Y ([double]$g.Y) -Width ([double]$g.Width) -Height ([double]$g.Height)
        }
        else {
            $newVisuals += Copy-AlignmentSnapshotVisual -Visual $visual -X ([double]$visual.X) -Y ([double]$visual.Y) -Width ([double]$visual.Width) -Height ([double]$visual.Height)
        }
    }

    $normalizedSnapshot = [pscustomobject]@{
        Id = $PageSnapshot.Id
        Name = $PageSnapshot.Name
        DisplayName = $PageSnapshot.DisplayName
        Width = [double]$PageSnapshot.Width
        Height = [double]$PageSnapshot.Height
        PageFolder = $PageSnapshot.PageFolder
        Visuals = $newVisuals
    }

    $normalizedManaged = @()
    foreach ($item in $managed) {
        $g = $normalized[[string]$item.Id]
        $normalizedManaged += [pscustomobject]@{
            Id = $item.Id
            X = [double]$g.X
            Y = [double]$g.Y
            Width = [double]$g.Width
            Height = [double]$g.Height
        }
    }

    $remaining = @(Get-AlignmentOverlapPairs -Items $normalizedManaged -Gap 0)

    [pscustomobject]@{
        Snapshot = $normalizedSnapshot
        HadOverlaps = $true
        InitialOverlapPairCount = $overlapPairs.Count
        RemainingOverlapPairCount = $remaining.Count
        MovedCount = $movedCount
        ResizedCount = $resizedCount
        Resolved = ($remaining.Count -eq 0)
        UsedCompactFallback = $usedCompactFallback
        Actions = $actions
    }
}

Export-ModuleMember -Function Resolve-PbiSnapshotOverlaps, Get-AlignmentOverlapPairs
