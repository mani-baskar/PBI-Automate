Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-PBIAutomateIcon {
    if (-not ('PBIAutomate.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PBIAutomate {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DestroyIcon(IntPtr handle);
    }
}
'@
    }

    $bitmap = New-Object System.Drawing.Bitmap(32,32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $background = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(31,41,55))
    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245,183,47))

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.FillEllipse($background,1,1,30,30)
        $graphics.FillRectangle($accent,7,18,4,7)
        $graphics.FillRectangle($accent,14,13,4,12)
        $graphics.FillRectangle($accent,21,7,4,18)
        $handle = $bitmap.GetHicon()
        try { return ([System.Drawing.Icon]::FromHandle($handle).Clone()) }
        finally { [void][PBIAutomate.NativeMethods]::DestroyIcon($handle) }
    }
    finally {
        $accent.Dispose()
        $background.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Show-PBIAutomateMainForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [switch]$BuildOnly
    )

    [System.Windows.Forms.Application]::EnableVisualStyles()
    $config = Get-PBIAutomateConfig -RootPath $RootPath
    $services = @(Get-PBIAutomateServices)

    $state = [pscustomobject]@{
        Project = $null
        Pages = @()
        Page = $null
        Snapshot = $null
        Analysis = $null
        Layout = $null
        LastBackup = $null
        SelectedService = 'alignment'
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Name = 'PBIAutomateMainForm'
    $form.Text = ('PBI Automate - ' + [string]$config.version)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(1120,720)
    $form.Size = New-Object System.Drawing.Size(1360,860)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
    $form.Icon = New-PBIAutomateIcon

    $rootGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $rootGrid.Dock = 'Fill'
    $rootGrid.ColumnCount = 1
    $rootGrid.RowCount = 4
    [void]$rootGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,96)))
    [void]$rootGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$rootGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,145)))
    [void]$rootGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,26)))
    $form.Controls.Add($rootGrid)

    function New-FieldLabel([string]$Text) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Text
        $label.Dock = 'Fill'
        $label.TextAlign = 'MiddleLeft'
        $label.ForeColor = [System.Drawing.Color]::FromArgb(55,65,81)
        return $label
    }

    # ----------------------------------------------------------------------
    # COMMON PROJECT BAR
    # ----------------------------------------------------------------------
    $projectBar = New-Object System.Windows.Forms.Panel
    $projectBar.Name = 'CommonProjectBar'
    $projectBar.Dock = 'Fill'
    $projectBar.Padding = New-Object System.Windows.Forms.Padding(18,10,18,8)
    $projectBar.BackColor = [System.Drawing.Color]::White
    $rootGrid.Controls.Add($projectBar,0,0)

    $projectGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $projectGrid.Dock = 'Fill'
    $projectGrid.ColumnCount = 5
    $projectGrid.RowCount = 3
    [void]$projectGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,110)))
    [void]$projectGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$projectGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,100)))
    [void]$projectGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,12)))
    [void]$projectGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,100)))
    $projectBar.Controls.Add($projectGrid)

    $txtPath = New-Object System.Windows.Forms.TextBox
    $txtPath.Name = 'ProjectPathTextBox'
    $txtPath.Dock = 'Fill'
    $btnPbip = New-Object System.Windows.Forms.Button
    $btnPbip.Name = 'PBIPButton'
    $btnPbip.Text = 'PBIP...'
    $btnPbip.Dock = 'Fill'
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Name = 'RefreshButton'
    $btnRefresh.Text = 'Refresh'
    $btnRefresh.Dock = 'Fill'

    $projectGrid.Controls.Add((New-FieldLabel 'PBIP Project'),0,0)
    $projectGrid.Controls.Add($txtPath,1,0)
    $projectGrid.Controls.Add($btnPbip,2,0)
    $projectGrid.Controls.Add($btnRefresh,4,0)

    $lblReport = New-Object System.Windows.Forms.Label
    $lblReport.Name = 'DetectedReportLabel'
    $lblReport.Text = 'Not loaded'
    $lblReport.Dock = 'Fill'
    $lblReport.TextAlign = 'MiddleLeft'
    $lblReport.ForeColor = [System.Drawing.Color]::DimGray
    $projectGrid.Controls.Add((New-FieldLabel 'Detected Report'),0,1)
    $projectGrid.Controls.Add($lblReport,1,1)
    $projectGrid.SetColumnSpan($lblReport,4)

    $cmbPage = New-Object System.Windows.Forms.ComboBox
    $cmbPage.Name = 'PageSelector'
    $cmbPage.Dock = 'Fill'
    $cmbPage.DropDownStyle = 'DropDownList'
    $projectGrid.Controls.Add((New-FieldLabel 'Page'),0,2)
    $projectGrid.Controls.Add($cmbPage,1,2)
    $projectGrid.SetColumnSpan($cmbPage,4)

    # ----------------------------------------------------------------------
    # MAIN SOFTWARE SHELL: SERVICE NAVIGATION + SERVICE WORKSPACE
    # ----------------------------------------------------------------------
    $workspaceSplit = New-Object System.Windows.Forms.SplitContainer
    $workspaceSplit.Name = 'WorkspaceSplit'
    $workspaceSplit.Dock = 'Fill'
    $workspaceSplit.Orientation = 'Vertical'
    $workspaceSplit.SplitterDistance = 218
    $workspaceSplit.FixedPanel = 'Panel1'
    $workspaceSplit.IsSplitterFixed = $true
    $rootGrid.Controls.Add($workspaceSplit,0,1)

    $navPanel = $workspaceSplit.Panel1
    $navPanel.BackColor = [System.Drawing.Color]::FromArgb(30,41,59)
    $navPanel.Padding = New-Object System.Windows.Forms.Padding(12)

    $navGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $navGrid.Dock = 'Fill'
    $navGrid.ColumnCount = 1
    $navGrid.RowCount = 3
    [void]$navGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,42)))
    [void]$navGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$navGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,46)))
    $navPanel.Controls.Add($navGrid)

    $svcTitle = New-Object System.Windows.Forms.Label
    $svcTitle.Text = 'SERVICES'
    $svcTitle.Dock = 'Fill'
    $svcTitle.TextAlign = 'MiddleLeft'
    $svcTitle.ForeColor = [System.Drawing.Color]::LightSteelBlue
    $svcTitle.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $navGrid.Controls.Add($svcTitle,0,0)

    $serviceList = New-Object System.Windows.Forms.FlowLayoutPanel
    $serviceList.Name = 'ServiceNavigation'
    $serviceList.Dock = 'Fill'
    $serviceList.FlowDirection = 'TopDown'
    $serviceList.WrapContents = $false
    $serviceList.AutoScroll = $true
    $serviceList.Padding = New-Object System.Windows.Forms.Padding(0,2,0,0)
    $navGrid.Controls.Add($serviceList,0,1)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = ('PBIP Automation`r`n' + [string]$config.version)
    $versionLabel.Dock = 'Fill'
    $versionLabel.TextAlign = 'BottomLeft'
    $versionLabel.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
    $navGrid.Controls.Add($versionLabel,0,2)

    $serviceButtons = @{}
    foreach ($service in $services) {
        $button = New-Object System.Windows.Forms.Button
        $button.Name = ('Service_' + $service.Id)
        $button.Tag = [string]$service.Id
        $button.Width = 186
        $button.Height = 56
        $button.Margin = New-Object System.Windows.Forms.Padding(0,4,0,4)
        $button.FlatStyle = 'Flat'
        $button.FlatAppearance.BorderSize = 0
        $button.TextAlign = 'MiddleLeft'
        $button.Padding = New-Object System.Windows.Forms.Padding(10,0,4,0)
        $button.ForeColor = [System.Drawing.Color]::White
        $button.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
        if ([string]$service.Status -eq 'Ready') {
            $button.Text = [string]$service.Name
        }
        else {
            $button.Text = ([string]$service.Name + "`r`nComing Soon")
        }
        [void]$serviceList.Controls.Add($button)
        $serviceButtons[[string]$service.Id] = $button
    }

    $workspace = $workspaceSplit.Panel2
    $workspace.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    $serviceGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $serviceGrid.Dock = 'Fill'
    $serviceGrid.ColumnCount = 1
    $serviceGrid.RowCount = 2
    [void]$serviceGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,132)))
    [void]$serviceGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    $workspace.Controls.Add($serviceGrid)

    # Selected service options always live above its content/preview.
    $serviceOptionsHost = New-Object System.Windows.Forms.Panel
    $serviceOptionsHost.Name = 'ServiceOptionsHost'
    $serviceOptionsHost.Dock = 'Fill'
    $serviceOptionsHost.Padding = New-Object System.Windows.Forms.Padding(14,10,14,8)
    $serviceOptionsHost.BackColor = [System.Drawing.Color]::White
    $serviceGrid.Controls.Add($serviceOptionsHost,0,0)

    $alignmentOptions = New-Object System.Windows.Forms.TableLayoutPanel
    $alignmentOptions.Name = 'AlignmentOptionsPanel'
    $alignmentOptions.Dock = 'Fill'
    $alignmentOptions.ColumnCount = 1
    $alignmentOptions.RowCount = 3
    [void]$alignmentOptions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
    [void]$alignmentOptions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,38)))
    [void]$alignmentOptions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,40)))
    $serviceOptionsHost.Controls.Add($alignmentOptions)

    $alignmentTitle = New-Object System.Windows.Forms.Label
    $alignmentTitle.Text = 'Alignment Correction'
    $alignmentTitle.Dock = 'Fill'
    $alignmentTitle.TextAlign = 'MiddleLeft'
    $alignmentTitle.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
    $alignmentTitle.ForeColor = [System.Drawing.Color]::FromArgb(31,41,55)
    $alignmentOptions.Controls.Add($alignmentTitle,0,0)

    $settingsFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $settingsFlow.Dock = 'Fill'
    $settingsFlow.FlowDirection = 'LeftToRight'
    $settingsFlow.WrapContents = $false
    $settingsFlow.AutoScroll = $false
    $alignmentOptions.Controls.Add($settingsFlow,0,1)

    $lblMode = New-Object System.Windows.Forms.Label
    $lblMode.Text = 'Layout Mode'
    $lblMode.Width = 82
    $lblMode.Height = 28
    $lblMode.TextAlign = 'MiddleLeft'
    $cmbMode = New-Object System.Windows.Forms.ComboBox
    $cmbMode.Name = 'AlignmentLayoutMode'
    $cmbMode.DropDownStyle = 'DropDownList'
    $cmbMode.Width = 210
    $cmbMode.Height = 28
    [void]$cmbMode.Items.Add([string]$config.layout.mode)
    $cmbMode.SelectedIndex = 0
    $lblMargin = New-Object System.Windows.Forms.Label
    $lblMargin.Text = 'Margin'
    $lblMargin.Width = 52
    $lblMargin.Height = 28
    $lblMargin.TextAlign = 'MiddleRight'
    $numMargin = New-Object System.Windows.Forms.NumericUpDown
    $numMargin.Name = 'AlignmentMargin'
    $numMargin.Minimum = 0
    $numMargin.Maximum = 500
    $numMargin.Value = [decimal]$config.layout.margin
    $numMargin.Width = 74
    $lblGap = New-Object System.Windows.Forms.Label
    $lblGap.Text = 'Gap'
    $lblGap.Width = 42
    $lblGap.Height = 28
    $lblGap.TextAlign = 'MiddleRight'
    $numGap = New-Object System.Windows.Forms.NumericUpDown
    $numGap.Name = 'AlignmentGap'
    $numGap.Minimum = 0
    $numGap.Maximum = 500
    $numGap.Value = [decimal]$config.layout.gap
    $numGap.Width = 74

    foreach ($control in @($lblMode,$cmbMode,$lblMargin,$numMargin,$lblGap,$numGap)) {
        $control.Margin = New-Object System.Windows.Forms.Padding(0,3,8,0)
        [void]$settingsFlow.Controls.Add($control)
    }

    $actionFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $actionFlow.Dock = 'Fill'
    $actionFlow.FlowDirection = 'LeftToRight'
    $actionFlow.WrapContents = $false
    $alignmentOptions.Controls.Add($actionFlow,0,2)

    function New-ActionButton([string]$Name,[string]$Text,[int]$Width=112) {
        $button = New-Object System.Windows.Forms.Button
        $button.Name = $Name
        $button.Text = $Text
        $button.Width = $Width
        $button.Height = 30
        $button.Margin = New-Object System.Windows.Forms.Padding(0,2,8,0)
        $button.FlatStyle = 'Flat'
        $button.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.BorderSize = 0
        return $button
    }

    $btnAnalyze = New-ActionButton 'AlignmentAnalyzeButton' 'Analyze Page' 112
    $btnPreview = New-ActionButton 'AlignmentPreviewButton' 'Preview Layout' 112
    $btnApply = New-ActionButton 'AlignmentApplyButton' 'Apply Layout' 112
    $btnUndo = New-ActionButton 'AlignmentUndoButton' 'Undo Last Apply' 122
    $btnValidate = New-ActionButton 'AlignmentValidateButton' 'Validate' 96
    $btnApply.Enabled = $false
    foreach ($button in @($btnAnalyze,$btnPreview,$btnApply,$btnUndo,$btnValidate)) { [void]$actionFlow.Controls.Add($button) }

    $comingOptions = New-Object System.Windows.Forms.Panel
    $comingOptions.Name = 'ComingSoonOptionsPanel'
    $comingOptions.Dock = 'Fill'
    $comingOptions.Visible = $false
    $serviceOptionsHost.Controls.Add($comingOptions)
    $comingTitle = New-Object System.Windows.Forms.Label
    $comingTitle.Name = 'ComingSoonServiceTitle'
    $comingTitle.Dock = 'Top'
    $comingTitle.Height = 34
    $comingTitle.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
    $comingTitle.ForeColor = [System.Drawing.Color]::FromArgb(31,41,55)
    $comingTitle.TextAlign = 'MiddleLeft'
    $comingOptions.Controls.Add($comingTitle)
    $comingDescription = New-Object System.Windows.Forms.Label
    $comingDescription.Name = 'ComingSoonServiceDescription'
    $comingDescription.Dock = 'Top'
    $comingDescription.Height = 54
    $comingDescription.ForeColor = [System.Drawing.Color]::DimGray
    $comingDescription.TextAlign = 'MiddleLeft'
    $comingOptions.Controls.Add($comingDescription)

    # Preview / service content area.
    $contentHost = New-Object System.Windows.Forms.Panel
    $contentHost.Name = 'ServiceContentHost'
    $contentHost.Dock = 'Fill'
    $contentHost.Padding = New-Object System.Windows.Forms.Padding(10)
    $serviceGrid.Controls.Add($contentHost,0,1)

    $previewGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $previewGrid.Name = 'AlignmentPreviewArea'
    $previewGrid.Dock = 'Fill'
    $previewGrid.ColumnCount = 2
    $previewGrid.RowCount = 1
    [void]$previewGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    [void]$previewGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    $contentHost.Controls.Add($previewGrid)

    $beforePanel = New-LayoutPreviewPanel -Title 'Before'
    $afterPanel = New-LayoutPreviewPanel -Title 'After'
    $beforePanel.Margin = New-Object System.Windows.Forms.Padding(0,0,5,0)
    $afterPanel.Margin = New-Object System.Windows.Forms.Padding(5,0,0,0)
    $previewGrid.Controls.Add($beforePanel,0,0)
    $previewGrid.Controls.Add($afterPanel,1,0)

    $comingContent = New-Object System.Windows.Forms.Panel
    $comingContent.Name = 'ComingSoonContent'
    $comingContent.Dock = 'Fill'
    $comingContent.BackColor = [System.Drawing.Color]::White
    $comingContent.BorderStyle = 'FixedSingle'
    $comingContent.Visible = $false
    $contentHost.Controls.Add($comingContent)
    $comingContentLabel = New-Object System.Windows.Forms.Label
    $comingContentLabel.Text = 'Coming Soon'
    $comingContentLabel.Dock = 'Fill'
    $comingContentLabel.TextAlign = 'MiddleCenter'
    $comingContentLabel.Font = New-Object System.Drawing.Font('Segoe UI',18,[System.Drawing.FontStyle]::Bold)
    $comingContentLabel.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
    $comingContent.Controls.Add($comingContentLabel)

    # ----------------------------------------------------------------------
    # PROCESSING / STATUS FOOTER
    # ----------------------------------------------------------------------
    $consolePanel = New-Object System.Windows.Forms.Panel
    $consolePanel.Dock = 'Fill'
    $consolePanel.Padding = New-Object System.Windows.Forms.Padding(6,4,6,2)
    $consolePanel.BackColor = [System.Drawing.Color]::FromArgb(15,23,42)
    $rootGrid.Controls.Add($consolePanel,0,2)

    $console = New-Object System.Windows.Forms.TextBox
    $console.Name = 'ProcessingConsole'
    $console.Dock = 'Fill'
    $console.Multiline = $true
    $console.ReadOnly = $true
    $console.ScrollBars = 'Vertical'
    $console.BackColor = [System.Drawing.Color]::FromArgb(15,23,42)
    $console.ForeColor = [System.Drawing.Color]::FromArgb(226,232,240)
    $console.Font = New-Object System.Drawing.Font('Consolas',9)
    $console.BorderStyle = 'None'
    $consolePanel.Controls.Add($console)

    $status = New-Object System.Windows.Forms.StatusStrip
    $status.Dock = 'Fill'
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = 'Ready'
    [void]$status.Items.Add($statusLabel)
    $rootGrid.Controls.Add($status,0,3)

    function Add-Activity([string]$Message) {
        $console.AppendText(('> {0}  {1}' -f (Get-Date -Format 'HH:mm:ss'),$Message)+[Environment]::NewLine)
        $console.SelectionStart = $console.TextLength
        $console.ScrollToCaret()
        $statusLabel.Text = $Message
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Show-Error([string]$Message) {
        Add-Activity ('ERROR: '+$Message)
        [void][System.Windows.Forms.MessageBox]::Show($form,$Message,'PBI Automate',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    }

    $invalidateAlignment = {
        if ($null -ne $state.Layout) {
            $state.Layout = $null
            $state.Analysis = $null
            $btnApply.Enabled = $false
            if ($null -ne $state.Snapshot) {
                Set-LayoutPreviewData -Panel $afterPanel -PageWidth $state.Snapshot.Width -PageHeight $state.Snapshot.Height -Items @() -Title 'After - settings changed; preview again'
                Add-Activity 'Alignment settings changed. Preview again before Apply.'
            }
        }
    }

    $loadSelectedPage = {
        try {
            if ($cmbPage.SelectedIndex -lt 0 -or $cmbPage.SelectedIndex -ge $state.Pages.Count) { return }
            $state.Page = $state.Pages[$cmbPage.SelectedIndex]
            $state.Snapshot = Get-PbiPageSnapshot -Page $state.Page
            $state.Analysis = $null
            $state.Layout = $null
            $btnApply.Enabled = $false

            $activeVisuals = @(Get-PbiActivePageVisuals -PageSnapshot $state.Snapshot)
            $hiddenCount = @($state.Snapshot.Visuals | Where-Object {
                if ($_.PSObject.Properties.Name -contains 'EffectiveHidden') { [bool]$_.EffectiveHidden } else { [bool]$_.IsHidden }
            }).Count
            $groupCount = @($state.Snapshot.Visuals | Where-Object { [bool]$_.IsVisualGroup }).Count

            Set-LayoutPreviewData -Panel $beforePanel -PageWidth $state.Snapshot.Width -PageHeight $state.Snapshot.Height -Items $activeVisuals -Title ('Before - '+$state.Page.DisplayName)
            Set-LayoutPreviewData -Panel $afterPanel -PageWidth $state.Snapshot.Width -PageHeight $state.Snapshot.Height -Items @() -Title 'After - Analyze to preview'
            Add-Activity ('Page ready: '+$state.Page.DisplayName+' | total='+$state.Snapshot.Visuals.Count+'; active='+$activeVisuals.Count+'; hidden='+$hiddenCount+'; group containers='+$groupCount)
        }
        catch { Show-Error $_.Exception.Message }
    }

    $loadProject = {
        param([string]$Path,[string]$PreservePageName='')
        try {
            $project = Resolve-PbiProject -Path $Path
            $pages = @(Get-PbiPages -ReportFolder $project.ReportFolder)
            if ($pages.Count -eq 0) { throw 'No report pages were found.' }

            $state.Project = $project
            $state.Pages = $pages
            $lblReport.Text = $project.ReportFolder
            $txtPath.Text = $Path
            $cmbPage.Items.Clear()

            $targetIndex = 0
            for ($i=0; $i -lt $pages.Count; $i++) {
                $pageItem = $pages[$i]
                $pageText = [string]$pageItem.DisplayName
                if ([double]$pageItem.Width -gt 0 -and [double]$pageItem.Height -gt 0) {
                    $pageText += (' ('+[int]$pageItem.Width+' x '+[int]$pageItem.Height+')')
                }
                [void]$cmbPage.Items.Add($pageText)
                if (-not [string]::IsNullOrWhiteSpace($PreservePageName) -and [string]$pageItem.Name -eq $PreservePageName) { $targetIndex = $i }
            }

            Add-Activity ('Loaded project: '+$project.ReportName+' ('+$pages.Count+' pages)')
            $cmbPage.SelectedIndex = $targetIndex
        }
        catch { Show-Error $_.Exception.Message }
    }

    $previewAlignment = {
        try {
            if ($null -eq $state.Snapshot) { throw 'Load a PBIP project and select a page first.' }
            Add-Activity 'Analyzing alignment geometry...'
            $result = Invoke-AlignmentPreview -PageSnapshot $state.Snapshot -Config $config -Margin ([double]$numMargin.Value) -Gap ([double]$numGap.Value)
            $state.Analysis = $result.Analysis
            $state.Layout = $result.Layout

            if ($result.OverlapNormalization.HadOverlaps) {
                $fallbackText = if ($result.OverlapNormalization.UsedCompactFallback) { '; compact fallback used' } else { '' }
                Add-Activity ('Pre-normalize overlap: pairs='+$result.OverlapNormalization.InitialOverlapPairCount+'; moved='+$result.OverlapNormalization.MovedCount+'; resized='+$result.OverlapNormalization.ResizedCount+'; remaining='+$result.OverlapNormalization.RemainingOverlapPairCount+$fallbackText)
            }

            $strategyLabel = if ($state.Layout.PSObject.Properties.Name -contains 'LayoutStrategy') { [string]$state.Layout.LayoutStrategy } else { 'Smart Align' }
            Set-LayoutPreviewData -Panel $afterPanel -PageWidth $state.Layout.PageWidth -PageHeight $state.Layout.PageHeight -Items $state.Layout.Items -Title ('After - '+$strategyLabel+' | '+$state.Layout.Columns+' cols x '+$state.Layout.Rows+' rows')

            $areaText = ''
            if ($state.Layout.PSObject.Properties.Name -contains 'MaxAreaShareDeltaPercent' -and $null -ne $state.Layout.MaxAreaShareDeltaPercent) {
                $areaText = '; max occupied-area share drift='+$state.Layout.MaxAreaShareDeltaPercent+'%'
            }
            Add-Activity ('Alignment: active='+$state.Analysis.ActiveVisualCount+'; hidden ignored='+$state.Analysis.HiddenVisualCount+'; group containers ignored='+$state.Analysis.GroupContainerCount+'; visible grouped children='+$state.Analysis.ActiveGroupedVisualCount+'; '+$state.Analysis.ColumnCount+' columns, '+$state.Analysis.RowCount+' rows; strategy='+$strategyLabel+$areaText+'; '+$state.Layout.ChangedCount+' visual(s) would change.')

            if ($result.Validation.IsValid) {
                Add-Activity 'Proposed alignment validation passed.'
                $btnApply.Enabled = ($state.Layout.ChangedCount -gt 0)
            }
            else {
                foreach ($err in $result.Validation.Errors) { Add-Activity ('Validation: '+$err) }
                $btnApply.Enabled = $false
            }
        }
        catch {
            $btnApply.Enabled = $false
            Show-Error $_.Exception.Message
        }
    }

    $showService = {
        param([string]$ServiceId)

        $state.SelectedService = $ServiceId
        foreach ($key in @($serviceButtons.Keys)) {
            $serviceButtons[$key].BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
            $serviceButtons[$key].ForeColor = [System.Drawing.Color]::White
        }
        if ($serviceButtons.ContainsKey($ServiceId)) {
            $serviceButtons[$ServiceId].BackColor = [System.Drawing.Color]::FromArgb(245,183,47)
            $serviceButtons[$ServiceId].ForeColor = [System.Drawing.Color]::FromArgb(31,41,55)
        }

        if ($ServiceId -eq 'alignment') {
            $comingOptions.Visible = $false
            $comingContent.Visible = $false
            $alignmentOptions.Visible = $true
            $previewGrid.Visible = $true
            $alignmentOptions.BringToFront()
            $previewGrid.BringToFront()
            Add-Activity 'Service selected: Alignment Correction'
            return
        }

        $service = @($services | Where-Object { [string]$_.Id -eq $ServiceId })[0]
        $alignmentOptions.Visible = $false
        $previewGrid.Visible = $false
        $comingOptions.Visible = $true
        $comingContent.Visible = $true
        $comingTitle.Text = [string]$service.Name
        $comingDescription.Text = ([string]$service.Description + '  Status: Coming Soon.')
        $comingContentLabel.Text = ([string]$service.Name + "`r`nComing Soon")
        $comingOptions.BringToFront()
        $comingContent.BringToFront()
        Add-Activity ('Service selected: '+$service.Name+' - Coming Soon')
    }

    foreach ($service in $services) {
        $id = [string]$service.Id
        $serviceButtons[$id].Add_Click({
            param($sender,$eventArgs)
            & $showService ([string]$sender.Tag)
        })
    }

    $btnPbip.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Power BI Project (*.pbip)|*.pbip|All files (*.*)|*.*'
        $dlg.Title = 'Select Power BI Project'
        if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { & $loadProject $dlg.FileName '' }
        $dlg.Dispose()
    })

    $btnRefresh.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtPath.Text)) { Show-Error 'Select a PBIP project first.'; return }
        $pageName = if ($null -ne $state.Page) { [string]$state.Page.Name } else { '' }
        Add-Activity 'Refreshing PBIP files from disk...'
        & $loadProject $txtPath.Text $pageName
    })

    $txtPath.Add_KeyDown({
        param($sender,$eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { & $loadProject $txtPath.Text '' }
    })
    $cmbPage.Add_SelectedIndexChanged({ & $loadSelectedPage })
    $numMargin.Add_ValueChanged({ & $invalidateAlignment })
    $numGap.Add_ValueChanged({ & $invalidateAlignment })
    $cmbMode.Add_SelectedIndexChanged({ & $invalidateAlignment })
    $btnAnalyze.Add_Click({ & $previewAlignment })
    $btnPreview.Add_Click({ & $previewAlignment })

    $btnValidate.Add_Click({
        try {
            if ($null -eq $state.Snapshot) { throw 'Load a page first.' }
            $result = Test-AlignmentCurrentPage -PageSnapshot $state.Snapshot
            if ($result.IsValid) { Add-Activity ('Current page validation passed ('+$result.VisualCount+' visuals).') }
            else { foreach ($err in $result.Errors) { Add-Activity ('Validation: '+$err) } }
        }
        catch { Show-Error $_.Exception.Message }
    })

    $btnApply.Add_Click({
        try {
            if ($null -eq $state.Layout) { throw 'Analyze and preview the page before applying changes.' }
            $answer = [System.Windows.Forms.MessageBox]::Show($form,('Apply alignment to '+$state.Layout.ChangedCount+' visual(s)? A backup will be created first.'),'Apply Alignment',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { Add-Activity 'Apply cancelled.'; return }

            Add-Activity 'Creating backup and applying alignment...'
            $apply = Invoke-AlignmentApply -ProjectRoot $state.Project.ProjectRoot -PageName $state.Page.DisplayName -Layout $state.Layout
            $state.LastBackup = $apply.Backup
            Add-Activity ('Backup: '+$apply.Backup.Directory)
            Add-Activity ('Applied '+$apply.Write.ChangedCount+' visual file change(s).')

            $state.Snapshot = Get-PbiPageSnapshot -Page $state.Page
            $postValidation = Test-AlignmentCurrentPage -PageSnapshot $state.Snapshot
            if (-not $postValidation.IsValid) { throw ('Post-write validation failed: '+($postValidation.Errors -join ' | ')) }
            Set-LayoutPreviewData -Panel $beforePanel -PageWidth $state.Snapshot.Width -PageHeight $state.Snapshot.Height -Items $state.Snapshot.Visuals -Title ('Current - '+$state.Page.DisplayName)
            Write-PBIAutomateLog -Message ('Alignment applied to '+$state.Page.DisplayName+'; files='+$apply.Write.ChangedCount+'; backup='+$apply.Backup.Directory) | Out-Null
            $state.Analysis = $null
            $state.Layout = $null
            $btnApply.Enabled = $false
            Add-Activity 'Alignment completed and verified. Reload/open Power BI Desktop to view the page.'
        }
        catch { Show-Error $_.Exception.Message }
    })

    $btnUndo.Add_Click({
        try {
            if ($null -eq $state.Project) { throw 'Load the project before using Undo.' }
            $answer = [System.Windows.Forms.MessageBox]::Show($form,'Restore the most recent PBI Automate alignment backup for this project?','Undo Last Apply',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $undo = Invoke-AlignmentUndo -ProjectRoot $state.Project.ProjectRoot
            Add-Activity ('Restored '+$undo.RestoredCount+' file(s) from '+$undo.ManifestPath)
            & $loadSelectedPage
        }
        catch { Show-Error $_.Exception.Message }
    })

    Add-Activity 'PBI Automate ready. Select a PBIP project.'
    & $showService 'alignment'

    if ($BuildOnly) { return $form }

    [void]$form.ShowDialog()
    $form.Dispose()
}

Export-ModuleMember -Function Show-PBIAutomateMainForm
