function Test-SPOAdminUrlFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$Url
    )

    if ($Url.Scheme -ne 'https') {
        return $false
    }

    if ($Url.Query -or $Url.Fragment) {
        return $false
    }

    if ($Url.AbsolutePath.Trim('/')) {
        return $false
    }

    return $Url.Host -match '^[A-Za-z0-9][A-Za-z0-9-]*-admin\.sharepoint\.[A-Za-z0-9.-]+$'
}
