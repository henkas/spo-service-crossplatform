function Test-SPOAdminUrlFormat {
    <#
    .SYNOPSIS
        Syntactic check that a URL is a canonical commercial SharePoint Online
        tenant admin URL: https://<tenant>-admin.sharepoint.com[/]
    .DESCRIPTION
        This release supports the commercial cloud only, because the sign-in
        authority is hard-coded to login.microsoftonline.com. Sovereign clouds
        (sharepoint.us, .de, .cn) need an authority mapping and are rejected
        until that exists. Everything except scheme, canonical host, default
        port and an empty path is rejected so a URL cannot smuggle a foreign
        host, credentials or a path past the pre-authentication boundary.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$Url
    )

    if (-not $Url.IsAbsoluteUri) { return $false }
    if ($Url.Scheme -ne 'https') { return $false }
    if (-not $Url.IsDefaultPort) { return $false }
    if ($Url.UserInfo) { return $false }
    if ($Url.Query -or $Url.Fragment) { return $false }
    if ($Url.AbsolutePath -ne '/') { return $false }

    # Tenant label: ASCII letters/digits with single internal hyphens, so the
    # host is exactly <tenant>-admin.sharepoint.com. The anchored suffix leaves
    # no room for extra labels, a trailing dot or a look-alike domain. Uri
    # already lower-cases and IDN-normalises Host, so any non-ASCII or xn--
    # label fails the character class.
    $tenant = '[a-z0-9]+(?:-[a-z0-9]+)*'
    return $Url.Host -cmatch "^(?!xn--)${tenant}-admin\.sharepoint\.com$"
}
