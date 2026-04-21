Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Connect-PnPSPOWorkaround.ps1')

function Resolve-SPOAdminUrl {
    [CmdletBinding()]
    param(
        [uri]$AdminUrl,
        [uri]$LibraryUrl
    )

    if ($AdminUrl) {
        return $AdminUrl
    }

    try {
        $existingConnection = Get-PnPConnection -ErrorAction Stop
        if ($existingConnection.Url -match '-admin\.sharepoint\.(com|us|de|cn)$') {
            return [uri]$existingConnection.Url
        }
    }
    catch {
    }

    if (-not $LibraryUrl) {
        throw 'AdminUrl is required when it cannot be derived from LibraryUrl or the current PnP connection.'
    }

    $sharePointHost = $LibraryUrl.Host
    if ($sharePointHost -match '^(?<tenant>[^.]+)\.sharepoint\.(?<suffix>com|us|de|cn)$') {
        return [uri]"$($LibraryUrl.Scheme)://$($Matches.tenant)-admin.sharepoint.$($Matches.suffix)"
    }

    if ($sharePointHost -match '^(?<tenant>.+)-admin\.sharepoint\.(?<suffix>com|us|de|cn)$') {
        return $LibraryUrl
    }

    throw "Unable to derive admin URL from '$($LibraryUrl.AbsoluteUri)'. Supply -AdminUrl explicitly."
}

function Get-SPOOrgAssetsTenantContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$AdminUrl
    )

    Connect-PnPSPOWorkaround -Url $AdminUrl
    $ctx = Get-PnPContext

    return [pscustomobject]@{
        Context = $ctx
        Tenant  = [Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($ctx)
    }
}

function Get-TenantInstanceMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $Target.GetType().GetMethod($Name, [System.Reflection.BindingFlags]'Public,Instance')
}

function Get-OrgAssetsLibrarySiteUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$LibraryUrl
    )

    $segments = $LibraryUrl.AbsolutePath.Trim('/') -split '/'
    if ($segments.Count -ge 2 -and $segments[0] -in @('sites', 'teams')) {
        return [uri]"$($LibraryUrl.Scheme)://$($LibraryUrl.Host)/$($segments[0])/$($segments[1])"
    }

    return [uri]"$($LibraryUrl.Scheme)://$($LibraryUrl.Host)"
}

function Get-OrgAssetsTargetList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$LibraryUrl
    )

    $siteUrl = Get-OrgAssetsLibrarySiteUrl -LibraryUrl $LibraryUrl
    Connect-PnPSPOWorkaround -Url $siteUrl

    $targetPath = $LibraryUrl.AbsolutePath.TrimEnd('/')
    $lists = Get-PnPList -Includes RootFolder
    foreach ($list in $lists) {
        Get-PnPProperty -ClientObject $list -Property RootFolder | Out-Null
        if ($list.RootFolder.ServerRelativeUrl.TrimEnd('/') -eq $targetPath) {
            return [pscustomobject]@{
                SiteUrl = $siteUrl
                List    = $list
            }
        }
    }

    throw "Could not resolve a SharePoint list from library URL '$($LibraryUrl.AbsoluteUri)'."
}

function Get-DefaultOrgAssetsThumbnailUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$SiteUrl
    )

    Connect-PnPSPOWorkaround -Url $SiteUrl
    $web = Get-PnPWeb -Includes SiteLogoUrl, Url

    if ([string]::IsNullOrWhiteSpace($web.SiteLogoUrl)) {
        throw "ThumbnailUrl was not provided and site '$($web.Url)' has no SiteLogoUrl. Supply -ThumbnailUrl explicitly."
    }

    if ($web.SiteLogoUrl -match '^https?://') {
        return $web.SiteLogoUrl
    }

    return "$($SiteUrl.Scheme)://$($SiteUrl.Host)$($web.SiteLogoUrl)"
}

function Ensure-OrgAssetsLibraryReadableByEveryoneExceptExternalUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$LibraryUrl,

        [string]$EnvPath = (Join-Path (Get-Location) '.env')
    )

    $resolved = Get-OrgAssetsTargetList -LibraryUrl $LibraryUrl
    $list = Get-PnPList -Identity $resolved.List.Id -Includes HasUniqueRoleAssignments
    if (-not $list.HasUniqueRoleAssignments) {
        Set-PnPList -Identity $list.Id -BreakRoleInheritance -CopyRoleAssignments | Out-Null
    }

    $envMap = Get-LocalEnvMap -Path $EnvPath
    $principal = "c:0-.f|rolemanager|spo-grid-all-users/$($envMap.TenantId)"
    Set-PnPListPermission -Identity $list.Id -User $principal -AddRole 'Read' -ErrorAction SilentlyContinue | Out-Null

    return $resolved
}

function Get-SPOOrgAssetsLibraryMacWorkaround {
    [CmdletBinding()]
    param(
        [uri]$AdminUrl
    )

    $resolvedAdminUrl = Resolve-SPOAdminUrl -AdminUrl $AdminUrl
    $tenantContext = Get-SPOOrgAssetsTenantContext -AdminUrl $resolvedAdminUrl
    $result = $tenantContext.Tenant.GetOrgAssets()
    $tenantContext.Context.ExecuteQuery()

    foreach ($library in $result.Value.OrgAssetsLibraries) {
        [pscustomobject]@{
            DisplayName  = $library.DisplayName
            LibraryUrl   = $library.LibraryUrl.DecodedUrl
            ListId       = $library.ListId
            OrgAssetType = $library.OrgAssetType.ToString()
            ThumbnailUrl = $library.ThumbnailUrl.DecodedUrl
            FileType     = $library.FileType
            UniqueId     = $library.UniqueId
        }
    }
}

function Add-SPOOrgAssetsLibraryMacWorkaround {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$LibraryUrl,

        [string]$ThumbnailUrl,

        [ValidateSet('ImageDocumentLibrary', 'OfficeTemplateLibrary', 'OfficeFontLibrary', 'BrandKitLibrary')]
        [string]$OrgAssetType = 'ImageDocumentLibrary',

        [ValidateSet('Public', 'Private')]
        [string]$CdnType = 'Public',

        [switch]$NoDefaultOrigins,

        [bool]$CopilotSearchable = $false,

        [uri]$AdminUrl,

        [string]$EnvPath = (Join-Path (Get-Location) '.env')
    )

    $resolvedAdminUrl = Resolve-SPOAdminUrl -AdminUrl $AdminUrl -LibraryUrl $LibraryUrl
    $resolvedList = Ensure-OrgAssetsLibraryReadableByEveryoneExceptExternalUsers -LibraryUrl $LibraryUrl -EnvPath $EnvPath

    if (-not $ThumbnailUrl) {
        $ThumbnailUrl = Get-DefaultOrgAssetsThumbnailUrl -SiteUrl $resolvedList.SiteUrl
    }

    if ($PSCmdlet.ShouldProcess($LibraryUrl.AbsoluteUri, 'Register organization assets library')) {
        $tenantContext = Get-SPOOrgAssetsTenantContext -AdminUrl $resolvedAdminUrl
        $config = [Microsoft.SharePoint.BrandCenter.OrgAssetsLibraryConfigParam]::new()
        $config.IsCopilotSearchable = $CopilotSearchable
        $config.IsCopilotSearchablePresent = $true

        $tenantContext.Tenant.AddToOrgAssetsLibWithConfig(
            [enum]::Parse([Microsoft.Online.SharePoint.TenantAdministration.SPOTenantCdnType], $CdnType),
            $LibraryUrl.AbsoluteUri,
            $ThumbnailUrl,
            [enum]::Parse([Microsoft.SharePoint.Administration.OrgAssetType], $OrgAssetType),
            (-not $NoDefaultOrigins.IsPresent),
            $config
        )
        $tenantContext.Context.ExecuteQuery()
    }

    Get-SPOOrgAssetsLibraryMacWorkaround -AdminUrl $resolvedAdminUrl |
        Where-Object { $_.LibraryUrl -eq $LibraryUrl.AbsolutePath.TrimStart('/') -or $_.LibraryUrl -eq $LibraryUrl.AbsoluteUri }
}

function Remove-SPOOrgAssetsLibraryMacWorkaround {
    [CmdletBinding(DefaultParameterSetName = 'ByLibraryUrl', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByLibraryUrl')]
        [uri]$LibraryUrl,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByListId')]
        [guid]$ListId,

        [Parameter(Mandatory = $true, ParameterSetName = 'BrandCenter')]
        [switch]$BrandCenter,

        [uri]$AdminUrl,

        [string]$EnvPath = (Join-Path (Get-Location) '.env'),

        [string]$CertificatePath = (Join-Path (Get-Location) 'app.pfx')
    )

    $resolvedAdminUrl = Resolve-SPOAdminUrl -AdminUrl $AdminUrl -LibraryUrl $LibraryUrl

    switch ($PSCmdlet.ParameterSetName) {
        'BrandCenter' {
            if ($PSCmdlet.ShouldProcess($resolvedAdminUrl.AbsoluteUri, 'Deactivate Brand Center features')) {
                $helperPath = Join-Path $PSScriptRoot 'Invoke-SPOBrandCenterDeactivation.ps1'
                $output = & pwsh -NoLogo -NoProfile -File $helperPath `
                    -AdminUrl $resolvedAdminUrl `
                    -EnvPath $EnvPath `
                    -CertificatePath $CertificatePath

                if ($LASTEXITCODE -ne 0) {
                    throw "Brand Center deactivation helper failed with exit code $LASTEXITCODE."
                }

                return ($output | ConvertFrom-Json)
            }
            return
        }
        'ByLibraryUrl' {
            $tenantContext = Get-SPOOrgAssetsTenantContext -AdminUrl $resolvedAdminUrl
            if ($PSCmdlet.ShouldProcess($LibraryUrl.AbsoluteUri, 'Remove organization assets library')) {
                $tenantContext.Tenant.RemoveFromOrgAssets($LibraryUrl.AbsoluteUri, [guid]::Empty)
                $tenantContext.Context.ExecuteQuery()
            }
        }
        'ByListId' {
            $tenantContext = Get-SPOOrgAssetsTenantContext -AdminUrl $resolvedAdminUrl
            if ($PSCmdlet.ShouldProcess($ListId.Guid, 'Remove organization assets library')) {
                $tenantContext.Tenant.RemoveFromOrgAssets([string]::Empty, $ListId)
                $tenantContext.Context.ExecuteQuery()
            }
        }
    }
}
