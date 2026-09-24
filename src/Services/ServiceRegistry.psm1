Set-StrictMode -Version 2.0

function Get-PBIAutomateServices {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{
            Id = 'alignment'
            Name = 'Alignment Correction'
            Status = 'Ready'
            Description = 'Analyze, align, resize, validate and safely apply PBIR visual layout corrections.'
        },
        [pscustomobject]@{
            Id = 'formatting'
            Name = 'Change Format'
            Status = 'Coming Soon'
            Description = 'Bulk visual formatting and style corrections.'
        },
        [pscustomobject]@{
            Id = 'theme'
            Name = 'Theme Creation'
            Status = 'Coming Soon'
            Description = 'Build and apply reusable report themes.'
        },
        [pscustomobject]@{
            Id = 'visual-copy-paste'
            Name = 'Visual Copy Paste'
            Status = 'Coming Soon'
            Description = 'Copy visuals and formatting safely between PBIP pages.'
        }
    )
}

Export-ModuleMember -Function Get-PBIAutomateServices
