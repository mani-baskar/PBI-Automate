[CmdletBinding()]
param(
    [switch]$KeepFixture
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:TestSucceeded = $false

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

$sourceFiles = @(
    'Start-PBIAutomate.ps1',
    'src\Core\ConfigService.psm1',
    'src\Core\Logging.psm1',
    'src\Core\ProjectDiscovery.psm1',
    'src\Core\PBIRReader.psm1',
    'src\Services\ServiceRegistry.psm1',
    'src\Services\Alignment\Core\AlignmentAnalyzer.psm1',
    'src\Services\Alignment\Core\AlignmentLayoutEngine.psm1',
    'src\Services\Alignment\Core\AlignmentValidator.psm1',
    'src\Core\BackupService.psm1',
    'src\Core\PBIRWriter.psm1',
    'src\Core\UndoService.psm1',
    'src\Services\Alignment\AlignmentService.psm1',
    'src\UI\PreviewCanvas.psm1',
    'src\UI\MainForm.psm1'
)

foreach ($relative in $sourceFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $relative),[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw ('PowerShell syntax error in ' + $relative + ': ' + (($parseErrors | ForEach-Object { $_.Message }) -join ' | '))
    }
}

$modules = @(
    'src\Core\ConfigService.psm1',
    'src\Core\Logging.psm1',
    'src\Core\ProjectDiscovery.psm1',
    'src\Core\PBIRReader.psm1',
    'src\Core\BackupService.psm1',
    'src\Core\PBIRWriter.psm1',
    'src\Core\UndoService.psm1',
    'src\Services\ServiceRegistry.psm1',
    'src\Services\Alignment\Core\AlignmentAnalyzer.psm1',
    'src\Services\Alignment\Core\AlignmentLayoutEngine.psm1',
    'src\Services\Alignment\Core\AlignmentValidator.psm1',
    'src\Services\Alignment\AlignmentService.psm1',
    'src\UI\PreviewCanvas.psm1',
    'src\UI\MainForm.psm1'
)

foreach ($module in $modules) {
    Import-Module (Join-Path $repoRoot $module) -Force -ErrorAction Stop
}

$script:Passed = 0

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ('ASSERT FAILED: ' + $Message) }
    $script:Passed++
    Write-Host ('PASS  ' + $Message) -ForegroundColor Green
}

function Assert-Throws {
    param([scriptblock]$Action,[string]$Message)
    $thrown = $false
    try { & $Action } catch { $thrown = $true }
    Assert-True $thrown $Message
}

function Find-ControlByName {
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [Parameter(Mandatory=$true)][string]$Name
    )

    foreach ($control in $Parent.Controls) {
        if ([string]$control.Name -eq $Name) { return $control }
        if ($control.Controls.Count -gt 0) {
            $found = Find-ControlByName -Parent $control -Name $Name
            if ($null -ne $found) { return $found }
        }
    }
    return $null
}

function Write-Utf8NoBom {
    param([string]$Path,[string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path,$Content,(New-Object System.Text.UTF8Encoding($false)))
}

function New-TestVisual {
    param(
        [string]$PageFolder,
        [string]$Id,
        [double]$X,
        [double]$Y,
        [double]$Width,
        [double]$Height,
        [string]$Type
    )

    $path = Join-Path $PageFolder ('visuals\' + $Id + '\visual.json')
    $json = @"
{
  "name": "$Id",
  "position": {
    "x": $X,
    "y": $Y,
    "z": 0,
    "height": $Height,
    "width": $Width,
    "tabOrder": 0
  },
  "visual": {
    "visualType": "$Type",
    "objects": {
      "title": [{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}}}}]
    }
  },
  "filterConfig": {
    "filters": []
  }
}
"@
    Write-Utf8NoBom -Path $path -Content $json
    return $path
}

$fixtureRoot = Join-Path $env:TEMP ('PBI-Automate-V1-Test-' + [Guid]::NewGuid().ToString('N'))
$projectRoot = Join-Path $fixtureRoot 'Demo'
$reportFolder = Join-Path $projectRoot 'Demo.Report'
$pageFolder = Join-Path $reportFolder 'definition\pages\Friendly.Page'
$page2Folder = Join-Path $reportFolder 'definition\pages\Other.Page'

try {
    New-Item -ItemType Directory -Path $pageFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $page2Folder -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $projectRoot 'Demo.pbip') -Content '{"version":"1.0","artifacts":[{"report":{"path":"Demo.Report"}}]}'
    Write-Utf8NoBom -Path (Join-Path $reportFolder 'definition.pbir') -Content '{}'
    $decoyReport = Join-Path $projectRoot 'Decoy.Report'
    New-Item -ItemType Directory -Path (Join-Path $decoyReport 'definition\pages') -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $decoyReport 'definition.pbir') -Content '{}'
    Write-Utf8NoBom -Path (Join-Path $decoyReport 'definition\pages\pages.json') -Content '{"pageOrder":[],"activePageName":""}'
    Write-Utf8NoBom -Path (Join-Path $reportFolder 'definition\pages\pages.json') -Content '{"pageOrder":["Page1","Page2"],"activePageName":"Page1"}'
    Write-Utf8NoBom -Path (Join-Path $pageFolder 'page.json') -Content '{"name":"Page1","displayName":"Executive Summary","displayOption":"FitToPage","width":400,"height":300}'
    Write-Utf8NoBom -Path (Join-Path $page2Folder 'page.json') -Content '{"name":"Page2","displayName":"Other Page","displayOption":"FitToPage","width":400,"height":300}'

    $background = New-TestVisual -PageFolder $pageFolder -Id 'Background.Visual' -X 0 -Y 0 -Width 400 -Height 300 -Type 'shape'
    $header = New-TestVisual -PageFolder $pageFolder -Id 'Header.Visual' -X 0 -Y 0 -Width 400 -Height 40 -Type 'textbox'

    $groupContainer = Join-Path $pageFolder 'visuals\GroupContainer.Visual\visual.json'
    Write-Utf8NoBom -Path $groupContainer -Content '{"name":"Group1","position":{"x":20,"y":60,"z":0,"height":180,"width":360,"tabOrder":10},"isHidden":true,"visualGroup":{"displayName":"Grouped Area","groupMode":"ScaleMode"}}'

    $groupChild = Join-Path $pageFolder 'visuals\GroupChild.Visual\visual.json'
    Write-Utf8NoBom -Path $groupChild -Content '{"name":"GroupedChild","position":{"x":30,"y":70,"z":1,"height":80,"width":120,"tabOrder":11},"parentGroupName":"Group1","visual":{"visualType":"slicer"},"filterConfig":{"filters":[]}}'

    $hiddenVisual = Join-Path $pageFolder 'visuals\Hidden.Visual\visual.json'
    Write-Utf8NoBom -Path $hiddenVisual -Content '{"name":"Hidden1","position":{"x":200,"y":80,"z":2,"height":80,"width":120,"tabOrder":12},"isHidden":true,"visual":{"visualType":"card"},"filterConfig":{"filters":[]}}'

    $a = New-TestVisual -PageFolder $pageFolder -Id 'VisualA.Visual' -X 7.25 -Y 8.5 -Width 184.75 -Height 130.25 -Type 'card'
    $b = New-TestVisual -PageFolder $pageFolder -Id 'VisualB.Visual' -X 204.4 -Y 11.2 -Width 188.1 -Height 127.6 -Type 'card'
    $c = New-TestVisual -PageFolder $pageFolder -Id 'VisualC.Visual' -X 9.1 -Y 151.35 -Width 383.2 -Height 140.4 -Type 'barChart'

    $originalHash = @{}
    foreach ($path in @($background,$header,$groupContainer,$groupChild,$hiddenVisual,$a,$b,$c)) {
        $originalHash[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }

    Write-Host ''
    Write-Host 'PBI Automate V1 integration test' -ForegroundColor Cyan
    Write-Host ('Fixture: ' + $fixtureRoot)
    Write-Host ''

    Assert-True $true 'All PowerShell source files parse under Windows PowerShell 5.1'
    $config = Get-PBIAutomateConfig -RootPath $repoRoot
    Assert-True ([double]$config.layout.margin -eq 5 -and [double]$config.layout.gap -eq 5) 'Default configuration loads 5-unit margin and gap'
    $previewControl = New-LayoutPreviewPanel -Title 'CI Preview'
    Assert-True ($previewControl -is [System.Windows.Forms.Panel]) 'WinForms preview control can be created'
    $previewControl.Dispose()
    $mainForm = Show-PBIAutomateMainForm -RootPath $repoRoot -BuildOnly
    Assert-True ($mainForm -is [System.Windows.Forms.Form]) 'Full WinForms main window builds without showing it'
    Assert-True ($mainForm.Text -like 'PBI Automate*') 'Main window title is configured'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'PBIPButton')) 'Common PBIP project button exists'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'RefreshButton')) 'Common Refresh button replaces folder browsing'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'PageSelector')) 'Common page selector exists'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'Service_alignment')) 'Alignment Correction service appears in navigation'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'Service_formatting')) 'Change Format coming-soon service appears in navigation'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'Service_theme')) 'Theme Creation coming-soon service appears in navigation'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'Service_visual-copy-paste')) 'Visual Copy Paste coming-soon service appears in navigation'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'AlignmentOptionsPanel')) 'Alignment settings live in service options area'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'AlignmentPreviewArea')) 'Alignment preview lives below service options'
    Assert-True ($null -ne (Find-ControlByName -Parent $mainForm -Name 'ProcessingConsole')) 'Processing console remains in footer'
    $mainForm.Dispose()

    # The checked-in PBIP is a live manual fixture and may be intentionally
    # edited during desktop testing. Validate that the product can always load
    # and preview its current state without hard-coding yesterday's geometry.
    $realPbip = Join-Path $repoRoot 'tests\PBIP\Test Report.pbip'
    Assert-True (Test-Path -LiteralPath $realPbip -PathType Leaf) 'Checked-in PBIP manual fixture exists'

    $realProject = Resolve-PbiProject -Path $realPbip
    $realPages = @(Get-PbiPages -ReportFolder $realProject.ReportFolder)
    Assert-True ($realPages.Count -ge 1) 'Checked-in PBIP exposes at least one report page'

    $realPage = $realPages[0]
    $realSnapshot = Get-PbiPageSnapshot -Page $realPage
    Assert-True ($realSnapshot.Visuals.Count -ge 1) 'Checked-in PBIP page exposes visual geometry'

    $realServicePreview = Invoke-AlignmentPreview -PageSnapshot $realSnapshot -Config $config -Margin 10 -Gap 10
    Assert-True ($null -ne $realServicePreview.Analysis) 'Alignment service facade returns analysis for checked-in PBIP'
    Assert-True ($null -ne $realServicePreview.Layout) 'Alignment service facade returns a proposed layout'
    Assert-True $realServicePreview.Validation.IsValid 'Current checked-in PBIP alignment proposal validates'

    # Visible grouped children are active visuals; only the group container is structural.
    $visibleGrouped = [pscustomobject]@{
        Id='VisibleGroupedChild'; ObjectName='VisibleGroupedChild'; VisualType='card'; FilePath=$a; FileHash=(Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash;
        ParentGroupName='VisibleGroup'; IsVisualGroup=$false; GroupMode=''; IsHidden=$false; EffectiveHidden=$false; HiddenReason='';
        X=20.0; Y=20.0; Width=120.0; Height=80.0; Right=140.0; Bottom=100.0; CenterX=80.0; CenterY=60.0
    }
    $visibleGroupContainer = [pscustomobject]@{
        Id='VisibleGroup'; ObjectName='VisibleGroup'; VisualType='visualGroup'; FilePath=$groupContainer; FileHash=(Get-FileHash -LiteralPath $groupContainer -Algorithm SHA256).Hash;
        ParentGroupName=''; IsVisualGroup=$true; GroupMode='ScaleMode'; IsHidden=$false; EffectiveHidden=$false; HiddenReason='';
        X=0.0; Y=0.0; Width=300.0; Height=200.0; Right=300.0; Bottom=200.0; CenterX=150.0; CenterY=100.0
    }
    $visibleGroupSnapshot = [pscustomobject]@{ Width=400.0; Height=300.0; Visuals=@($visibleGroupContainer,$visibleGrouped) }
    $visibleGroupAnalysis = Get-PbiLayoutAnalysis -PageSnapshot $visibleGroupSnapshot
    Assert-True ($visibleGroupAnalysis.ManagedVisualCount -eq 1) 'Visible grouped child participates in alignment'
    Assert-True ($visibleGroupAnalysis.ActiveGroupedVisualCount -eq 1) 'Visible grouped child count is reported'
    Assert-True ($visibleGroupAnalysis.GroupContainerCount -eq 1) 'Visible group container is ignored as structure'

    # Synthetic anchor-priority case: top is the primary width anchor and
    # left is the primary height anchor when original dimensions differ only slightly.
    $anchorItems = @(
        [pscustomobject]@{ Id='ATop1'; VisualType='card'; FilePath=$a; SourceHash=''; ParentGroupName=''; IsVisualGroup=$false; IsHidden=$false; ProtectionReason=$null; X=0.0; Y=0.0; Width=200.0; Height=60.0; Column=0; Row=0; ColumnSpan=1; RowSpan=1; IsLocked=$false; AllowOverlap=$false },
        [pscustomobject]@{ Id='ATop2'; VisualType='card'; FilePath=$b; SourceHash=''; ParentGroupName=''; IsVisualGroup=$false; IsHidden=$false; ProtectionReason=$null; X=205.0; Y=0.0; Width=395.0; Height=60.0; Column=1; Row=0; ColumnSpan=2; RowSpan=1; IsLocked=$false; AllowOverlap=$false },
        [pscustomobject]@{ Id='ALeft1'; VisualType='tableEx'; FilePath=$a; SourceHash=''; ParentGroupName=''; IsVisualGroup=$false; IsHidden=$false; ProtectionReason=$null; X=0.0; Y=65.0; Width=202.0; Height=150.0; Column=0; Row=1; ColumnSpan=1; RowSpan=1; IsLocked=$false; AllowOverlap=$false },
        [pscustomobject]@{ Id='ALeft2'; VisualType='tableEx'; FilePath=$a; SourceHash=''; ParentGroupName=''; IsVisualGroup=$false; IsHidden=$false; ProtectionReason=$null; X=0.0; Y=220.0; Width=202.0; Height=180.0; Column=0; Row=2; ColumnSpan=1; RowSpan=1; IsLocked=$false; AllowOverlap=$false },
        [pscustomobject]@{ Id='AMain11'; VisualType='chart'; FilePath=$b; SourceHash=''; ParentGroupName=''; IsVisualGroup=$false; IsHidden=$false; ProtectionReason=$null; X=207.0; Y=66.0; Width=190.0; Height=148.0; Column=1; Row=1; ColumnSpan=1; RowSpan=1; IsLocked=$false; AllowOverlap=$false },
        [pscustomobject]@{ Id='AMain12'; VisualType='chart'; FilePath=$c; SourceHash=''; ParentGroupName=''; IsVisualGroup=$false; IsHidden=$false; ProtectionReason=$null; X=402.0; Y=66.0; Width=198.0; Height=149.0; Column=2; Row=1; ColumnSpan=1; RowSpan=1; IsLocked=$false; AllowOverlap=$false },
        [pscustomobject]@{ Id='AMain2'; VisualType='chart'; FilePath=$c; SourceHash=''; ParentGroupName=''; IsVisualGroup=$false; IsHidden=$false; ProtectionReason=$null; X=207.0; Y=221.0; Width=393.0; Height=178.0; Column=1; Row=2; ColumnSpan=2; RowSpan=1; IsLocked=$false; AllowOverlap=$false }
    )
    $anchorAnalysis = [pscustomobject]@{
        PageWidth=600.0; PageHeight=400.0; ColumnCount=3; RowCount=3;
        ReservedLeft=0.0; ReservedTop=0.0; ReservedRight=600.0; ReservedBottom=400.0;
        Items=$anchorItems
    }
    $anchorLayout = Get-SmartPbiLayout -Analysis $anchorAnalysis -Margin 5 -Gap 5
    $anchorTopLeft = @($anchorLayout.Items | Where-Object { $_.Id -eq 'ATop1' })[0]
    $anchorLeft1 = @($anchorLayout.Items | Where-Object { $_.Id -eq 'ALeft1' })[0]
    $anchorLeft2 = @($anchorLayout.Items | Where-Object { $_.Id -eq 'ALeft2' })[0]
    $anchorMain11 = @($anchorLayout.Items | Where-Object { $_.Id -eq 'AMain11' })[0]
    $anchorMain2 = @($anchorLayout.Items | Where-Object { $_.Id -eq 'AMain2' })[0]
    Assert-True ([Math]::Abs($anchorTopLeft.Width - $anchorLeft1.Width) -le 0.01) 'Primary-top width anchors a near-equal left stack width'
    Assert-True ([Math]::Abs($anchorLeft1.Height - $anchorMain11.Height) -le 0.01) 'Primary-left row height anchors a near-equal first inner row'
    Assert-True ([Math]::Abs($anchorLeft2.Height - $anchorMain2.Height) -le 0.01) 'Primary-left row height anchors a near-equal second inner row'
    Assert-True ($anchorLayout.VerticalAnchorSnapCount -eq 2) 'Two vertical row-height anchor snaps are reported'

    $project = Resolve-PbiProject -Path (Join-Path $projectRoot 'Demo.pbip')
    $resolvedActual = (Get-Item -LiteralPath $project.ReportFolder).FullName
    $resolvedExpected = (Get-Item -LiteralPath $reportFolder).FullName
    Assert-True ($resolvedActual -ieq $resolvedExpected) 'PBIP project resolves its enhanced .Report folder'
    Assert-True ($project.ReportName -eq 'Demo') 'PBIP artifact path selects the intended report when another .Report folder exists'
    $rootResolved = Resolve-PbiProject -Path $projectRoot
    Assert-True ((Get-Item -LiteralPath $rootResolved.ReportFolder).FullName -ieq $resolvedExpected) 'Project-root selection uses the single PBIP artifact path'

    $pages = @(Get-PbiPages -ReportFolder $project.ReportFolder)
    Assert-True ($pages.Count -eq 2) 'Two pages are discovered'
    Assert-True ($pages[0].DisplayName -eq 'Executive Summary' -and $pages[1].DisplayName -eq 'Other Page') 'pages.json order is respected using page.json names'
    Assert-True ($pages[0].Id -eq 'Friendly.Page' -and $pages[0].Name -eq 'Page1') 'Friendly .Page folder can differ from page.json name'
    $directReport = Resolve-PbiProject -Path $reportFolder
    Assert-True ((Get-Item -LiteralPath $directReport.ReportFolder).FullName -ieq $resolvedExpected) 'Direct .Report folder selection resolves correctly'

    $snapshot = Get-PbiPageSnapshot -Page $pages[0]
    Assert-True ($snapshot.Visuals.Count -eq 8) 'Eight visuals, including protected background/header/group/hidden items, are read'
    $readGroup = @($snapshot.Visuals | Where-Object { $_.Id -eq 'GroupContainer.Visual' })[0]
    $readChild = @($snapshot.Visuals | Where-Object { $_.Id -eq 'GroupChild.Visual' })[0]
    $readHidden = @($snapshot.Visuals | Where-Object { $_.Id -eq 'Hidden.Visual' })[0]
    Assert-True ($readGroup.IsVisualGroup -and $readGroup.VisualType -eq 'visualGroup') 'visualGroup container is detected'
    Assert-True ($readGroup.ObjectName -eq 'Group1' -and $readGroup.GroupMode -eq 'ScaleMode') 'visualGroup name and group mode are read'
    Assert-True ($readChild.ParentGroupName -eq 'Group1') 'parentGroupName is read for grouped child'
    Assert-True $readGroup.EffectiveHidden 'Hidden visualGroup is effectively hidden'
    Assert-True ($readChild.EffectiveHidden -and $readChild.HiddenReason -like 'AncestorGroup:*') 'Child of hidden visualGroup inherits hidden state'
    Assert-True $readHidden.IsHidden 'Root-level isHidden state is read'
    $activeSnapshotVisuals = @(Get-PbiActivePageVisuals -PageSnapshot $snapshot)
    Assert-True ($activeSnapshotVisuals.Count -eq 5) 'Active visual helper excludes hidden visuals, hidden-group children, and group containers'
    Assert-True ($snapshot.Width -eq 400 -and $snapshot.Height -eq 300) 'Page canvas size is read'

    $analysis = Get-PbiLayoutAnalysis -PageSnapshot $snapshot
    Assert-True ($analysis.LockedVisualCount -eq 2) 'Only visible structural background/header visuals remain protected'
    Assert-True ($analysis.HiddenVisualCount -eq 3) 'Hidden visual, hidden group, and inherited-hidden child are ignored'
    Assert-True ($analysis.GroupContainerCount -eq 1) 'Group container count is reported separately'
    Assert-True ($analysis.ManagedVisualCount -eq 3) 'Only active content visuals participate in row/column detection'
    Assert-True ($analysis.ReservedTop -eq 40) 'Top structural header reserves its occupied region'
    Assert-True ($analysis.ColumnCount -eq 2) 'Rough X positions collapse into two columns'
    Assert-True ($analysis.RowCount -eq 2) 'Rough Y positions collapse into two rows'

    $wide = @($analysis.Items | Where-Object { $_.Id -eq 'VisualC.Visual' })[0]
    Assert-True ($wide.ColumnSpan -eq 2) 'Wide visual is detected as a two-column span'

    $layout = Get-SmartPbiLayout -Analysis $analysis -Margin 5 -Gap 5
    Assert-True ($layout.ChangedCount -eq 3) 'Only the three rough content visuals receive geometry corrections'
    $lockedBackground = @($layout.Items | Where-Object { $_.Id -eq 'Background.Visual' })[0]
    Assert-True ($lockedBackground.IsLocked -and -not $lockedBackground.Changed) 'Protected background remains unchanged in the proposal'
    Assert-True ($lockedBackground.X -eq 0 -and $lockedBackground.Y -eq 0 -and $lockedBackground.Width -eq 400 -and $lockedBackground.Height -eq 300) 'Protected background geometry is preserved exactly'
    $lockedHeader = @($layout.Items | Where-Object { $_.Id -eq 'Header.Visual' })[0]
    Assert-True ($lockedHeader.IsLocked -and -not $lockedHeader.Changed) 'Wide structural textbox header remains unchanged in the proposal'
    Assert-True ($lockedHeader.Width -eq 400 -and $lockedHeader.Height -eq 40) 'Structural header geometry is preserved exactly'
    Assert-True (@($layout.Items | Where-Object { $_.IsVisualGroup }).Count -eq 0) 'Group containers are excluded from alignment proposal'
    Assert-True (@($layout.Items | Where-Object { $_.EffectiveHidden }).Count -eq 0) 'Hidden visuals are excluded from alignment proposal'
    Assert-True ($layout.Columns -eq 2 -and $layout.Rows -eq 2) 'Layout keeps the detected two-by-two structure'
    Assert-True ($layout.ContentTop -eq 45) 'Smart Align starts content after header plus configured 5-unit gap'
    Assert-True (@($layout.Items | Where-Object { -not $_.IsLocked -and $_.Y -lt 45 }).Count -eq 0) 'No managed visual is placed inside the reserved header region'

    $currentWithBackground = [pscustomobject]@{ PageWidth=$snapshot.Width; PageHeight=$snapshot.Height; Items=$snapshot.Visuals }
    $currentValidation = Test-PbiLayout -Layout $currentWithBackground
    Assert-True $currentValidation.IsValid 'Current-page validation permits intentional canvas-background overlap'

    $validation = Test-PbiLayout -Layout $layout
    Assert-True $validation.IsValid 'Proposed layout is in-bounds and has no unintended overlaps'

    $staleOriginal = [System.IO.File]::ReadAllText($a)
    [System.IO.File]::WriteAllText($a,($staleOriginal + [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($false)))
    $staleValidation = Test-PbiLayout -Layout $layout
    Assert-True (-not $staleValidation.IsValid) 'Stale source hash blocks Apply after PBIR changes'
    [System.IO.File]::WriteAllText($a,$staleOriginal,(New-Object System.Text.UTF8Encoding($false)))
    $validation = Test-PbiLayout -Layout $layout
    Assert-True $validation.IsValid 'Layout becomes valid again after source file is restored'

    $changedItems = @($layout.Items | Where-Object { $_.Changed })

    $readOnlyItem = Get-Item -LiteralPath $a
    $readOnlyItem.IsReadOnly = $true
    try {
        Assert-Throws { Test-PbiWriteTargets -Items $changedItems | Out-Null } 'Read-only target is rejected during write preflight'
    }
    finally {
        (Get-Item -LiteralPath $a).IsReadOnly = $false
    }

    $lockStream = [System.IO.File]::Open(
        $a,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::None
    )
    try {
        Assert-Throws { Test-PbiWriteTargets -Items $changedItems | Out-Null } 'Locked target is rejected during write preflight'
    }
    finally {
        $lockStream.Dispose()
    }

    Assert-True (Test-PbiWriteTargets -Items $changedItems) 'Writable unlocked targets pass write preflight'

    $failureBackup = New-PbiBackup -ProjectRoot $project.ProjectRoot -Items $layout.Items -PageName $pages[0].DisplayName
    $failureOriginal = [System.IO.File]::ReadAllText($a)
    [System.IO.File]::WriteAllText($a,($failureOriginal + [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($false)))
    Assert-Throws { Set-PbiLayoutFiles -Layout $layout -BackupOperation $failureBackup | Out-Null } 'Writer rejects a source file changed after backup'
    Assert-True ((Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash -eq $originalHash[$a]) 'Failed write is automatically rolled back to backup bytes'
    $failedManifest = Get-Content -LiteralPath $failureBackup.ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$failedManifest.Status -eq 'RolledBack') 'Failed write manifest is marked RolledBack'

    $backup = New-PbiBackup -ProjectRoot $project.ProjectRoot -Items $layout.Items -PageName $pages[0].DisplayName
    Assert-True (Test-Path -LiteralPath $backup.ManifestPath -PathType Leaf) 'Backup manifest is created before write'
    Assert-True (@($backup.Manifest.Entries).Count -eq 3) 'Only changed content visual files are backed up'
    Assert-True (-not (@($backup.Manifest.Entries | Where-Object { $_.TargetPath -eq $background }).Count -gt 0)) 'Protected background is not included in write backup'
    Assert-True (-not (@($backup.Manifest.Entries | Where-Object { $_.TargetPath -eq $header }).Count -gt 0)) 'Protected structural header is not included in write backup'
    Assert-True (-not (@($backup.Manifest.Entries | Where-Object { $_.TargetPath -eq $groupContainer }).Count -gt 0)) 'visualGroup container is not included in write backup'
    Assert-True (-not (@($backup.Manifest.Entries | Where-Object { $_.TargetPath -eq $groupChild }).Count -gt 0)) 'Grouped child is not included in write backup'
    Assert-True (-not (@($backup.Manifest.Entries | Where-Object { $_.TargetPath -eq $hiddenVisual }).Count -gt 0)) 'Hidden visual is not included in write backup'

    $write = Set-PbiLayoutFiles -Layout $layout -BackupOperation $backup
    Assert-True ($write.Success -and $write.ChangedCount -eq 3) 'Geometry writes complete successfully'

    $appliedManifest = Get-Content -LiteralPath $backup.ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$appliedManifest.Status -eq 'Applied') 'Backup manifest records Applied status'
    Assert-True (@($appliedManifest.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.AppliedHash) }).Count -eq 3) 'Backup manifest records post-apply hashes'

    $postSnapshot = Get-PbiPageSnapshot -Page $pages[0]
    $postAJson = Get-Content -LiteralPath $a -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($postAJson.visual.visualType -eq 'card') 'Non-geometry visual type/formatting payload remains after write'
    Assert-True ($postAJson.filterConfig.filters.Count -eq 0) 'Non-geometry filter payload remains after write'
    foreach ($expected in @($layout.Items)) {
        $actual = @($postSnapshot.Visuals | Where-Object { $_.Id -eq $expected.Id })[0]
        Assert-True ([Math]::Abs($actual.X - $expected.X) -le 0.001) ($expected.Id + ' x is verified after write')
        Assert-True ([Math]::Abs($actual.Y - $expected.Y) -le 0.001) ($expected.Id + ' y is verified after write')
        Assert-True ([Math]::Abs($actual.Width - $expected.Width) -le 0.001) ($expected.Id + ' width is verified after write')
        Assert-True ([Math]::Abs($actual.Height - $expected.Height) -le 0.001) ($expected.Id + ' height is verified after write')
    }

    $appliedA = [System.IO.File]::ReadAllText($a)
    [System.IO.File]::WriteAllText($a,($appliedA + [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($false)))
    Assert-Throws { Undo-LatestPbiApply -ProjectRoot $project.ProjectRoot | Out-Null } 'Undo blocks newer edits made after Apply'
    [System.IO.File]::WriteAllText($a,$appliedA,(New-Object System.Text.UTF8Encoding($false)))

    $undo = Undo-LatestPbiApply -ProjectRoot $project.ProjectRoot
    Assert-True ($undo.Success -and $undo.RestoredCount -eq 3) 'Undo restores the most recent operation'

    $undoneManifest = Get-Content -LiteralPath $backup.ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$undoneManifest.Status -eq 'Undone') 'Undo marks the latest operation as Undone'
    Assert-Throws { Undo-LatestPbiApply -ProjectRoot $project.ProjectRoot | Out-Null } 'A completed Undo cannot be repeated accidentally'

    foreach ($path in @($background,$a,$b,$c)) {
        $restored = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Assert-True ($restored -eq $originalHash[$path]) ((Split-Path -Leaf (Split-Path -Parent $path)) + ' is byte-for-byte restored')
    }

    $tempFiles = @(Get-ChildItem -LiteralPath $projectRoot -Filter '*.pbiautomate.tmp' -File -Recurse -ErrorAction SilentlyContinue)
    Assert-True ($tempFiles.Count -eq 0) 'No temporary write files remain in the PBIP project'

    Write-Host ''
    Write-Host ('SUCCESS - ' + $script:Passed + ' assertions passed.') -ForegroundColor Green
    $script:TestSucceeded = $true
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('FAILED - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host ('Fixture retained for inspection: ' + $fixtureRoot) -ForegroundColor Yellow
    exit 1
}
finally {
    if (-not $KeepFixture -and $script:TestSucceeded) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
