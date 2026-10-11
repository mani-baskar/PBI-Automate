Set-StrictMode -Version 2.0

function ConvertFrom-PowerQueryStringLiteral {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $text = $Value.Trim()
    if ($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')) {
        $text = $text.Substring(1,$text.Length-2)
    }
    return $text.Replace('""','"').Replace('#(lf)',[Environment]::NewLine).Replace('#(cr)',[Environment]::NewLine)
}

function Protect-SourceTargetText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return '' }
    $safe = [string]$Text
    $safe = [regex]::Replace($safe,'(?i)(Password|Pwd|AccessToken|RefreshToken|Token|ClientSecret|ApiKey|Api_Key|Credential)\s*=\s*"(?:[^"]|"")*"','$1="<redacted>"')
    $safe = [regex]::Replace($safe,'(?i)(Password|Pwd|AccessToken|RefreshToken|Token|ClientSecret|ApiKey|Api_Key|Credential)\s*=\s*([^;,\]\}\r\n]+)','$1=<redacted>')
    $urlSecretPattern = '(?i)([?&](?:access_token|token|api_key|apikey|sig|client_secret)=)[^&\s"]+'
    return [regex]::Replace($safe,$urlSecretPattern,'$1<redacted>')
}

function Add-PbiSourceTarget {
    param(
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory=$true)][string]$Connector,
        [Parameter(Mandatory=$true)][string]$Target
    )

    $clean = Protect-SourceTargetText (ConvertFrom-PowerQueryStringLiteral $Target)
    if ([string]::IsNullOrWhiteSpace($clean)) { return }

    $display = $Connector + ': ' + $clean
    if (@($List | Where-Object { $_.Display -eq $display }).Count -eq 0) {
        [void]$List.Add([pscustomobject]@{
            Connector = $Connector
            Target = $clean
            Display = $display
        })
    }
}

function Get-PbiPowerQueryConnectionTargets {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    $result = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    # Two-string connectors: server/account + database/catalog.
    $twoArgConnectors = @(
        'Sql\.Database',
        'PostgreSQL\.Database',
        'MySQL\.Database',
        'AnalysisServices\.Database'
    )
    foreach ($connectorPattern in $twoArgConnectors) {
        $pattern = '(?is)\b(' + $connectorPattern + ')\s*\(\s*("(?:[^"]|"")*")\s*,\s*("(?:[^"]|"")*")'
        foreach ($match in [regex]::Matches($Text,$pattern)) {
            $connector = [string]$match.Groups[1].Value
            $first = ConvertFrom-PowerQueryStringLiteral ([string]$match.Groups[2].Value)
            $second = ConvertFrom-PowerQueryStringLiteral ([string]$match.Groups[3].Value)
            Add-PbiSourceTarget -List $result -Connector $connector -Target ($first + ' / ' + $second)
        }
    }

    # One-string connectors and nested file/web sources.
    $oneArgConnectors = @(
        'File\.Contents',
        'Web\.Contents',
        'SharePoint\.Files',
        'SharePoint\.Contents',
        'Oracle\.Database',
        'Snowflake\.Databases',
        'Odbc\.DataSource',
        'Odbc\.Query',
        'OleDb\.DataSource',
        'OleDb\.Query'
    )
    foreach ($connectorPattern in $oneArgConnectors) {
        $pattern = '(?is)\b(' + $connectorPattern + ')\s*\(\s*("(?:[^"]|"")*")'
        foreach ($match in [regex]::Matches($Text,$pattern)) {
            Add-PbiSourceTarget -List $result -Connector ([string]$match.Groups[1].Value) -Target ([string]$match.Groups[2].Value)
        }
    }

    # Common PBIR/TMDL navigation values help BigQuery and similar hierarchical connectors.
    foreach ($match in [regex]::Matches($Text,'(?i)\[\s*Name\s*=\s*"([^"]+)"\s*,\s*Kind\s*=\s*"(Database|Schema|Table|View|Project|Dataset)"\s*\]')) {
        $name = [string]$match.Groups[1].Value
        $kind = [string]$match.Groups[2].Value
        Add-PbiSourceTarget -List $result -Connector ('Navigation ' + $kind) -Target $name
    }

    return @($result)
}

function Format-PbiPowerQueryConnectionTargets {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    $targets = @(Get-PbiPowerQueryConnectionTargets -Text $Text)
    if ($targets.Count -eq 0) { return '' }
    return (@($targets | ForEach-Object { $_.Display }) -join '; ')
}

Export-ModuleMember -Function Get-PbiPowerQueryConnectionTargets, Format-PbiPowerQueryConnectionTargets
