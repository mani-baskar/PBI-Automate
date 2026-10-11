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
    'src\Services\Alignment\Core\OverlapResolver.psm1',
    'src\Services\Alignment\AlignmentService.psm1',
    'src\Services\Analyse\Core\SemanticModelDiscovery.psm1',
    'src\Services\Analyse\Core\TmdlReader.psm1',
    'src\Services\Analyse\Core\SourceInspector.psm1',
    'src\Services\Analyse\Core\MarkdownWriter.psm1',
    'src\Services\Analyse\AnalyseService.psm1',
    'src\UI\PreviewCanvas.psm1',
    'src\UI\MainForm.psm1',
    'src\Services\Analyse\AnalyseView.psm1'
)

foreach ($module in $modules) {
    Import-Module (Join-Path $root $module) -Force -ErrorAction Stop
}

# Keep Show-PBIAutomateMainForm in its normal modal lifetime. Its WinForms event
# handlers intentionally reference function-local scriptblocks such as
# $loadProject. Returning the form with -BuildOnly and showing it later would
# end that scope and break PBIP/Refresh events.
#
# Analyse is attached after the main form enters its message loop, while the
# Show-PBIAutomateMainForm function is still alive. This preserves the proven
# Alignment/PBIP lifecycle and lets Analyse extend the same software shell.
$analyseAttached = $false
$analyseAttachFailed = $false
$attachTimer = New-Object System.Windows.Forms.Timer
$attachTimer.Interval = 50

$attachTimer.Add_Tick({
    if ($analyseAttached -or $analyseAttachFailed) { return }

    $mainForm = $null
    foreach ($openForm in [System.Windows.Forms.Application]::OpenForms) {
        if ([string]$openForm.Name -eq 'PBIAutomateMainForm') {
            $mainForm = $openForm
            break
        }
    }

    if ($null -eq $mainForm) { return }

    try {
        Add-PbiAnalyseUi -Form $mainForm -RootPath $root | Out-Null
        $analyseAttached = $true
        $attachTimer.Stop()
    }
    catch {
        $analyseAttachFailed = $true
        $attachTimer.Stop()
        [void][System.Windows.Forms.MessageBox]::Show(
            $mainForm,
            ('Analyse UI could not be attached: ' + $_.Exception.Message),
            'PBI Automate - Analyse',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}.GetNewClosure())

$attachTimer.Start()
try {
    Show-PBIAutomateMainForm -RootPath $root
}
finally {
    $attachTimer.Stop()
    $attachTimer.Dispose()
}
