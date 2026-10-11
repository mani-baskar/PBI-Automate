Set-StrictMode -Version 2.0

function Get-PbiAnalyseProjectInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath)

    $project = Resolve-PbiProject -Path $ProjectPath
    $semantic = Resolve-PbiSemanticModel -ProjectRoot $project.ProjectRoot -ReportFolder $project.ReportFolder
    $tableFiles = @(Get-ChildItem -LiteralPath $semantic.TablesFolder -File -Filter '*.tmdl' -ErrorAction Stop | Sort-Object Name)
    $relationships = @(Get-PbiTmdlRelationships -Path $semantic.RelationshipsFile)
    $pages = @(Get-PbiPages -ReportFolder $project.ReportFolder)

    [pscustomobject]@{
        Project = $project
        SemanticModel = $semantic
        TableFileCount = $tableFiles.Count
        RelationshipCount = $relationships.Count
        PageCount = $pages.Count
    }
}

function Get-PbiAnalysePageSummaries {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ReportFolder)

    $result = @()
    foreach ($page in @(Get-PbiPages -ReportFolder $ReportFolder)) {
        try {
            $snapshot = Get-PbiPageSnapshot -Page $page
            $active = @(Get-PbiActivePageVisuals -PageSnapshot $snapshot)
            $hidden = @($snapshot.Visuals | Where-Object {
                if ($_.PSObject.Properties.Name -contains 'EffectiveHidden') { [bool]$_.EffectiveHidden } else { [bool]$_.IsHidden }
            })
            $groups = @($snapshot.Visuals | Where-Object { $_.PSObject.Properties.Name -contains 'IsVisualGroup' -and [bool]$_.IsVisualGroup })

            $result += [pscustomobject]@{
                DisplayName = $page.DisplayName
                Name = $page.Name
                Width = [double]$page.Width
                Height = [double]$page.Height
                TotalVisuals = @($snapshot.Visuals).Count
                ActiveVisuals = $active.Count
                HiddenVisuals = $hidden.Count
                GroupContainers = $groups.Count
            }
        }
        catch {
            $result += [pscustomobject]@{
                DisplayName = $page.DisplayName
                Name = $page.Name
                Width = [double]$page.Width
                Height = [double]$page.Height
                TotalVisuals = 0
                ActiveVisuals = 0
                HiddenVisuals = 0
                GroupContainers = 0
            }
        }
    }
    return @($result)
}

function Add-PbiConnectionTargetsToMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Markdown,
        [Parameter(Mandatory=$true)]$Table
    )

    if ($null -eq (Get-Command -Name Get-PbiPowerQueryConnectionTargets -ErrorAction SilentlyContinue)) {
        return $Markdown
    }

    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($partition in @($Table.Partitions)) {
        foreach ($target in @(Get-PbiPowerQueryConnectionTargets -Text ([string]$partition.Source))) {
            $connector = ([string]$target.Connector).Replace('|','\|')
            $targetText = ([string]$target.Target).Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
            [void]$rows.Add('| ' + $partition.Name + ' | ' + $connector + ' | ' + $targetText + ' |')
        }
    }

    if ($rows.Count -eq 0) { return $Markdown }

    $section = New-Object System.Text.StringBuilder
    [void]$section.AppendLine('## Connection Targets')
    [void]$section.AppendLine('')
    [void]$section.AppendLine('| Partition | Connector | Target |')
    [void]$section.AppendLine('|---|---|---|')
    foreach ($row in $rows) { [void]$section.AppendLine($row) }
    [void]$section.AppendLine('')

    $marker = '## Data Source & Power Query'
    if ($Markdown.Contains($marker)) {
        return $Markdown.Replace($marker,($section.ToString() + $marker))
    }
    return ($Markdown + [Environment]::NewLine + $section.ToString())
}

function Invoke-PbiAnalyseExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectPath,
        [Parameter(Mandatory=$true)][string]$OutputRoot
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) { throw 'Choose an output folder before generating Analyse documentation.' }
    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) { throw ('Output folder does not exist: ' + $OutputRoot) }

    $project = Resolve-PbiProject -Path $ProjectPath
    $semantic = Resolve-PbiSemanticModel -ProjectRoot $project.ProjectRoot -ReportFolder $project.ReportFolder
    $analyseRoot = Join-Path (Get-Item -LiteralPath $OutputRoot).FullName 'Analyse'
    $tableOutput = Join-Path $analyseRoot 'Table'
    $relationshipOutput = Join-Path $analyseRoot 'Relationship'
    $pagesOutput = Join-Path $analyseRoot 'Pages'

    foreach ($folder in @($analyseRoot,$tableOutput,$relationshipOutput,$pagesOutput)) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    }

    $sharedExpressions = @(Get-PbiTmdlExpressions -Path $semantic.ExpressionsFile)
    $tableFiles = @(Get-ChildItem -LiteralPath $semantic.TablesFolder -File -Filter '*.tmdl' -ErrorAction Stop | Sort-Object Name)
    $tables = @()
    $errors = @()

    foreach ($tableFile in $tableFiles) {
        try {
            $table = Get-PbiTmdlTable -Path $tableFile.FullName
            $tables += $table
            $safeName = ConvertTo-AnalyseSafeFileName -Name ([string]$table.Name)
            $markdown = New-PbiTableMarkdown -Table $table -SharedExpressions $sharedExpressions
            $markdown = Add-PbiConnectionTargetsToMarkdown -Markdown $markdown -Table $table
            Write-AnalyseUtf8File -Path (Join-Path $tableOutput ($safeName + '.md')) -Content $markdown
        }
        catch {
            $errors += ('Table ' + $tableFile.Name + ': ' + $_.Exception.Message)
        }
    }

    $relationships = @(Get-PbiTmdlRelationships -Path $semantic.RelationshipsFile)
    $relationshipMarkdown = New-PbiRelationshipsMarkdown -Relationships $relationships
    Write-AnalyseUtf8File -Path (Join-Path $relationshipOutput 'Relationships.md') -Content $relationshipMarkdown

    $pages = @(Get-PbiAnalysePageSummaries -ReportFolder $project.ReportFolder)
    $pagesMarkdown = New-PbiPagesMarkdown -Pages $pages
    Write-AnalyseUtf8File -Path (Join-Path $pagesOutput 'README.md') -Content $pagesMarkdown

    $tableIndex = New-PbiTableIndexMarkdown -Tables $tables
    Write-AnalyseUtf8File -Path (Join-Path $tableOutput '_index.md') -Content $tableIndex

    $index = New-PbiAnalyseIndexMarkdown -Project $project -SemanticModel $semantic -Tables $tables -Relationships $relationships -Pages $pages
    Write-AnalyseUtf8File -Path (Join-Path $analyseRoot 'README.md') -Content $index

    $nativeSqlTableCount = @($tables | Where-Object { @($_.Partitions | Where-Object { $_.NativeSqlDetected }).Count -gt 0 }).Count
    $sourceCalls = @()
    foreach ($table in $tables) {
        foreach ($partition in @($table.Partitions)) {
            foreach ($call in @($partition.SourceCalls)) { if ($sourceCalls -notcontains $call) { $sourceCalls += $call } }
        }
    }

    [pscustomobject]@{
        Success = ($errors.Count -eq 0)
        OutputFolder = $analyseRoot
        SemanticModelFolder = $semantic.SemanticModelFolder
        TableCount = $tables.Count
        RelationshipCount = $relationships.Count
        PageCount = $pages.Count
        NativeSqlTableCount = $nativeSqlTableCount
        SourceCalls = @($sourceCalls)
        Errors = @($errors)
    }
}

Export-ModuleMember -Function Get-PbiAnalyseProjectInfo, Get-PbiAnalysePageSummaries, Invoke-PbiAnalyseExport
