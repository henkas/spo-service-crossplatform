function Select-SPOVendorModule {
    <#
    .SYNOPSIS
        Decides which Microsoft.Online.SharePoint.PowerShell version to use.
    .DESCRIPTION
        Pure policy over the lists of loaded and installed vendor modules, so
        the rules can be unit tested without the vendor module present:

        - A version already loaded in the session must be reused. .NET will not
          load a second copy of the same assembly name, so it cannot be swapped
          for a newer one; if it is below the minimum, the only fix is a new
          session.
        - Otherwise import the highest installed version at or above the
          minimum. Never rely on directory or list order.
        - Fail with an actionable message when nothing suitable exists.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [psobject[]]$Loaded = @(),

        [AllowEmptyCollection()]
        [psobject[]]$Available = @(),

        [Parameter(Mandatory = $true)]
        [version]$MinimumVersion
    )

    $name = 'Microsoft.Online.SharePoint.PowerShell'

    if ($Loaded.Count -gt 1) {
        $versions = ($Loaded | ForEach-Object { [version]$_.Version } | Sort-Object) -join ', '
        throw "$name has more than one version loaded in this session ($versions), so SPOService.CrossPlatform cannot tell which assembly the native cmdlets will use. Start a new pwsh session and import one version only."
    }

    if ($Loaded.Count -eq 1) {
        $module = $Loaded[0]
        $version = [version]$module.Version
        if ($version -lt $MinimumVersion) {
            throw "$name $version is already loaded in this session (from $($module.ModuleBase)) and is below the minimum supported version $MinimumVersion. A loaded module assembly cannot be replaced, so start a new pwsh session; run 'Update-Module $name' first if no newer version is installed."
        }
        return [pscustomobject]@{ Action = 'UseLoaded'; Version = $version; ModuleBase = $module.ModuleBase }
    }

    if ($Available.Count -eq 0) {
        throw "$name is not installed. Install it with 'Install-Module $name -Scope CurrentUser' (minimum version $MinimumVersion)."
    }

    $supported = @($Available |
        Where-Object { [version]$_.Version -ge $MinimumVersion } |
        Sort-Object -Property @{ Expression = { [version]$_.Version } } -Descending)
    if ($supported.Count -eq 0) {
        $versions = ($Available | ForEach-Object { [version]$_.Version } | Sort-Object -Descending) -join ', '
        throw "Installed $name version(s) $versions are below the minimum supported version $MinimumVersion. Run 'Update-Module $name' or 'Install-Module $name -Scope CurrentUser -Force'."
    }

    $pick = $supported[0]
    [pscustomobject]@{ Action = 'Import'; Version = [version]$pick.Version; ModuleBase = $pick.ModuleBase }
}
