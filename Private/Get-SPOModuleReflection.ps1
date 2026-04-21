function Get-SPOModuleReflection {
    [CmdletBinding()]
    param()

    Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue

    $moduleBase = (Get-Module Microsoft.Online.SharePoint.PowerShell | Select-Object -First 1).ModuleBase
    Add-Type -Path (Join-Path $moduleBase 'microsoft.identity.client.dll') -ErrorAction SilentlyContinue

    $dll = Join-Path $moduleBase 'Microsoft.Online.SharePoint.PowerShell.dll'
    $asm = [Reflection.Assembly]::LoadFrom($dll)

    $types = [ordered]@{
        CmdLetContext    = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.CmdLetContext')
        OAuthSession     = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.OAuthSession')
        SPOService       = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.SPOService')
        SPOServiceHelper = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.SPOServiceHelper')
    }

    $missing = $types.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key }
    if ($missing) {
        throw "Installed Microsoft.Online.SharePoint.PowerShell module is missing required type(s): $($missing -join ', '). Upgrade the SPO module."
    }

    [pscustomobject]@{
        ModuleBase       = $moduleBase
        Assembly         = $asm
        CmdLetContext    = $types.CmdLetContext
        OAuthSession     = $types.OAuthSession
        SPOService       = $types.SPOService
        SPOServiceHelper = $types.SPOServiceHelper
    }
}
