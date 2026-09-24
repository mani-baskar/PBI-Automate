Set-StrictMode -Version 2.0

function Get-PBIAutomateConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $defaults = [pscustomobject]@{
        productName = 'PBI Automate'
        version = '0.1.0-dev'
        layout = [pscustomobject]@{
            mode = 'Smart Align'
            margin = 5
            gap = 5
            toleranceMode = 'Auto'
            minimumTolerance = 3
            maximumTolerance = 24
        }
        safety = [pscustomobject]@{
            backupBeforeApply = $true
            validateBeforeApply = $true
            validateAfterApply = $true
        }
    }

    $path = Join-Path $RootPath 'config\defaults.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $defaults
    }

    try {
        $loaded = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw ('Unable to read configuration "{0}": {1}' -f $path,$_.Exception.Message)
    }

    if ($null -eq $loaded.layout) { $loaded | Add-Member -MemberType NoteProperty -Name layout -Value $defaults.layout }
    if ($null -eq $loaded.safety) { $loaded | Add-Member -MemberType NoteProperty -Name safety -Value $defaults.safety }

    foreach ($name in @('mode','margin','gap','toleranceMode','minimumTolerance','maximumTolerance')) {
        if (-not ($loaded.layout.PSObject.Properties.Name -contains $name)) {
            $loaded.layout | Add-Member -MemberType NoteProperty -Name $name -Value $defaults.layout.$name
        }
    }
    foreach ($name in @('backupBeforeApply','validateBeforeApply','validateAfterApply')) {
        if (-not ($loaded.safety.PSObject.Properties.Name -contains $name)) {
            $loaded.safety | Add-Member -MemberType NoteProperty -Name $name -Value $defaults.safety.$name
        }
    }
    if (-not ($loaded.PSObject.Properties.Name -contains 'productName')) { $loaded | Add-Member -MemberType NoteProperty -Name productName -Value $defaults.productName }
    if (-not ($loaded.PSObject.Properties.Name -contains 'version')) { $loaded | Add-Member -MemberType NoteProperty -Name version -Value $defaults.version }

    return $loaded
}

Export-ModuleMember -Function Get-PBIAutomateConfig
