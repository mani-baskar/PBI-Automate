Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Find-AnalyseControl {
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [Parameter(Mandatory=$true)][string]$Name
    )

    foreach ($control in $Parent.Controls) {
        if ([string]$control.Name -eq $Name) { return $control }
        if ($control.Controls.Count -gt 0) {
            $found = Find-AnalyseControl -Parent $control -Name $Name
            if ($null -ne $found) { return $found }
        }
    }
    return $null
}

function Add-PbiAnalyseUi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory=$true)][string]$RootPath
    )

    $optionsHost = Find-AnalyseControl -Parent $Form -Name 'ServiceOptionsHost'
    $contentHost = Find-AnalyseControl -Parent $Form -Name 'ServiceContentHost'
    $alignmentOptions = Find-AnalyseControl -Parent $Form -Name 'AlignmentOptionsPanel'
    $alignmentContent = Find-AnalyseControl -Parent $Form -Name 'AlignmentPreviewArea'
    $comingOptions = Find-AnalyseControl -Parent $Form -Name 'ComingSoonOptionsPanel'
    $comingContent = Find-AnalyseControl -Parent $Form -Name 'ComingSoonContent'
    $projectText = Find-AnalyseControl -Parent $Form -Name 'ProjectPathTextBox'
    $analyseButton = Find-AnalyseControl -Parent $Form -Name 'Service_analyse'
    $console = Find-AnalyseControl -Parent $Form -Name 'ProcessingConsole'

    if ($null -eq $optionsHost -or $null -eq $contentHost -or $null -eq $projectText -or $null -eq $analyseButton) {
        throw 'Analyse UI could not attach to the PBI Automate shell.'
    }

    $writeActivity = {
        param([string]$Message)
        if ($null -ne $console) {
            $console.AppendText(('> {0}  {1}' -f (Get-Date -Format 'HH:mm:ss'),$Message)+[Environment]::NewLine)
            $console.SelectionStart = $console.TextLength
            $console.ScrollToCaret()
        }
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $showError = {
        param([string]$Message)
        & $writeActivity ('ERROR: ' + $Message)
        [void][System.Windows.Forms.MessageBox]::Show($Form,$Message,'PBI Automate - Analyse',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    }.GetNewClosure()

    # ------------------------------------------------------------------
    # ANALYSE OPTIONS
    # ------------------------------------------------------------------
    $analyseOptions = New-Object System.Windows.Forms.TableLayoutPanel
    $analyseOptions.Name = 'AnalyseOptionsPanel'
    $analyseOptions.Dock = 'Fill'
    $analyseOptions.ColumnCount = 1
    $analyseOptions.RowCount = 3
    $analyseOptions.Visible = $false
    [void]$analyseOptions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
    [void]$analyseOptions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,38)))
    [void]$analyseOptions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,40)))
    $optionsHost.Controls.Add($analyseOptions)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Analyse'
    $title.Dock = 'Fill'
    $title.TextAlign = 'MiddleLeft'
    $title.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(31,41,55)
    $analyseOptions.Controls.Add($title,0,0)

    $folderGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $folderGrid.Dock = 'Fill'
    $folderGrid.ColumnCount = 3
    $folderGrid.RowCount = 1
    [void]$folderGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,92)))
    [void]$folderGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$folderGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,105)))
    $analyseOptions.Controls.Add($folderGrid,0,1)

    $folderLabel = New-Object System.Windows.Forms.Label
    $folderLabel.Text = 'Output Folder'
    $folderLabel.Dock = 'Fill'
    $folderLabel.TextAlign = 'MiddleLeft'
    $folderGrid.Controls.Add($folderLabel,0,0)

    $outputText = New-Object System.Windows.Forms.TextBox
    $outputText.Name = 'AnalyseOutputRoot'
    $outputText.Dock = 'Fill'
    $folderGrid.Controls.Add($outputText,1,0)

    $folderButton = New-Object System.Windows.Forms.Button
    $folderButton.Name = 'AnalyseFolderButton'
    $folderButton.Text = 'Folder...'
    $folderButton.Dock = 'Fill'
    $folderButton.Margin = New-Object System.Windows.Forms.Padding(8,0,0,0)
    $folderGrid.Controls.Add($folderButton,2,0)

    $actions = New-Object System.Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Fill'
    $actions.FlowDirection = 'LeftToRight'
    $actions.WrapContents = $false
    $analyseOptions.Controls.Add($actions,0,2)

    function New-AnalyseButton([string]$Name,[string]$Text,[int]$Width) {
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

    $scanButton = New-AnalyseButton 'AnalyseScanButton' 'Scan Model' 108
    $generateButton = New-AnalyseButton 'AnalyseGenerateButton' 'Generate Markdown' 142
    $openButton = New-AnalyseButton 'AnalyseOpenFolderButton' 'Open Analyse' 116
    $openButton.Enabled = $false
    foreach ($button in @($scanButton,$generateButton,$openButton)) { [void]$actions.Controls.Add($button) }

    # ------------------------------------------------------------------
    # ANALYSE CONTENT
    # ------------------------------------------------------------------
    $analyseContent = New-Object System.Windows.Forms.Panel
    $analyseContent.Name = 'AnalyseContent'
    $analyseContent.Dock = 'Fill'
    $analyseContent.Visible = $false
    $analyseContent.BackColor = [System.Drawing.Color]::White
    $analyseContent.BorderStyle = 'FixedSingle'
    $analyseContent.Padding = New-Object System.Windows.Forms.Padding(24)
    $contentHost.Controls.Add($analyseContent)

    $contentGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $contentGrid.Dock = 'Fill'
    $contentGrid.ColumnCount = 1
    $contentGrid.RowCount = 6
    [void]$contentGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,46)))
    [void]$contentGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,54)))
    [void]$contentGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,42)))
    [void]$contentGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,42)))
    [void]$contentGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,42)))
    [void]$contentGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    $analyseContent.Controls.Add($contentGrid)

    $headline = New-Object System.Windows.Forms.Label
    $headline.Text = 'PBIP Model Documentation'
    $headline.Dock = 'Fill'
    $headline.TextAlign = 'MiddleLeft'
    $headline.Font = New-Object System.Drawing.Font('Segoe UI',17,[System.Drawing.FontStyle]::Bold)
    $headline.ForeColor = [System.Drawing.Color]::FromArgb(31,41,55)
    $contentGrid.Controls.Add($headline,0,0)

    $description = New-Object System.Windows.Forms.Label
    $description.Text = 'Generate readable Markdown for semantic-model tables, source connections, Power Query, native SQL, DAX, relationships and report pages.'
    $description.Dock = 'Fill'
    $description.TextAlign = 'MiddleLeft'
    $description.ForeColor = [System.Drawing.Color]::DimGray
    $contentGrid.Controls.Add($description,0,1)

    function New-SummaryLabel([string]$Name,[string]$Text) {
        $label = New-Object System.Windows.Forms.Label
        $label.Name = $Name
        $label.Text = $Text
        $label.Dock = 'Fill'
        $label.TextAlign = 'MiddleLeft'
        $label.Font = New-Object System.Drawing.Font('Segoe UI',10)
        $label.ForeColor = [System.Drawing.Color]::FromArgb(51,65,85)
        return $label
    }

    $modelSummary = New-SummaryLabel 'AnalyseModelSummary' 'Semantic Model: not scanned'
    $countSummary = New-SummaryLabel 'AnalyseCountSummary' 'Tables: -     Relationships: -     Pages: -'
    $outputSummary = New-SummaryLabel 'AnalyseOutputSummary' 'Output: <selected folder>\Analyse\Table | Relationship | Pages'
    $contentGrid.Controls.Add($modelSummary,0,2)
    $contentGrid.Controls.Add($countSummary,0,3)
    $contentGrid.Controls.Add($outputSummary,0,4)

    $details = New-Object System.Windows.Forms.TextBox
    $details.Name = 'AnalyseDetails'
    $details.Dock = 'Fill'
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = 'Vertical'
    $details.BackColor = [System.Drawing.Color]::FromArgb(248,250,252)
    $details.BorderStyle = 'FixedSingle'
    $details.Font = New-Object System.Drawing.Font('Consolas',9)
    $details.Text = "Generated structure:`r`n  Analyse\README.md`r`n  Analyse\Table\<Table>.md`r`n  Analyse\Relationship\Relationships.md`r`n  Analyse\Pages\README.md`r`n`r`nLong SQL, Power Query and DAX logic is written inside collapsed <details> blocks."
    $contentGrid.Controls.Add($details,0,5)

    $lastAutoOutput = ''
    $lastGeneratedFolder = ''

    $setDefaultOutput = {
        $newDefault = ''
        try { $newDefault = Get-PbiAnalyseDefaultOutputRoot -ProjectPath ([string]$projectText.Text) } catch { $newDefault = '' }
        if (-not [string]::IsNullOrWhiteSpace($newDefault)) {
            if ([string]::IsNullOrWhiteSpace($outputText.Text) -or $outputText.Text -eq $lastAutoOutput) {
                $outputText.Text = $newDefault
            }
            $lastAutoOutput = $newDefault
        }
    }.GetNewClosure()

    $scanModel = {
        try {
            if ([string]::IsNullOrWhiteSpace($projectText.Text)) { throw 'Select a PBIP project first.' }
            & $setDefaultOutput
            & $writeActivity 'Analyse: scanning semantic model...'
            $info = Get-PbiAnalyseProjectInfo -ProjectPath ([string]$projectText.Text)
            $modelSummary.Text = ('Semantic Model: ' + $info.SemanticModel.SemanticModelFolder)
            $countSummary.Text = ('Tables: ' + $info.TableFileCount + '     Relationships: ' + $info.RelationshipCount + '     Pages: ' + $info.PageCount)
            $details.Text = ('Detection: ' + $info.SemanticModel.DetectionMethod + [Environment]::NewLine +
                'TMDL Definition: ' + $info.SemanticModel.DefinitionFolder + [Environment]::NewLine +
                'Output Root: ' + $outputText.Text + [Environment]::NewLine + [Environment]::NewLine +
                'Ready to generate Markdown documentation.')
            & $writeActivity ('Analyse scan: tables=' + $info.TableFileCount + '; relationships=' + $info.RelationshipCount + '; pages=' + $info.PageCount)
        }
        catch { & $showError $_.Exception.Message }
    }.GetNewClosure()

    $generate = {
        try {
            if ([string]::IsNullOrWhiteSpace($projectText.Text)) { throw 'Select a PBIP project first.' }
            & $setDefaultOutput
            if ([string]::IsNullOrWhiteSpace($outputText.Text)) { throw 'Choose an output folder.' }
            & $writeActivity 'Analyse: generating Markdown documentation...'
            $result = Invoke-PbiAnalyseExport -ProjectPath ([string]$projectText.Text) -OutputRoot ([string]$outputText.Text)
            $lastGeneratedFolder = [string]$result.OutputFolder
            $openButton.Enabled = $true
            $modelSummary.Text = ('Semantic Model: ' + $result.SemanticModelFolder)
            $countSummary.Text = ('Tables: ' + $result.TableCount + '     Relationships: ' + $result.RelationshipCount + '     Pages: ' + $result.PageCount + '     Native SQL tables: ' + $result.NativeSqlTableCount)
            $outputSummary.Text = ('Output: ' + $result.OutputFolder)
            $sourceText = if (@($result.SourceCalls).Count -gt 0) { @($result.SourceCalls) -join ', ' } else { 'No connector call detected / calculated model' }
            $details.Text = ('Generated successfully.' + [Environment]::NewLine +
                'Sources: ' + $sourceText + [Environment]::NewLine +
                'Table docs: ' + (Join-Path $result.OutputFolder 'Table') + [Environment]::NewLine +
                'Relationships: ' + (Join-Path $result.OutputFolder 'Relationship\Relationships.md') + [Environment]::NewLine +
                'Pages: ' + (Join-Path $result.OutputFolder 'Pages\README.md'))
            foreach ($errorText in @($result.Errors)) { & $writeActivity ('Analyse warning: ' + $errorText) }
            & $writeActivity ('Analyse completed: ' + $result.OutputFolder)
        }
        catch { & $showError $_.Exception.Message }
    }.GetNewClosure()

    $folderButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select the folder where PBI Automate should create the Analyse folder.'
        if (Test-Path -LiteralPath $outputText.Text -PathType Container) { $dialog.SelectedPath = $outputText.Text }
        if ($dialog.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $outputText.Text = $dialog.SelectedPath
            $lastAutoOutput = ''
        }
        $dialog.Dispose()
    }.GetNewClosure())
    $scanButton.Add_Click({ & $scanModel }.GetNewClosure())
    $generateButton.Add_Click({ & $generate }.GetNewClosure())
    $openButton.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($lastGeneratedFolder) -or -not (Test-Path -LiteralPath $lastGeneratedFolder -PathType Container)) { throw 'Generate Analyse documentation first.' }
            Start-Process explorer.exe -ArgumentList ('"' + $lastGeneratedFolder + '"')
        }
        catch { & $showError $_.Exception.Message }
    }.GetNewClosure())
    $projectText.Add_TextChanged({ & $setDefaultOutput }.GetNewClosure())

    $hideAnalyse = {
        $analyseOptions.Visible = $false
        $analyseContent.Visible = $false
    }.GetNewClosure()

    foreach ($serviceId in @('alignment','formatting','theme','visual-copy-paste')) {
        $button = Find-AnalyseControl -Parent $Form -Name ('Service_' + $serviceId)
        if ($null -ne $button) { $button.Add_Click({ & $hideAnalyse }.GetNewClosure()) }
    }

    $analyseButton.Add_Click({
        if ($null -ne $alignmentOptions) { $alignmentOptions.Visible = $false }
        if ($null -ne $alignmentContent) { $alignmentContent.Visible = $false }
        if ($null -ne $comingOptions) { $comingOptions.Visible = $false }
        if ($null -ne $comingContent) { $comingContent.Visible = $false }
        $analyseOptions.Visible = $true
        $analyseContent.Visible = $true
        $analyseOptions.BringToFront()
        $analyseContent.BringToFront()
        & $setDefaultOutput

        # MainForm's generic fallback currently logs Ready services other than Alignment as Coming Soon.
        # Remove that one misleading line until Analyse is folded into the shared shell natively.
        if ($null -ne $console -and -not [string]::IsNullOrWhiteSpace($console.Text)) {
            $lines = @($console.Lines | Where-Object { $_ -notmatch 'Service selected: Analyse - Coming Soon$' })
            $console.Lines = $lines
        }
        & $writeActivity 'Service selected: Analyse'
    }.GetNewClosure())

    & $setDefaultOutput
    return $analyseContent
}

Export-ModuleMember -Function Add-PbiAnalyseUi
