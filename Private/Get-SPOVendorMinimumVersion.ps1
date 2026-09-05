function Get-SPOVendorMinimumVersion {
    <#
    .SYNOPSIS
        Returns the minimum supported Microsoft.Online.SharePoint.PowerShell version.
    .DESCRIPTION
        The module manifest's RequiredModules entry is the single source of
        truth; PSGallery enforces it at install time and this helper enforces
        the same floor at runtime against the module actually loaded.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param()

    $manifest = Join-Path $PSScriptRoot '../SPOService.CrossPlatform.psd1'
    $data = Import-PowerShellDataFile -LiteralPath $manifest
    $entries = @(@($data.RequiredModules) | Where-Object {
        $_ -is [System.Collections.IDictionary] -and $_.ModuleName -eq 'Microsoft.Online.SharePoint.PowerShell'
    })
    if ($entries.Count -ne 1) {
        throw "Expected exactly one Microsoft.Online.SharePoint.PowerShell entry in RequiredModules of '$manifest'; found $($entries.Count)."
    }
    [version]$entries[0].ModuleVersion
}
