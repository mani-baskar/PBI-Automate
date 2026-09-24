Set-StrictMode -Version 2.0

function Test-EnhancedPbirReportFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    $definitionPbir = Join-Path $Path 'definition.pbir'
    $pagesPath = Join-Path $Path 'definition\pages'
    return (Test-Path -LiteralPath $definitionPbir -PathType Leaf) -and
           (Test-Path -LiteralPath $pagesPath -PathType Container)
}

function Resolve-PbipReportArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$PbipFile)

    if (-not (Test-Path -LiteralPath $PbipFile -PathType Leaf)) {
        throw ('PBIP file not found: {0}' -f $PbipFile)
    }

    try {
        $pbip = Get-Content -LiteralPath $PbipFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw ('Invalid PBIP JSON in "{0}": {1}' -f $PbipFile,$_.Exception.Message)
    }

    if (-not ($pbip.PSObject.Properties.Name -contains 'artifacts')) {
        return $null
    }

    $projectRoot = Split-Path -Parent $PbipFile
    $reportPaths = New-Object System.Collections.Generic.List[string]

    foreach ($artifact in @($pbip.artifacts)) {
        if ($null -eq $artifact) { continue }
        if (-not ($artifact.PSObject.Properties.Name -contains 'report')) { continue }
        if ($null -eq $artifact.report) { continue }
        if (-not ($artifact.report.PSObject.Properties.Name -contains 'path')) { continue }

        $relative = [string]$artifact.report.path
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }

        $candidate = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
        if (-not $reportPaths.Contains($candidate)) {
            $reportPaths.Add($candidate)
        }
    }

    if ($reportPaths.Count -eq 0) { return $null }
    if ($reportPaths.Count -gt 1) {
        throw ('PBIP file references multiple report artifacts. Select the required .Report folder directly. PBIP: {0}' -f $PbipFile)
    }

    $reportFolder = $reportPaths[0]
    if (-not (Test-Path -LiteralPath $reportFolder -PathType Container)) {
        throw ('The report folder referenced by the PBIP file does not exist: {0}' -f $reportFolder)
    }
    if (-not (Test-EnhancedPbirReportFolder -Path $reportFolder)) {
        throw ('The report referenced by the PBIP file is not enhanced PBIR: {0}' -f $reportFolder)
    }

    return $reportFolder
}

function Resolve-PbiProject {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'A PBIP file, project folder, or .Report folder path is required.'
    }

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    $item = Get-Item -LiteralPath $resolved.Path -ErrorAction Stop

    $projectRoot = $null
    $pbipFile = $null
    $reportFolder = $null

    if (-not $item.PSIsContainer -and $item.Extension -ieq '.pbip') {
        $pbipFile = $item.FullName
        $projectRoot = $item.Directory.FullName
        $reportFolder = Resolve-PbipReportArtifact -PbipFile $pbipFile
    }
    elseif ($item.PSIsContainer -and $item.Name -like '*.Report') {
        $reportFolder = $item.FullName
        $projectRoot = $item.Parent.FullName
    }
    elseif ($item.PSIsContainer) {
        $projectRoot = $item.FullName
        $pbipCandidates = @(Get-ChildItem -LiteralPath $projectRoot -Filter '*.pbip' -File -ErrorAction SilentlyContinue)

        if ($pbipCandidates.Count -eq 1) {
            $pbipFile = $pbipCandidates[0].FullName
            $reportFolder = Resolve-PbipReportArtifact -PbipFile $pbipFile
        }
    }
    else {
        throw 'Unsupported path. Select a .pbip file, project folder, or .Report folder.'
    }

    if ($null -eq $reportFolder) {
        $reportCandidates = @(
            Get-ChildItem -LiteralPath $projectRoot -Directory -ErrorAction Stop |
            Where-Object { $_.Name -like '*.Report' -and (Test-EnhancedPbirReportFolder -Path $_.FullName) }
        )

        if ($reportCandidates.Count -eq 0) {
            throw 'No enhanced PBIR .Report folder was found. V1 supports PBIP projects with definition\pages only.'
        }
        if ($reportCandidates.Count -gt 1) {
            throw ('Multiple enhanced .Report folders were found under "{0}". Select a .pbip file that references the report, or select the required .Report folder directly.' -f $projectRoot)
        }

        $reportFolder = $reportCandidates[0].FullName
    }

    if (-not (Test-EnhancedPbirReportFolder -Path $reportFolder)) {
        throw 'The selected report does not contain the enhanced PBIR definition\pages structure.'
    }

    [pscustomobject]@{
        ProjectRoot   = $projectRoot
        PbipFile      = $pbipFile
        ReportFolder  = $reportFolder
        DefinitionDir = (Join-Path $reportFolder 'definition')
        PagesDir      = (Join-Path $reportFolder 'definition\pages')
        ReportName    = [System.IO.Path]::GetFileNameWithoutExtension($reportFolder)
    }
}

Export-ModuleMember -Function Resolve-PbiProject, Test-EnhancedPbirReportFolder, Resolve-PbipReportArtifact
