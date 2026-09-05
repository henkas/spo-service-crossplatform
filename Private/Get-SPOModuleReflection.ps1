function Get-SPOModuleReflection {
    <#
    .SYNOPSIS
        Loads a supported Microsoft.Online.SharePoint.PowerShell and reflects
        out the internal types the connect path needs.
    .DESCRIPTION
        Version selection is deterministic (see Select-SPOVendorModule): reuse
        an already-loaded version if it meets the manifest floor, otherwise
        import the highest installed version that does. The result carries
        the loaded version, path and environment facts so every later error
        can identify the combination without any tenant data.
    #>
    [CmdletBinding()]
    param()

    $name = 'Microsoft.Online.SharePoint.PowerShell'
    $minimum = Get-SPOVendorMinimumVersion
    $choice = Select-SPOVendorModule `
        -Loaded @(Get-Module $name) `
        -Available @(Get-Module -ListAvailable $name) `
        -MinimumVersion $minimum

    if ($choice.Action -eq 'Import') {
        Import-Module $name -RequiredVersion $choice.Version -ErrorAction Stop -WarningAction SilentlyContinue
    }

    $module = @(Get-Module $name | Where-Object { $_.Version -eq $choice.Version })
    if ($module.Count -ne 1) {
        throw "Expected exactly one loaded $name $($choice.Version) after import; found $($module.Count)."
    }
    $moduleBase = $module[0].ModuleBase

    $environment = [pscustomobject]@{
        PowerShell   = $PSVersionTable.PSVersion.ToString()
        Runtime      = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        OS           = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        Architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }

    Add-Type -Path (Join-Path $moduleBase 'microsoft.identity.client.dll') -ErrorAction SilentlyContinue

    $dll = Join-Path $moduleBase 'Microsoft.Online.SharePoint.PowerShell.dll'
    $asm = [Reflection.Assembly]::LoadFrom($dll)

    $types = [ordered]@{
        CmdLetContext    = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.CmdLetContext')
        OAuthSession     = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.OAuthSession')
        SPOService       = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.SPOService')
        SPOServiceHelper = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.SPOServiceHelper')
    }

    $missing = @($types.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
    if ($missing.Count) {
        throw "Loaded $name $($choice.Version) at $moduleBase is missing required internal type(s): $($missing -join ', '). Environment: PowerShell $($environment.PowerShell); $($environment.Runtime); $($environment.OS); $($environment.Architecture). Please report this at https://github.com/henkas/spo-service-crossplatform/issues with the vendor version above."
    }

    [pscustomobject]@{
        Version          = $choice.Version
        ModuleBase       = $moduleBase
        MinimumVersion   = $minimum
        Environment      = $environment
        Assembly         = $asm
        CmdLetContext    = $types.CmdLetContext
        OAuthSession     = $types.OAuthSession
        SPOService       = $types.SPOService
        SPOServiceHelper = $types.SPOServiceHelper
    }
}
