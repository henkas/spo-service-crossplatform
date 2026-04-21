function Assert-SupportedRuntime {
    [CmdletBinding()]
    param(
        [version]$Version = $PSVersionTable.PSVersion
    )

    if ($Version -lt [version]'7.6.0') {
        throw "SPOService.CrossPlatform requires PowerShell 7.6 or newer. PowerShell $Version is not supported."
    }
}
