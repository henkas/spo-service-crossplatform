function Assert-SPOAdminSite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Reflection,

        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [uri]$Url
    )

    $isAdminMethod = $Reflection.SPOServiceHelper.GetMethod(
        'IsTenantAdminSite',
        [Reflection.BindingFlags]'Public,NonPublic,Static')
    if (-not $isAdminMethod) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.SPOServiceHelper.IsTenantAdminSite is not present in the installed SPO module. Upgrade 'Microsoft.Online.SharePoint.PowerShell' or file an issue."
    }

    try {
        $isAdmin = $isAdminMethod.Invoke($null, @($Context))
    } catch {
        $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        throw "Authenticated against '$($Url.AbsoluteUri)', but SharePoint did not accept it as a tenant admin URL. Use the admin site, e.g. https://<tenant>-admin.sharepoint.com. Underlying error: $inner"
    }

    if (-not $isAdmin) {
        throw "'$($Url.AbsoluteUri)' is not a SharePoint tenant admin URL. Use the admin site, e.g. https://<tenant>-admin.sharepoint.com."
    }
}
