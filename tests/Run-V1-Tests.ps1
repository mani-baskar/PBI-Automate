[CmdletBinding()]
param(
    [switch]$KeepFixture
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

$modules = @(
    'src\Core\Logging.psm1',
    'src\Core\ProjectDiscovery.psm1',
    'src\Core\PBIRReader.psm1',
    'src\Core\LayoutAnalyzer.psm1',
    'src\Core\SmartLayoutEngine.psm1',
    'src\Core\LayoutValidator.psm1',
    'src\Core\BackupService.psm1',
    'src\Core\PBIRWriter.psm1',
    'src\Core\UndoService.psm1'
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
$pageFolder = Join-Path $reportFolder 'definition\pages\Page1'

try {
    New-Item -ItemType Directory -Path $pageFolder -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $projectRoot 'Demo.pbip') -Content '{}'
    Write-Utf8NoBom -Path (Join-Path $reportFolder 'definition.pbir') -Content '{}'
    Write-Utf8NoBom -Path (Join-Path $reportFolder 'definition\pages\pages.json') -Content '{"pageOrder":["Page1"],"activePageName":"Page1"}'
    Write-Utf8NoBom -Path (Join-Path $pageFolder 'page.json') -Content '{"name":"Page1","displayName":"Executive Summary","width":400,"height":300}'

    $a = New-TestVisual -PageFolder $pageFolder -Id 'VisualA' -X 7 -Y 8 -Width 184 -Height 130 -Type 'card'
    $b = New-TestVisual -PageFolder $pageFolder -Id 'VisualB' -X 204 -Y 11 -Width 188 -Height 127 -Type 'card'
    $c = New-TestVisual -PageFolder $pageFolder -Id 'VisualC' -X 9 -Y 151 -Width 383 -Height 140 -Type 'barChart'

    $originalHash = @{}
    foreach ($path in @($a,$b,$c)) {
        $originalHash[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }

    Write-Host ''
    Write-Host 'PBI Automate V1 integration test' -ForegroundColor Cyan
    Write-Host ('Fixture: ' + $fixtureRoot)
    Write-Host ''

    $project = Resolve-PbiProject -Path (Join-Path $projectRoot 'Demo.pbip')
    Assert-True ($project.ReportFolder -eq $reportFolder) 'PBIP project resolves its enhanced .Report folder'

    $pages = @(Get-PbiPages -ReportFolder $project.ReportFolder)
    Assert-True ($pages.Count -eq 1) 'Exactly one page is discovered'
    Assert-True ($pages[0].DisplayName -eq 'Executive Summary') 'Page display name is read'

    $snapshot = Get-PbiPageSnapshot -Page $pages[0]
    Assert-True ($snapshot.Visuals.Count -eq 3) 'Three supported visuals are read'
    Assert-True ($snapshot.Width -eq 400 -and $snapshot.Height -eq 300) 'Page canvas size is read'

    $analysis = Get-PbiLayoutAnalysis -PageSnapshot $snapshot
    Assert-True ($analysis.ColumnCount -eq 2) 'Rough X positions collapse into two columns'
    Assert-True ($analysis.RowCount -eq 2) 'Rough Y positions collapse into two rows'

    $wide = @($analysis.Items | Where-Object { $_.Id -eq 'VisualC' })[0]
    Assert-True ($wide.ColumnSpan -eq 2) 'Wide visual is detected as a two-column span'

    $layout = Get-SmartPbiLayout -Analysis $analysis -Margin 5 -Gap 5
    Assert-True ($layout.ChangedCount -eq 3) 'All rough fixture visuals receive deterministic geometry corrections'
    Assert-True ($layout.Columns -eq 2 -and $layout.Rows -eq 2) 'Layout keeps the detected two-by-two structure'

    $validation = Test-PbiLayout -Layout $layout
    Assert-True $validation.IsValid 'Proposed layout is in-bounds and has no overlaps'

    $backup = New-PbiBackup -ProjectRoot $project.ProjectRoot -Items $layout.Items -PageName $pages[0].DisplayName
    Assert-True (Test-Path -LiteralPath $backup.ManifestPath -PathType Leaf) 'Backup manifest is created before write'
    Assert-True (@($backup.Manifest.Entries).Count -eq 3) 'All changed visual files are backed up'

    $write = Set-PbiLayoutFiles -Layout $layout -BackupOperation $backup
    Assert-True ($write.Success -and $write.ChangedCount -eq 3) 'Geometry writes complete successfully'

    $postSnapshot = Get-PbiPageSnapshot -Page $pages[0]
    foreach ($expected in @($layout.Items)) {
        $actual = @($postSnapshot.Visuals | Where-Object { $_.Id -eq $expected.Id })[0]
        Assert-True ([Math]::Abs($actual.X - $expected.X) -le 0.001) ($expected.Id + ' x is verified after write')
        Assert-True ([Math]::Abs($actual.Y - $expected.Y) -le 0.001) ($expected.Id + ' y is verified after write')
        Assert-True ([Math]::Abs($actual.Width - $expected.Width) -le 0.001) ($expected.Id + ' width is verified after write')
        Assert-True ([Math]::Abs($actual.Height - $expected.Height) -le 0.001) ($expected.Id + ' height is verified after write')
    }

    $undo = Undo-LatestPbiApply -ProjectRoot $project.ProjectRoot
    Assert-True ($undo.Success -and $undo.RestoredCount -eq 3) 'Undo restores the most recent operation'

    foreach ($path in @($a,$b,$c)) {
        $restored = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Assert-True ($restored -eq $originalHash[$path]) ((Split-Path -Leaf (Split-Path -Parent $path)) + ' is byte-for-byte restored')
    }

    $tempFiles = @(Get-ChildItem -LiteralPath $projectRoot -Filter '*.pbiautomate.tmp' -File -Recurse -ErrorAction SilentlyContinue)
    Assert-True ($tempFiles.Count -eq 0) 'No temporary write files remain in the PBIP project'

    Write-Host ''
    Write-Host ('SUCCESS — ' + $script:Passed + ' assertions passed.') -ForegroundColor Green
    $script:TestSucceeded = $true
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('FAILED — ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host ('Fixture retained for inspection: ' + $fixtureRoot) -ForegroundColor Yellow
    exit 1
}
finally {
    if (-not $KeepFixture -and $script:TestSucceeded) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
