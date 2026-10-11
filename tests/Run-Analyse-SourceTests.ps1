[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempRoot = Join-Path $env:TEMP ('PBI-Automate-Source-Test-' + [Guid]::NewGuid().ToString('N'))
$passed = 0

function Assert-Source {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ('ASSERT FAILED: ' + $Message) }
    $script:passed++
    Write-Host ('PASS  ' + $Message) -ForegroundColor Green
}

try {
    $readerPath = Join-Path $root 'src\Services\Analyse\Core\TmdlReader.psm1'
    $sourcePath = Join-Path $root 'src\Services\Analyse\Core\SourceInspector.psm1'

    foreach ($path in @($readerPath,$sourcePath)) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        Assert-Source (@($errors).Count -eq 0) ((Split-Path -Leaf $path) + ' parses under Windows PowerShell 5.1')
        Import-Module $path -Force -ErrorAction Stop
    }

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $tablePath = Join-Path $tempRoot 'Sales.tmdl'
    $tmdl = @'
table Sales
	measure 'Total Sales' = SUM(Sales[Amount])
		formatString: #,0

	column Amount
		dataType: double
		sourceColumn: Amount

	partition Sales = m
		mode: import
		source =
			let
				Source = Sql.Database("sql-prod-01", "Finance", [Query="SELECT Amount FROM dbo.Sales"]),
				Filtered = Table.SelectRows(Source, each [Amount] > 0)
			in
				Filtered
'@
    [System.IO.File]::WriteAllText($tablePath,$tmdl,(New-Object System.Text.UTF8Encoding($false)))

    $table = Get-PbiTmdlTable -Path $tablePath
    Assert-Source ($table.Name -eq 'Sales') 'Synthetic table name is parsed'
    Assert-Source ($table.Measures.Count -eq 1) 'Measure definition is parsed'
    Assert-Source ($table.Measures[0].Name -eq 'Total Sales') 'Measure name is parsed'
    Assert-Source ([string]$table.Measures[0].Expression -match 'SUM\(Sales\[Amount\]\)') 'Measure DAX expression is parsed'
    Assert-Source ($table.Partitions.Count -eq 1) 'Import partition is parsed'
    Assert-Source $table.Partitions[0].NativeSqlDetected 'Native SQL is detected from Sql.Database Query option'
    Assert-Source (@($table.Partitions[0].NativeSqlQueries).Count -eq 1) 'Native SQL text is extracted'
    Assert-Source ([string]$table.Partitions[0].NativeSqlQueries[0] -match 'SELECT Amount FROM dbo\.Sales') 'Extracted native SQL contains expected statement'

    $targets = @(Get-PbiPowerQueryConnectionTargets -Text ([string]$table.Partitions[0].Source))
    Assert-Source ($targets.Count -ge 1) 'Connection target is detected'
    Assert-Source (@($targets | Where-Object { $_.Connector -eq 'Sql.Database' -and $_.Target -eq 'sql-prod-01 / Finance' }).Count -eq 1) 'SQL server and database are extracted'

    $sampleSource = 'Excel.Workbook(File.Contents("C:\Data\Financial Sample.xlsx"), null, true)'
    $fileTargets = @(Get-PbiPowerQueryConnectionTargets -Text $sampleSource)
    Assert-Source (@($fileTargets | Where-Object { $_.Connector -eq 'File.Contents' -and $_.Target -match 'Financial Sample\.xlsx' }).Count -eq 1) 'Nested file connection path is extracted'

    $secretSource = 'Odbc.DataSource("dsn=Prod;Password=SuperSecret;ApiKey=abc123")'
    $secretTargets = @(Get-PbiPowerQueryConnectionTargets -Text $secretSource)
    $joinedTargets = @($secretTargets | ForEach-Object { $_.Target }) -join ' '
    Assert-Source ($joinedTargets -notmatch 'SuperSecret|abc123') 'Credential values are redacted from connection targets'

    Write-Host ''
    Write-Host ('SUCCESS - ' + $passed + ' source assertions passed.') -ForegroundColor Green
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
