Set-StrictMode -Version 2.0

function Test-EnhancedPbirReportFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $definitionPbir = Join-Path $Path 'definition.pbir'
    $pagesPath = Join-Path $Path 'definition\pages'
    return (Test-Path -LiteralPath $definitionPbir -PathType Leaf) -and (Test-Path -LiteralPath $pagesPath -PathType Container)
}

function Resolve-PbiProject {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'A PBIP file, project folder, or .Report folder path is required.' }
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    $item = Get-Item -LiteralPath $resolved.Path -ErrorAction Stop
    $projectRoot = $null; $pbipFile = $null; $reportFolder = $null

    if (-not $item.PSIsContainer -and $item.Extension -ieq '.pbip') {
        $pbipFile = $item.FullName
        $projectRoot = $item.Directory.FullName
    } elseif ($item.PSIsContainer -and $item.Name -like '*.Report') {
        $reportFolder = $item.FullName
        $projectRoot = $item.Parent.FullName
    } elseif ($item.PSIsContainer) {
        $projectRoot = $item.FullName
        $pbipCandidates = @(Get-ChildItem -LiteralPath $projectRoot -Filter '*.pbip' -File -ErrorAction SilentlyContinue)
        if ($pbipCandidates.Count -eq 1) { $pbipFile = $pbipCandidates[0].FullName }
    } else {
        throw 'Unsupported path. Select a .pbip file, project folder, or .Report folder.'
    }

    if ($null -eq $reportFolder) {
        $reportCandidates = @(Get-ChildItem -LiteralPath $projectRoot -Directory -ErrorAction Stop | Where-Object { $_.Name -like '*.Report' -and (Test-EnhancedPbirReportFolder -Path $_.FullName) })
        if ($reportCandidates.Count -eq 0) { throw 'No enhanced PBIR .Report folder was found. V1 supports PBIP projects with definition\pages only.' }
        if ($reportCandidates.Count -gt 1) { throw ('Multiple enhanced .Report folders were found under "{0}". Select the required .Report folder directly.' -f $projectRoot) }
        $reportFolder = $reportCandidates[0].FullName
    }

    if (-not (Test-EnhancedPbirReportFolder -Path $reportFolder)) { throw 'The selected report does not contain the enhanced PBIR definition\pages structure.' }

    [pscustomobject]@{
        ProjectRoot   = $projectRoot
        PbipFile      = $pbipFile
        ReportFolder  = $reportFolder
        DefinitionDir = (Join-Path $reportFolder 'definition')
        PagesDir      = (Join-Path $reportFolder 'definition\pages')
        ReportName    = ([System.IO.Path]::GetFileNameWithoutExtension($reportFolder) -replace '\.Report$','')
    }
}

Export-ModuleMember -Function Resolve-PbiProject, Test-EnhancedPbirReportFolder
