[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempRoot = Join-Path $env:TEMP ('PBI-Automate-Analyse-Test-' + [Guid]::NewGuid().ToString('N'))
$passed = 0

function Assert-Analyse {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ('ASSERT FAILED: ' + $Message) }
    $script:passed++
    Write-Host ('PASS  ' + $Message) -ForegroundColor Green
}

function Find-TestControl {
    param($Parent,[string]$Name)
    foreach ($control in $Parent.Controls) {
        if ([string]$control.Name -eq $Name) { return $control }
        if ($control.Controls.Count -gt 0) {
            $found = Find-TestControl -Parent $control -Name $Name
            if ($null -ne $found) { return $found }
        }
    }
    return $null
}

$modulePaths = @(
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
    'src\Services\Alignment\Core\OverlapResolver.psm1',
    'src\Services\Alignment\AlignmentService.psm1',
    'src\Services\Analyse\Core\SemanticModelDiscovery.psm1',
    'src\Services\Analyse\Core\TmdlReader.psm1',
    'src\Services\Analyse\Core\SourceInspector.psm1',
    'src\Services\Analyse\Core\MarkdownWriter.psm1',
    'src\Services\Analyse\AnalyseService.psm1',
    'src\UI\PreviewCanvas.psm1',
    'src\UI\MainForm.psm1',
    'src\Services\Analyse\AnalyseView.psm1'
)

try {
    foreach ($relative in $modulePaths) {
        $path = Join-Path $root $relative
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
        Assert-Analyse (@($parseErrors).Count -eq 0) ($relative + ' parses under Windows PowerShell 5.1')
        Import-Module $path -Force -ErrorAction Stop
    }

    $startupPath = Join-Path $root 'Start-PBIAutomate.ps1'
    $startupText = Get-Content -LiteralPath $startupPath -Raw -Encoding UTF8
    Assert-Analyse ($startupText -notmatch 'Show-PBIAutomateMainForm\s+-RootPath\s+\$root\s+-BuildOnly') 'Desktop startup does not return MainForm before its event-handler scope completes'
    Assert-Analyse ($startupText -match 'Show-PBIAutomateMainForm\s+-RootPath\s+\$root') 'Desktop startup keeps the normal modal MainForm lifecycle'
    Assert-Analyse ($startupText -match 'Add-PbiAnalyseUi') 'Analyse UI is attached without replacing the MainForm lifecycle'

    $pbip = Join-Path $root 'PBI Demo\Demo 1.pbip'
    Assert-Analyse (Test-Path -LiteralPath $pbip -PathType Leaf) 'Checked-in PBIP Analyse fixture exists'

    $project = Resolve-PbiProject -Path $pbip
    $semantic = Resolve-PbiSemanticModel -ProjectRoot $project.ProjectRoot -ReportFolder $project.ReportFolder
    Assert-Analyse ($semantic.SemanticModelFolder -like '*.SemanticModel') 'Semantic model resolves from report datasetReference.byPath'
    Assert-Analyse ($semantic.DetectionMethod -eq 'definition.pbir datasetReference.byPath') 'Semantic model records PBIR path detection method'

    $financialPath = Join-Path $semantic.TablesFolder 'financials.tmdl'
    $financial = Get-PbiTmdlTable -Path $financialPath
    Assert-Analyse ($financial.Name -eq 'financials') 'TMDL table name is parsed'
    Assert-Analyse ($financial.Columns.Count -ge 10) 'Physical columns are parsed from TMDL'
    Assert-Analyse ($financial.Partitions.Count -eq 1) 'Table partition is parsed'
    Assert-Analyse (@($financial.Partitions[0].SourceCalls) -contains 'Excel.Workbook') 'Power Query connector call is detected'
    Assert-Analyse (@($financial.Partitions[0].PowerQuerySteps).Count -ge 2) 'Power Query steps are inventoried'

    $datePath = Get-ChildItem -LiteralPath $semantic.TablesFolder -Filter 'DateTableTemplate_*.tmdl' -File | Select-Object -First 1
    $dateTable = Get-PbiTmdlTable -Path $datePath.FullName
    Assert-Analyse (@($dateTable.Columns | Where-Object { $_.IsCalculated }).Count -ge 1) 'Calculated column DAX is detected'
    Assert-Analyse (@($dateTable.Partitions | Where-Object { $_.Type -eq 'calculated' }).Count -eq 1) 'Calculated table partition DAX is detected'

    $relationships = @(Get-PbiTmdlRelationships -Path $semantic.RelationshipsFile)
    Assert-Analyse ($relationships.Count -eq 1) 'Relationship TMDL is parsed'
    Assert-Analyse ($relationships[0].FromTable -eq 'financials') 'Relationship from table is parsed'
    Assert-Analyse (-not [string]::IsNullOrWhiteSpace($relationships[0].ToTable)) 'Relationship to table is parsed'

    $redacted = Protect-AnalyseText 'Server=x;Password=Secret123;AccessToken=abc123;Database=y'
    Assert-Analyse ($redacted -notmatch 'Secret123|abc123') 'Credential-like values are redacted from generated documentation'

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $export = Invoke-PbiAnalyseExport -ProjectPath $pbip -OutputRoot $tempRoot
    Assert-Analyse (Test-Path -LiteralPath $export.OutputFolder -PathType Container) 'Analyse output folder is created'
    Assert-Analyse (Test-Path -LiteralPath (Join-Path $export.OutputFolder 'Table\financials.md') -PathType Leaf) 'Per-table Markdown is generated'
    Assert-Analyse (Test-Path -LiteralPath (Join-Path $export.OutputFolder 'Relationship\Relationships.md') -PathType Leaf) 'Relationship Markdown is generated'
    Assert-Analyse (Test-Path -LiteralPath (Join-Path $export.OutputFolder 'Pages\README.md') -PathType Leaf) 'Pages Markdown is generated'

    $financialMd = Get-Content -LiteralPath (Join-Path $export.OutputFolder 'Table\financials.md') -Raw -Encoding UTF8
    Assert-Analyse ($financialMd -match '<details>') 'Table Markdown uses collapsed details blocks'
    Assert-Analyse ($financialMd -match 'Power Query \(M\)') 'Table Markdown contains Power Query section'
    Assert-Analyse ($financialMd -match 'Excel\.Workbook') 'Table Markdown exposes detected source connector'

    $relationshipMd = Get-Content -LiteralPath (Join-Path $export.OutputFolder 'Relationship\Relationships.md') -Raw -Encoding UTF8
    Assert-Analyse ($relationshipMd -match '```mermaid') 'Relationship Markdown contains a Mermaid flowchart'

    # BuildOnly is valid for non-interactive UI structure tests. Production startup
    # must never show this returned form outside Show-PBIAutomateMainForm's scope.
    $form = Show-PBIAutomateMainForm -RootPath $root -BuildOnly
    Add-PbiAnalyseUi -Form $form -RootPath $root | Out-Null
    Assert-Analyse ($null -ne (Find-TestControl -Parent $form -Name 'Service_analyse')) 'Analyse appears in service navigation'
    Assert-Analyse ($null -ne (Find-TestControl -Parent $form -Name 'AnalyseOutputRoot')) 'Analyse output folder control exists'
    Assert-Analyse ($null -ne (Find-TestControl -Parent $form -Name 'AnalyseGenerateButton')) 'Analyse Generate Markdown button exists'
    Assert-Analyse ($null -ne (Find-TestControl -Parent $form -Name 'AnalyseContent')) 'Analyse main workspace exists'
    $form.Dispose()

    Write-Host ''
    Write-Host ('SUCCESS - ' + $passed + ' Analyse assertions passed.') -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('FAILED - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    exit 1
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
