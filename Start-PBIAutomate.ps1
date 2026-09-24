[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$modules = @(
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
    'src\Services\Alignment\AlignmentService.psm1',
    'src\UI\PreviewCanvas.psm1',
    'src\UI\MainForm.psm1'
)

foreach ($module in $modules) {
    Import-Module (Join-Path $root $module) -Force -ErrorAction Stop
}

Show-PBIAutomateMainForm -RootPath $root
