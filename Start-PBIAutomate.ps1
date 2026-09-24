[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

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
    Import-Module (Join-Path $root $module) -Force -ErrorAction Stop
}

Show-PBIAutomateMainForm -RootPath $root
