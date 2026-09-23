[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$modules = @(
    'src\Core\Logging.psm1',
    'src\Core\ProjectDiscovery.psm1',
    'src\Core\PBIRReader.psm1',
    'src\Core\LayoutAnalyzer.psm1',
    'src\Core\SmartLayoutEngine.psm1'
)

foreach ($module in $modules) {
    Import-Module (Join-Path $root $module) -Force -ErrorAction Stop
}

$uiModule = Join-Path $root 'src\UI\MainForm.psm1'
if (-not (Test-Path -LiteralPath $uiModule)) {
    Write-Host 'PBI Automate V1 core is installed on this branch.'
    Write-Host 'The WinForms UI module is being added in the next V1 batch.'
    Write-Host ''
    Write-Host 'Core smoke test:'
    Write-Host '  Import-Module .\src\Core\ProjectDiscovery.psm1'
    Write-Host '  Resolve-PbiProject -Path <your .pbip or .Report path>'
    exit 0
}

Import-Module $uiModule -Force -ErrorAction Stop
Show-PBIAutomateMainForm -RootPath $root
