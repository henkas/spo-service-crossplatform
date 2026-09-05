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
    # just to tear down state. Only one vendor version can be loaded per
    # session, but clear the static on every loaded copy rather than picking
    # one by list order, and stay idempotent when nothing is loaded.
    foreach ($module in @(Get-Module Microsoft.Online.SharePoint.PowerShell)) {
        $dll = Join-Path $module.ModuleBase 'Microsoft.Online.SharePoint.PowerShell.dll'
        if (-not (Test-Path -LiteralPath $dll)) { continue }
        $asm = [Reflection.Assembly]::LoadFrom($dll)
        $svcType = $asm.GetType('Microsoft.Online.SharePoint.PowerShell.SPOService')
        if (-not $svcType) { continue }
        $currentServiceProp = $svcType.GetProperty('CurrentService', [Reflection.BindingFlags]'Public,NonPublic,Static')
        if ($currentServiceProp -and $currentServiceProp.GetSetMethod($true)) {
            $currentServiceProp.SetValue($null, $null)
        }
    }
}
