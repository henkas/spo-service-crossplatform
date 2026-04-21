function Disconnect-SPOServiceCrossPlatform {
<#
.SYNOPSIS
    Clears the SPOService.CurrentService established by Connect-SPOServiceCrossPlatform.
    Also exported as the alias Disconnect-SPOService.

.DESCRIPTION
    Undoes the state change made by Connect-SPOServiceCrossPlatform. After this
    runs, native SPO cmdlets will fail until another Connect-SPOServiceCrossPlatform
    call.
#>
    [CmdletBinding()]
    param()

    # Disconnect only needs to nullify a static property on SPOService;
    # avoid importing Microsoft.Online.SharePoint.PowerShell or loading MSAL
    # just to tear down state.
    $module = Get-Module Microsoft.Online.SharePoint.PowerShell | Select-Object -First 1
    if (-not $module) {
        $script:TokenProvider = $null
        return
    }

    $dll = Join-Path $module.ModuleBase 'Microsoft.Online.SharePoint.PowerShell.dll'
    $asm = [Reflection.Assembly]::LoadFrom($dll)
    $svcType = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.SPOService')
    $currentServiceProp = $svcType.GetProperty('CurrentService', [Reflection.BindingFlags]'Public,NonPublic,Static')
    $currentServiceProp.SetValue($null, $null)
    $script:TokenProvider = $null
}
