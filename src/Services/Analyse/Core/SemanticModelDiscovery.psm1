Set-StrictMode -Version 2.0

function Resolve-PbiSemanticModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$ReportFolder
    )

    $projectRootFull = (Get-Item -LiteralPath $ProjectRoot -ErrorAction Stop).FullName
    $reportFolderFull = (Get-Item -LiteralPath $ReportFolder -ErrorAction Stop).FullName
    $definitionPbir = Join-Path $reportFolderFull 'definition.pbir'
    $semanticFolder = $null
    $detectionMethod = $null

    if (Test-Path -LiteralPath $definitionPbir -PathType Leaf) {
        try {
            $reportDefinition = Get-Content -LiteralPath $definitionPbir -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $reportDefinition.datasetReference -and
                $null -ne $reportDefinition.datasetReference.byPath -and
                -not [string]::IsNullOrWhiteSpace([string]$reportDefinition.datasetReference.byPath.path)) {
                $candidate = Join-Path $reportFolderFull ([string]$reportDefinition.datasetReference.byPath.path)
                if (Test-Path -LiteralPath $candidate -PathType Container) {
                    $semanticFolder = (Get-Item -LiteralPath $candidate).FullName
                    $detectionMethod = 'definition.pbir datasetReference.byPath'
                }
            }
        }
        catch {
            # Fallback discovery below is intentionally allowed when definition.pbir is older or malformed.
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$semanticFolder)) {
        $semanticCandidates = @(Get-ChildItem -LiteralPath $projectRootFull -Directory -Filter '*.SemanticModel' -ErrorAction SilentlyContinue)

        if ($semanticCandidates.Count -eq 1) {
            $semanticFolder = $semanticCandidates[0].FullName
            $detectionMethod = 'single sibling *.SemanticModel folder'
        }
        elseif ($semanticCandidates.Count -gt 1) {
            $reportBaseName = [System.IO.Path]::GetFileNameWithoutExtension($reportFolderFull)
            $nameMatch = @($semanticCandidates | Where-Object {
                [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -ieq $reportBaseName
            })
            if ($nameMatch.Count -eq 1) {
                $semanticFolder = $nameMatch[0].FullName
                $detectionMethod = 'matching sibling *.SemanticModel folder'
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$semanticFolder)) {
        throw 'Unable to resolve a local .SemanticModel folder for the selected PBIP report. The report may use a remote semantic model or the local dataset reference is missing.'
    }

    $definitionFolder = Join-Path $semanticFolder 'definition'
    if (-not (Test-Path -LiteralPath $definitionFolder -PathType Container)) {
        throw ('Semantic model does not contain a TMDL definition folder: ' + $semanticFolder)
    }

    $tablesFolder = Join-Path $definitionFolder 'tables'
    if (-not (Test-Path -LiteralPath $tablesFolder -PathType Container)) {
        throw ('Semantic model does not contain definition\tables: ' + $semanticFolder)
    }

    [pscustomobject]@{
        SemanticModelFolder = $semanticFolder
        DefinitionFolder = $definitionFolder
        TablesFolder = $tablesFolder
        RelationshipsFile = Join-Path $definitionFolder 'relationships.tmdl'
        ExpressionsFile = Join-Path $definitionFolder 'expressions.tmdl'
        ModelFile = Join-Path $definitionFolder 'model.tmdl'
        DetectionMethod = $detectionMethod
    }
}

function Get-PbiAnalyseDefaultOutputRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath)

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { return '' }

    if (Test-Path -LiteralPath $ProjectPath -PathType Leaf) {
        return (Split-Path -Parent (Get-Item -LiteralPath $ProjectPath).FullName)
    }

    if (Test-Path -LiteralPath $ProjectPath -PathType Container) {
        return (Get-Item -LiteralPath $ProjectPath).FullName
    }

    return ''
}

Export-ModuleMember -Function Resolve-PbiSemanticModel, Get-PbiAnalyseDefaultOutputRoot
