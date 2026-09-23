Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-PBIAutomateMainForm {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RootPath)

    [Windows.Forms.Application]::EnableVisualStyles()

    $state = [pscustomobject]@{ Project=$null; Pages=@(); Page=$null; Snapshot=$null; Analysis=$null; Layout=$null; LastBackup=$null }

    $form = New-Object Windows.Forms.Form
    $form.Text = 'PBI Automate — V1 Smart Layout'
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object Drawing.Size(1080,720)
    $form.Size = New-Object Drawing.Size(1280,820)
    $form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
    $form.Font = New-Object Drawing.Font('Segoe UI',9)
    $form.BackColor = [Drawing.Color]::FromArgb(245,247,250)

    $rootGrid = New-Object Windows.Forms.TableLayoutPanel
    $rootGrid.Dock='Fill'; $rootGrid.ColumnCount=1; $rootGrid.RowCount=4
    [void]$rootGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,150)))
    [void]$rootGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$rootGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,145)))
    [void]$rootGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,26)))
    $form.Controls.Add($rootGrid)

    $header = New-Object Windows.Forms.Panel; $header.Dock='Fill'; $header.Padding=New-Object Windows.Forms.Padding(14,12,14,8); $header.BackColor=[Drawing.Color]::White
    $rootGrid.Controls.Add($header,0,0)
    $headerGrid = New-Object Windows.Forms.TableLayoutPanel; $headerGrid.Dock='Fill'; $headerGrid.ColumnCount=6; $headerGrid.RowCount=3
    [void]$headerGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,110)))
    [void]$headerGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$headerGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,95)))
    [void]$headerGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,95)))
    [void]$headerGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,95)))
    [void]$headerGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,95)))
    $header.Controls.Add($headerGrid)

    function New-Label([string]$text) { $l=New-Object Windows.Forms.Label; $l.Text=$text; $l.Dock='Fill'; $l.TextAlign='MiddleLeft'; return $l }
    $txtPath=New-Object Windows.Forms.TextBox; $txtPath.Dock='Fill'
    $btnPbip=New-Object Windows.Forms.Button; $btnPbip.Text='PBIP...'; $btnPbip.Dock='Fill'
    $btnFolder=New-Object Windows.Forms.Button; $btnFolder.Text='Folder...'; $btnFolder.Dock='Fill'
    $headerGrid.Controls.Add((New-Label 'PBIP / Report Path'),0,0); $headerGrid.Controls.Add($txtPath,1,0); $headerGrid.SetColumnSpan($txtPath,3); $headerGrid.Controls.Add($btnPbip,4,0); $headerGrid.Controls.Add($btnFolder,5,0)

    $lblReport=New-Object Windows.Forms.Label; $lblReport.Text='Not loaded'; $lblReport.Dock='Fill'; $lblReport.TextAlign='MiddleLeft'; $lblReport.ForeColor=[Drawing.Color]::DimGray
    $headerGrid.Controls.Add((New-Label 'Detected Report'),0,1); $headerGrid.Controls.Add($lblReport,1,1); $headerGrid.SetColumnSpan($lblReport,5)

    $cmbPage=New-Object Windows.Forms.ComboBox; $cmbPage.Dock='Fill'; $cmbPage.DropDownStyle='DropDownList'; $cmbPage.DisplayMember='DisplayName'
    $numMargin=New-Object Windows.Forms.NumericUpDown; $numMargin.Minimum=0; $numMargin.Maximum=500; $numMargin.Value=5; $numMargin.Dock='Fill'
    $numGap=New-Object Windows.Forms.NumericUpDown; $numGap.Minimum=0; $numGap.Maximum=500; $numGap.Value=5; $numGap.Dock='Fill'
    $cmbMode=New-Object Windows.Forms.ComboBox; $cmbMode.DropDownStyle='DropDownList'; $cmbMode.Dock='Fill'; [void]$cmbMode.Items.Add('Smart Align'); $cmbMode.SelectedIndex=0
    $headerGrid.Controls.Add((New-Label 'Page'),0,2); $headerGrid.Controls.Add($cmbPage,1,2); $headerGrid.Controls.Add((New-Label 'Margin'),2,2); $headerGrid.Controls.Add($numMargin,3,2); $headerGrid.Controls.Add((New-Label 'Gap'),4,2); $headerGrid.Controls.Add($numGap,5,2)

    $bodySplit=New-Object Windows.Forms.SplitContainer; $bodySplit.Dock='Fill'; $bodySplit.Orientation='Vertical'; $bodySplit.SplitterDistance=220; $bodySplit.FixedPanel='Panel1'
    $rootGrid.Controls.Add($bodySplit,0,1)
    $bodySplit.Panel1.BackColor=[Drawing.Color]::FromArgb(30,41,59); $bodySplit.Panel1.Padding=New-Object Windows.Forms.Padding(12)
    $serviceGrid=New-Object Windows.Forms.TableLayoutPanel; $serviceGrid.Dock='Top'; $serviceGrid.ColumnCount=1; $serviceGrid.RowCount=7; $serviceGrid.Height=330
    $bodySplit.Panel1.Controls.Add($serviceGrid)
    $svcTitle=New-Object Windows.Forms.Label; $svcTitle.Text='SERVICES'; $svcTitle.ForeColor=[Drawing.Color]::LightSteelBlue; $svcTitle.Dock='Fill'; $svcTitle.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold)
    $serviceGrid.Controls.Add($svcTitle,0,0)
    function New-ServiceButton([string]$text) { $b=New-Object Windows.Forms.Button; $b.Text=$text; $b.Dock='Fill'; $b.FlatStyle='Flat'; $b.FlatAppearance.BorderSize=0; $b.BackColor=[Drawing.Color]::FromArgb(51,65,85); $b.ForeColor=[Drawing.Color]::White; $b.Margin=New-Object Windows.Forms.Padding(0,4,0,4); return $b }
    $btnAnalyze=New-ServiceButton 'Analyze Page'; $btnPreview=New-ServiceButton 'Preview Layout'; $btnApply=New-ServiceButton 'Apply Layout'; $btnUndo=New-ServiceButton 'Undo Last Apply'; $btnValidate=New-ServiceButton 'Validate'
    $serviceGrid.Controls.Add($btnAnalyze,0,1); $serviceGrid.Controls.Add($btnPreview,0,2); $serviceGrid.Controls.Add($btnApply,0,3); $serviceGrid.Controls.Add($btnUndo,0,4); $serviceGrid.Controls.Add($btnValidate,0,5)
    $btnApply.Enabled=$false

    $previewGrid=New-Object Windows.Forms.TableLayoutPanel; $previewGrid.Dock='Fill'; $previewGrid.ColumnCount=2; $previewGrid.RowCount=1; $previewGrid.Padding=New-Object Windows.Forms.Padding(10)
    [void]$previewGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50))); [void]$previewGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50)))
    $bodySplit.Panel2.Controls.Add($previewGrid)
    $beforePanel=New-LayoutPreviewPanel -Title 'Before'; $afterPanel=New-LayoutPreviewPanel -Title 'After'
    $beforePanel.Margin=New-Object Windows.Forms.Padding(0,0,5,0); $afterPanel.Margin=New-Object Windows.Forms.Padding(5,0,0,0)
    $previewGrid.Controls.Add($beforePanel,0,0); $previewGrid.Controls.Add($afterPanel,1,0)

    $console=New-Object Windows.Forms.TextBox; $console.Dock='Fill'; $console.Multiline=$true; $console.ReadOnly=$true; $console.ScrollBars='Vertical'; $console.BackColor=[Drawing.Color]::FromArgb(15,23,42); $console.ForeColor=[Drawing.Color]::FromArgb(226,232,240); $console.Font=New-Object Drawing.Font('Consolas',9); $console.BorderStyle='None'
    $rootGrid.Controls.Add($console,0,2)

    $status=New-Object Windows.Forms.StatusStrip; $status.Dock='Fill'; $statusLabel=New-Object Windows.Forms.ToolStripStatusLabel; $statusLabel.Text='Ready'; [void]$status.Items.Add($statusLabel); $rootGrid.Controls.Add($status,0,3)

    function Add-Activity([string]$Message) { $console.AppendText(('> {0}  {1}' -f (Get-Date -Format 'HH:mm:ss'),$Message)+[Environment]::NewLine); $console.SelectionStart=$console.TextLength; $console.ScrollToCaret(); $statusLabel.Text=$Message; [Windows.Forms.Application]::DoEvents() }
    function Show-Error([string]$Message) { Add-Activity ('ERROR: '+$Message); [void][Windows.Forms.MessageBox]::Show($form,$Message,'PBI Automate',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) }

    $loadProject = {
        param([string]$path)
        try {
            $state.Project = Resolve-PbiProject -Path $path
            $state.Pages = @(Get-PbiPages -ReportFolder $state.Project.ReportFolder)
            if ($state.Pages.Count -eq 0) { throw 'No report pages were found.' }
            $lblReport.Text = $state.Project.ReportFolder
            $cmbPage.DataSource = $null; $cmbPage.DataSource = $state.Pages; $cmbPage.DisplayMember='DisplayName'
            $txtPath.Text = $path
            Add-Activity ('Loaded report: '+$state.Project.ReportName+' ('+$state.Pages.Count+' pages)')
            $cmbPage.SelectedIndex=0
        } catch { Show-Error $_.Exception.Message }
    }

    $loadSelectedPage = {
        try {
            if ($null -eq $cmbPage.SelectedItem) { return }
            $state.Page = $cmbPage.SelectedItem
            $state.Snapshot = Get-PbiPageSnapshot -Page $state.Page
            $state.Analysis=$null; $state.Layout=$null; $btnApply.Enabled=$false
            Set-LayoutPreviewData -Panel $beforePanel -PageWidth $state.Snapshot.Width -PageHeight $state.Snapshot.Height -Items $state.Snapshot.Visuals -Title ('Before — '+$state.Page.DisplayName)
            Set-LayoutPreviewData -Panel $afterPanel -PageWidth $state.Snapshot.Width -PageHeight $state.Snapshot.Height -Items @() -Title 'After — Analyze to preview'
            Add-Activity ('Page ready: '+$state.Page.DisplayName+' | '+$state.Snapshot.Visuals.Count+' visuals')
        } catch { Show-Error $_.Exception.Message }
    }

    $analyze = {
        try {
            if ($null -eq $state.Snapshot) { throw 'Load a PBIP report and select a page first.' }
            Add-Activity 'Analyzing visual geometry...'
            $state.Analysis = Get-PbiLayoutAnalysis -PageSnapshot $state.Snapshot
            $state.Layout = Get-SmartPbiLayout -Analysis $state.Analysis -Margin ([double]$numMargin.Value) -Gap ([double]$numGap.Value)
            $validation = Test-PbiLayout -Layout $state.Layout
            Set-LayoutPreviewData -Panel $afterPanel -PageWidth $state.Layout.PageWidth -PageHeight $state.Layout.PageHeight -Items $state.Layout.Items -Title ('After — '+$state.Layout.Columns+' cols × '+$state.Layout.Rows+' rows')
            Add-Activity ('Detected '+$state.Analysis.ColumnCount+' columns, '+$state.Analysis.RowCount+' rows; '+$state.Layout.ChangedCount+' visuals would change.')
            if ($validation.IsValid) { Add-Activity 'Proposed layout validation passed.'; $btnApply.Enabled=($state.Layout.ChangedCount -gt 0) }
            else { foreach ($err in $validation.Errors) { Add-Activity ('Validation: '+$err) }; $btnApply.Enabled=$false }
        } catch { $btnApply.Enabled=$false; Show-Error $_.Exception.Message }
    }

    $btnPbip.Add_Click({
        $dlg=New-Object Windows.Forms.OpenFileDialog; $dlg.Filter='Power BI Project (*.pbip)|*.pbip|All files (*.*)|*.*'; $dlg.Title='Select Power BI Project'
        if ($dlg.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) { & $loadProject $dlg.FileName }
        $dlg.Dispose()
    })
    $btnFolder.Add_Click({
        $dlg=New-Object Windows.Forms.FolderBrowserDialog; $dlg.Description='Select PBIP project folder or .Report folder'; $dlg.ShowNewFolderButton=$false
        if ($dlg.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) { & $loadProject $dlg.SelectedPath }
        $dlg.Dispose()
    })
    $txtPath.Add_KeyDown({ param($s,$e) if ($e.KeyCode -eq [Windows.Forms.Keys]::Enter) { & $loadProject $txtPath.Text } })
    $cmbPage.Add_SelectedIndexChanged({ & $loadSelectedPage })
    $btnAnalyze.Add_Click({ & $analyze })
    $btnPreview.Add_Click({ & $analyze })

    $btnValidate.Add_Click({
        try {
            if ($null -eq $state.Snapshot) { throw 'Load a page first.' }
            $current = [pscustomobject]@{ PageWidth=$state.Snapshot.Width; PageHeight=$state.Snapshot.Height; Items=$state.Snapshot.Visuals }
            $result = Test-PbiLayout -Layout $current
            if ($result.IsValid) { Add-Activity ('Current page validation passed ('+$result.VisualCount+' visuals).') }
            else { foreach ($err in $result.Errors) { Add-Activity ('Validation: '+$err) } }
        } catch { Show-Error $_.Exception.Message }
    })

    $btnApply.Add_Click({
        try {
            if ($null -eq $state.Layout) { throw 'Analyze and preview the page before applying changes.' }
            $validation = Test-PbiLayout -Layout $state.Layout
            if (-not $validation.IsValid) { throw ('Proposed layout is not valid: '+($validation.Errors -join ' | ')) }
            $answer=[Windows.Forms.MessageBox]::Show($form,('Apply layout to '+$state.Layout.ChangedCount+' visual(s)? A backup will be created first.'),'Apply Layout',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Add-Activity 'Apply cancelled.'; return }
            Add-Activity 'Creating backup...'
            $state.LastBackup = New-PbiBackup -ProjectRoot $state.Project.ProjectRoot -Items $state.Layout.Items -PageName $state.Page.DisplayName
            Add-Activity ('Backup: '+$state.LastBackup.Directory)
            $write = Set-PbiLayoutFiles -Layout $state.Layout -BackupOperation $state.LastBackup
            Add-Activity ('Applied '+$write.ChangedCount+' visual file changes.')
            $state.Snapshot = Get-PbiPageSnapshot -Page $state.Page
            $post = [pscustomobject]@{ PageWidth=$state.Snapshot.Width; PageHeight=$state.Snapshot.Height; Items=$state.Snapshot.Visuals }
            $postValidation = Test-PbiLayout -Layout $post
            if (-not $postValidation.IsValid) { throw ('Post-write validation failed: '+($postValidation.Errors -join ' | ')) }
            Set-LayoutPreviewData -Panel $beforePanel -PageWidth $state.Snapshot.Width -PageHeight $state.Snapshot.Height -Items $state.Snapshot.Visuals -Title ('Current — '+$state.Page.DisplayName)
            Write-PBIAutomateLog -Message ('Applied layout to '+$state.Page.DisplayName+'; files='+$write.ChangedCount+'; backup='+$state.LastBackup.Directory) | Out-Null
            $btnApply.Enabled=$false
            Add-Activity 'Apply completed and verified. Reload/open Power BI Desktop to view the page.'
        } catch { Show-Error $_.Exception.Message }
    })

    $btnUndo.Add_Click({
        try {
            if ($null -eq $state.Project) { throw 'Load the project before using Undo.' }
            $answer=[Windows.Forms.MessageBox]::Show($form,'Restore the most recent PBI Automate backup for this project?','Undo Last Apply',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
            $undo = Undo-LatestPbiApply -ProjectRoot $state.Project.ProjectRoot
            Add-Activity ('Restored '+$undo.RestoredCount+' files from '+$undo.ManifestPath)
            & $loadSelectedPage
        } catch { Show-Error $_.Exception.Message }
    })

    Add-Activity 'PBI Automate V1 ready. Select a PBIP project or .Report folder.'
    [void]$form.ShowDialog()
    $form.Dispose()
}

Export-ModuleMember -Function Show-PBIAutomateMainForm
