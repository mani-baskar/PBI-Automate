Set-StrictMode -Version 2.0

function ConvertFrom-TmdlIdentifier {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '' }
    $valueText = $Value.Trim()
    if ($valueText.Length -ge 2 -and $valueText.StartsWith("'") -and $valueText.EndsWith("'")) {
        return $valueText.Substring(1,$valueText.Length-2).Replace("''","'")
    }
    return $valueText
}

function Get-TmdlIndentLevel {
    param([string]$Line)

    $level = 0.0
    foreach ($char in $Line.ToCharArray()) {
        if ($char -eq "`t") { $level += 1.0; continue }
        if ($char -eq ' ') { $level += 0.25; continue }
        break
    }
    return [int][Math]::Floor($level)
}

function Get-TmdlMemberBlocks {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string[]]$Kinds
    )

    $lines = @($Text -split "`r?`n")
    $blocks = @()
    $current = $null

    foreach ($line in $lines) {
        $indent = Get-TmdlIndentLevel -Line $line
        $trimmed = $line.Trim()
        $kind = $null

        if ($indent -eq 1) {
            foreach ($candidateKind in $Kinds) {
                if ($trimmed -match ('^' + [regex]::Escape($candidateKind) + '\s+')) {
                    $kind = $candidateKind
                    break
                }
            }
        }

        if ($null -ne $kind) {
            if ($null -ne $current) { $blocks += $current }
            $current = [pscustomobject]@{
                Kind = $kind
                Declaration = $trimmed
                Lines = New-Object System.Collections.Generic.List[string]
            }
            [void]$current.Lines.Add($line)
            continue
        }

        if ($null -ne $current) {
            if ($indent -le 1 -and -not [string]::IsNullOrWhiteSpace($trimmed)) {
                $blocks += $current
                $current = $null
            }
            elseif ($null -ne $current) {
                [void]$current.Lines.Add($line)
            }
        }
    }

    if ($null -ne $current) { $blocks += $current }
    return @($blocks)
}

function Get-TmdlDeclaredNameAndExpression {
    param(
        [Parameter(Mandatory=$true)][string]$Declaration,
        [Parameter(Mandatory=$true)][string]$Kind
    )

    $rest = $Declaration.Substring($Kind.Length).Trim()
    $namePart = $rest
    $expression = ''
    $equalsIndex = $rest.IndexOf(' = ')

    if ($equalsIndex -ge 0) {
        $namePart = $rest.Substring(0,$equalsIndex).Trim()
        $expression = $rest.Substring($equalsIndex + 3).Trim()
    }

    [pscustomobject]@{
        Name = ConvertFrom-TmdlIdentifier $namePart
        Expression = $expression
    }
}

function Get-TmdlBlockProperty {
    param(
        [Parameter(Mandatory=$true)]$Block,
        [Parameter(Mandatory=$true)][string]$Name
    )

    foreach ($line in @($Block.Lines)) {
        $trimmed = $line.Trim()
        if ($trimmed -match ('^' + [regex]::Escape($Name) + '\s*:\s*(.*)$')) {
            return [string]$Matches[1].Trim()
        }
    }
    return ''
}

function Get-TmdlLogicExpression {
    param(
        [Parameter(Mandatory=$true)]$Block,
        [Parameter(Mandatory=$true)][string]$Kind
    )

    $decl = Get-TmdlDeclaredNameAndExpression -Declaration $Block.Declaration -Kind $Kind
    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($decl.Expression)) { [void]$parts.Add($decl.Expression) }

    $metadataPattern = '^(dataType|formatString|formatStringDefinition|lineageTag|summarizeBy|sourceColumn|displayFolder|description|dataCategory|sortByColumn|isHidden|isNameInferred|annotation|variation|changedProperty|extendedProperty|detailRowsDefinition)\b'

    for ($i=1; $i -lt $Block.Lines.Count; $i++) {
        $line = [string]$Block.Lines[$i]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            if ($parts.Count -gt 0) { [void]$parts.Add('') }
            continue
        }
        if ($trimmed -match $metadataPattern) { break }
        [void]$parts.Add($trimmed)
    }

    return (($parts -join [Environment]::NewLine).Trim())
}

function Get-TmdlPartitionSource {
    param([Parameter(Mandatory=$true)]$Block)

    $sourceLines = New-Object System.Collections.Generic.List[string]
    $collecting = $false
    $sourceIndent = 0

    foreach ($line in @($Block.Lines)) {
        $trimmed = $line.Trim()
        $indent = Get-TmdlIndentLevel -Line $line

        if (-not $collecting -and $trimmed -match '^source\s*=\s*(.*)$') {
            $collecting = $true
            $sourceIndent = $indent
            $inline = [string]$Matches[1]
            if (-not [string]::IsNullOrWhiteSpace($inline)) { [void]$sourceLines.Add($inline) }
            continue
        }

        if ($collecting) {
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and $indent -le $sourceIndent) { break }
            if ($indent -gt $sourceIndent) {
                $removeTabs = [Math]::Min($sourceIndent + 1,($line.Length - $line.TrimStart("`t",' ').Length))
                [void]$sourceLines.Add($line.TrimStart("`t",' '))
            }
        }
    }

    return (($sourceLines -join [Environment]::NewLine).Trim())
}

function Get-PowerQuerySourceCalls {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $pattern = '(?i)\b(Sql\.Database|Snowflake\.Databases|GoogleBigQuery\.Database|Oracle\.Database|PostgreSQL\.Database|MySQL\.Database|Odbc\.DataSource|Odbc\.Query|OleDb\.DataSource|OleDb\.Query|AnalysisServices\.Database|SharePoint\.Files|SharePoint\.Contents|Web\.Contents|Excel\.Workbook|File\.Contents|Csv\.Document|AzureStorage\.[A-Za-z]+|Databricks\.[A-Za-z.]+)\s*\('
    $matches = [regex]::Matches($Text,$pattern)
    $result = @()
    foreach ($match in $matches) {
        $name = [string]$match.Groups[1].Value
        if ($result -notcontains $name) { $result += $name }
    }
    return @($result)
}

function Get-PowerQuerySteps {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch '(?i)\blet\b') { return @() }
    $result = @()
    foreach ($line in @($Text -split "`r?`n")) {
        $trimmed = $line.Trim().TrimEnd(',')
        if ($trimmed -match '^(#"[^"]+"|[A-Za-z_][A-Za-z0-9_ ]*)\s*=') {
            $step = [string]$Matches[1]
            if ($result -notcontains $step) { $result += $step }
        }
    }
    return @($result)
}

function Get-NativeSqlInfo {
    param([string]$Text)

    $detected = $false
    $queries = @()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [pscustomobject]@{ Detected=$false; Queries=@() }
    }

    if ($Text -match '(?i)Value\.NativeQuery\s*\(' -or
        $Text -match '(?i)Odbc\.Query\s*\(' -or
        $Text -match '(?i)OleDb\.Query\s*\(' -or
        $Text -match '(?i)\[\s*Query\s*=') {
        $detected = $true
    }

    foreach ($pattern in @(
        '(?is)\[\s*Query\s*=\s*"((?:[^"]|"")*)"',
        '(?is)Value\.NativeQuery\s*\([^,]+,\s*"((?:[^"]|"")*)"',
        '(?is)Odbc\.Query\s*\([^,]+,\s*"((?:[^"]|"")*)"',
        '(?is)OleDb\.Query\s*\([^,]+,\s*"((?:[^"]|"")*)"'
    )) {
        foreach ($match in [regex]::Matches($Text,$pattern)) {
            $query = [string]$match.Groups[1].Value
            $query = $query.Replace('""','"').Replace('#(lf)',[Environment]::NewLine).Replace('#(cr)',[Environment]::NewLine).Trim()
            if (-not [string]::IsNullOrWhiteSpace($query) -and $queries -notcontains $query) { $queries += $query }
        }
    }

    [pscustomobject]@{ Detected=$detected; Queries=@($queries) }
}

function Get-PbiTmdlTable {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $firstLine = @($raw -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0].Trim()
    if ($firstLine -notmatch '^table\s+(.+)$') { throw ('TMDL table declaration was not found: ' + $Path) }
    $tableName = ConvertFrom-TmdlIdentifier ([string]$Matches[1])
    $tableHidden = [bool]($raw -match '(?m)^\tisHidden\s*$')

    $blocks = @(Get-TmdlMemberBlocks -Text $raw -Kinds @('column','measure','partition','hierarchy'))
    $columns = @()
    $measures = @()
    $partitions = @()
    $hierarchies = @()

    foreach ($block in $blocks) {
        $decl = Get-TmdlDeclaredNameAndExpression -Declaration $block.Declaration -Kind $block.Kind
        switch ($block.Kind) {
            'column' {
                $expression = Get-TmdlLogicExpression -Block $block -Kind 'column'
                $columns += [pscustomobject]@{
                    Name = $decl.Name
                    DataType = Get-TmdlBlockProperty -Block $block -Name 'dataType'
                    SourceColumn = Get-TmdlBlockProperty -Block $block -Name 'sourceColumn'
                    SummarizeBy = Get-TmdlBlockProperty -Block $block -Name 'summarizeBy'
                    FormatString = Get-TmdlBlockProperty -Block $block -Name 'formatString'
                    IsHidden = [bool]((@($block.Lines) -join "`n") -match '(?m)^\s*isHidden\s*$')
                    IsCalculated = -not [string]::IsNullOrWhiteSpace($expression)
                    Expression = $expression
                }
            }
            'measure' {
                $measures += [pscustomobject]@{
                    Name = $decl.Name
                    Expression = Get-TmdlLogicExpression -Block $block -Kind 'measure'
                    FormatString = Get-TmdlBlockProperty -Block $block -Name 'formatString'
                    DisplayFolder = Get-TmdlBlockProperty -Block $block -Name 'displayFolder'
                }
            }
            'partition' {
                $source = Get-TmdlPartitionSource -Block $block
                $partitionType = ''
                $partitionRest = $block.Declaration.Substring('partition'.Length).Trim()
                $eq = $partitionRest.LastIndexOf(' = ')
                if ($eq -ge 0) { $partitionType = $partitionRest.Substring($eq + 3).Trim() }
                $nativeSql = Get-NativeSqlInfo -Text $source
                $partitions += [pscustomobject]@{
                    Name = $decl.Name
                    Type = $partitionType
                    Mode = Get-TmdlBlockProperty -Block $block -Name 'mode'
                    Source = $source
                    SourceCalls = @(Get-PowerQuerySourceCalls -Text $source)
                    PowerQuerySteps = @(Get-PowerQuerySteps -Text $source)
                    NativeSqlDetected = [bool]$nativeSql.Detected
                    NativeSqlQueries = @($nativeSql.Queries)
                }
            }
            'hierarchy' {
                $hierarchies += [pscustomobject]@{ Name=$decl.Name }
            }
        }
    }

    [pscustomobject]@{
        Name = $tableName
        FilePath = $Path
        IsHidden = $tableHidden
        Columns = @($columns)
        Measures = @($measures)
        Partitions = @($partitions)
        Hierarchies = @($hierarchies)
        RawTmdl = $raw
    }
}

function Split-TmdlColumnReference {
    param([string]$Reference)

    $text = $Reference.Trim()
    $dotIndex = -1
    $insideQuote = $false
    for ($i=0; $i -lt $text.Length; $i++) {
        if ($text[$i] -eq "'") {
            if ($insideQuote -and $i+1 -lt $text.Length -and $text[$i+1] -eq "'") { $i++; continue }
            $insideQuote = -not $insideQuote
            continue
        }
        if ($text[$i] -eq '.' -and -not $insideQuote) { $dotIndex = $i }
    }

    if ($dotIndex -lt 0) { return [pscustomobject]@{ Table=''; Column=(ConvertFrom-TmdlIdentifier $text) } }
    return [pscustomobject]@{
        Table = ConvertFrom-TmdlIdentifier $text.Substring(0,$dotIndex)
        Column = ConvertFrom-TmdlIdentifier $text.Substring($dotIndex+1)
    }
}

function Get-PbiTmdlRelationships {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $lines = @($raw -split "`r?`n")
    $blocks = @()
    $current = $null

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ((Get-TmdlIndentLevel -Line $line) -eq 0 -and $trimmed -match '^relationship\s+(.+)$') {
            if ($null -ne $current) { $blocks += $current }
            $current = [pscustomobject]@{ Name=[string]$Matches[1].Trim(); Lines=New-Object System.Collections.Generic.List[string] }
            [void]$current.Lines.Add($line)
            continue
        }
        if ($null -ne $current) { [void]$current.Lines.Add($line) }
    }
    if ($null -ne $current) { $blocks += $current }

    $relationships = @()
    foreach ($block in $blocks) {
        $props = @{}
        foreach ($line in @($block.Lines)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^([A-Za-z][A-Za-z0-9]+)\s*:\s*(.*)$') { $props[[string]$Matches[1]] = [string]$Matches[2].Trim() }
            elseif ($trimmed -match '^(isActive|relyOnReferentialIntegrity)\s*$') { $props[[string]$Matches[1]] = 'true' }
        }
        $from = Split-TmdlColumnReference ([string]$props['fromColumn'])
        $to = Split-TmdlColumnReference ([string]$props['toColumn'])
        $relationships += [pscustomobject]@{
            Name = $block.Name
            FromTable = $from.Table
            FromColumn = $from.Column
            ToTable = $to.Table
            ToColumn = $to.Column
            FromCardinality = if ($props.ContainsKey('fromCardinality')) { $props['fromCardinality'] } else { 'many (default)' }
            ToCardinality = if ($props.ContainsKey('toCardinality')) { $props['toCardinality'] } else { 'one (default)' }
            CrossFilteringBehavior = if ($props.ContainsKey('crossFilteringBehavior')) { $props['crossFilteringBehavior'] } else { 'oneDirection (default)' }
            IsActive = if ($props.ContainsKey('isActive')) { [string]$props['isActive'] } else { 'true (default)' }
            SecurityFilteringBehavior = if ($props.ContainsKey('securityFilteringBehavior')) { $props['securityFilteringBehavior'] } else { '' }
            JoinOnDateBehavior = if ($props.ContainsKey('joinOnDateBehavior')) { $props['joinOnDateBehavior'] } else { '' }
            Raw = (@($block.Lines) -join [Environment]::NewLine).Trim()
        }
    }
    return @($relationships)
}

function Get-PbiTmdlExpressions {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $lines = @($raw -split "`r?`n")
    $result = @()
    $currentName = $null
    $currentLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ((Get-TmdlIndentLevel -Line $line) -eq 0 -and $trimmed -match '^expression\s+(.+?)\s*=\s*(.*)$') {
            if ($null -ne $currentName) {
                $result += [pscustomobject]@{ Name=$currentName; Expression=($currentLines -join [Environment]::NewLine).Trim() }
            }
            $currentName = ConvertFrom-TmdlIdentifier ([string]$Matches[1])
            $currentLines = New-Object System.Collections.Generic.List[string]
            if (-not [string]::IsNullOrWhiteSpace([string]$Matches[2])) { [void]$currentLines.Add([string]$Matches[2]) }
            continue
        }
        if ($null -ne $currentName) { [void]$currentLines.Add($line.TrimStart("`t",' ')) }
    }
    if ($null -ne $currentName) { $result += [pscustomobject]@{ Name=$currentName; Expression=($currentLines -join [Environment]::NewLine).Trim() } }
    return @($result)
}

Export-ModuleMember -Function Get-PbiTmdlTable, Get-PbiTmdlRelationships, Get-PbiTmdlExpressions, Get-NativeSqlInfo, Get-PowerQuerySourceCalls
