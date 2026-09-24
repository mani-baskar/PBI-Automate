Set-StrictMode -Version 2.0

function Get-PBIAutomateDataRoot {
    [CmdletBinding()]
    param()

    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
    $root = Join-Path $base 'PBIAutomate'
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    return $root
}

function Write-PBIAutomateLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    $root = Get-PBIAutomateDataRoot
    $logDir = Join-Path $root 'Logs'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $path = Join-Path $logDir ('PBIAutomate-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    return $path
}

Export-ModuleMember -Function Get-PBIAutomateDataRoot, Write-PBIAutomateLog
