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
    'src\Core\LayoutAnalyzer.psm1',
    'src\Core\SmartLayoutEngine.psm1',
    'src\Core\LayoutValidator.psm1',
    'src\Core\BackupService.psm1',
    'src\Core\PBIRWriter.psm1',
    'src\Core\UndoService.psm1',
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
    'src\Core\LayoutAnalyzer.psm1',
    'src\Core\SmartLayoutEngine.psm1',
    'src\Core\LayoutValidator.psm1',
    'src\Core\BackupService.psm1',
    'src\Core\PBIRWriter.psm1',
    'src\Core\UndoService.psm1',
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
    Write-Utf8NoBom -Path (Join-Path $projectRoot 'Demo.pbip') -Content '{}'
    Write-Utf8NoBom -Path (Join-Path $reportFolder 'definition.pbir') -Content '{}'
    Write-Utf8NoBom -Path (Join-Path $reportFolder 'definition\pages\pages.json') -Content '{"pageOrder":["Page1","Page2"],"activePageName":"Page1"}'
    Write-Utf8NoBom -Path (Join-Path $pageFolder 'page.json') -Content '{"name":"Page1","displayName":"Executive Summary","displayOption":"FitToPage","width":400,"height":300}'
    Write-Utf8NoBom -Path (Join-Path $page2Folder 'page.json') -Content '{"name":"Page2","displayName":"Other Page","displayOption":"FitToPage","width":400,"height":300}'

    $a = New-TestVisual -PageFolder $pageFolder -Id 'VisualA.Visual' -X 7.25 -Y 8.5 -Width 184.75 -Height 130.25 -Type 'card'
    $b = New-TestVisual -PageFolder $pageFolder -Id 'VisualB.Visual' -X 204.4 -Y 11.2 -Width 188.1 -Height 127.6 -Type 'card'
    $c = New-TestVisual -PageFolder $pageFolder -Id 'VisualC.Visual' -X 9.1 -Y 151.35 -Width 383.2 -Height 140.4 -Type 'barChart'

    $originalHash = @{}
    foreach ($path in @($a,$b,$c)) {
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

    $project = Resolve-PbiProject -Path (Join-Path $projectRoot 'Demo.pbip')
    $resolvedActual = (Get-Item -LiteralPath $project.ReportFolder).FullName
    $resolvedExpected = (Get-Item -LiteralPath $reportFolder).FullName
    Assert-True ($resolvedActual -ieq $resolvedExpected) 'PBIP project resolves its enhanced .Report folder'

    $pages = @(Get-PbiPages -ReportFolder $project.ReportFolder)
    Assert-True ($pages.Count -eq 2) 'Two pages are discovered'
    Assert-True ($pages[0].DisplayName -eq 'Executive Summary' -and $pages[1].DisplayName -eq 'Other Page') 'pages.json order is respected using page.json names'
    Assert-True ($pages[0].Id -eq 'Friendly.Page' -and $pages[0].Name -eq 'Page1') 'Friendly .Page folder can differ from page.json name'
    $directReport = Resolve-PbiProject -Path $reportFolder
    Assert-True ((Get-Item -LiteralPath $directReport.ReportFolder).FullName -ieq $resolvedExpected) 'Direct .Report folder selection resolves correctly'

    $snapshot = Get-PbiPageSnapshot -Page $pages[0]
    Assert-True ($snapshot.Visuals.Count -eq 3) 'Three supported visuals are read'
    Assert-True ($snapshot.Width -eq 400 -and $snapshot.Height -eq 300) 'Page canvas size is read'

    $analysis = Get-PbiLayoutAnalysis -PageSnapshot $snapshot
    Assert-True ($analysis.ColumnCount -eq 2) 'Rough X positions collapse into two columns'
    Assert-True ($analysis.RowCount -eq 2) 'Rough Y positions collapse into two rows'

    $wide = @($analysis.Items | Where-Object { $_.Id -eq 'VisualC.Visual' })[0]
    Assert-True ($wide.ColumnSpan -eq 2) 'Wide visual is detected as a two-column span'

    $layout = Get-SmartPbiLayout -Analysis $analysis -Margin 5 -Gap 5
    Assert-True ($layout.ChangedCount -eq 3) 'All rough fixture visuals receive deterministic geometry corrections'
    Assert-True ($layout.Columns -eq 2 -and $layout.Rows -eq 2) 'Layout keeps the detected two-by-two structure'

    $validation = Test-PbiLayout -Layout $layout
    Assert-True $validation.IsValid 'Proposed layout is in-bounds and has no overlaps'

    $staleOriginal = [System.IO.File]::ReadAllText($a)
    [System.IO.File]::WriteAllText($a,($staleOriginal + [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($false)))
    $staleValidation = Test-PbiLayout -Layout $layout
    Assert-True (-not $staleValidation.IsValid) 'Stale source hash blocks Apply after PBIR changes'
    [System.IO.File]::WriteAllText($a,$staleOriginal,(New-Object System.Text.UTF8Encoding($false)))
    $validation = Test-PbiLayout -Layout $layout
    Assert-True $validation.IsValid 'Layout becomes valid again after source file is restored'

    $backup = New-PbiBackup -ProjectRoot $project.ProjectRoot -Items $layout.Items -PageName $pages[0].DisplayName
    Assert-True (Test-Path -LiteralPath $backup.ManifestPath -PathType Leaf) 'Backup manifest is created before write'
    Assert-True (@($backup.Manifest.Entries).Count -eq 3) 'All changed visual files are backed up'

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

    foreach ($path in @($a,$b,$c)) {
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
