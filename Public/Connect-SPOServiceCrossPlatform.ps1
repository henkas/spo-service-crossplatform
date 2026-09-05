function Connect-SPOServiceCrossPlatform {
<#
.SYNOPSIS
    Connects to SharePoint Online on macOS / Linux in place of the broken
    native Connect-SPOService. Also exported as the alias Connect-SPOService.

.DESCRIPTION
    Works around two distinct defects in Microsoft.Online.SharePoint.PowerShell
    that stop it from running under PowerShell 7 / .NET Core outside Windows:

        1. SPOServiceHelper.InstantiateSPOService unconditionally reads
           Microsoft.Win32.Registry.CurrentUser / LocalMachine, both null on
           non-Windows, producing "Object reference not set to an instance of
           an object".

        2. The module's 16.0.0.0 Microsoft.SharePoint.Client.Runtime uses
           HttpWebRequestExecutor, which on .NET Core does not flush request
           bodies, so every CSOM POST goes out with Content-Length: 0 and the
           server responds "Invalid request." / 400 Bad Request.

    This cmdlet bypasses InstantiateSPOService and installs a custom
    HttpClient-based WebRequestExecutorFactory on the CmdLetContext, then
    sets SPOService.CurrentService. After it returns, the native cmdlets
    (Get-SPOTenant, Get-SPOSite, Get-SPOOrgAssetsLibrary, etc.) work against
    the repaired pipeline transparently.

    Authentication uses the native reflected OAuthSession model from
    Microsoft.Online.SharePoint.PowerShell. On Unix, the module keeps the
    official session shape and only replaces the broken CSOM transport with
    the HttpClient-based executor shim.

.PARAMETER Url
    The SharePoint tenant admin URL, exactly https://<tenant>-admin.sharepoint.com
    (e.g. https://contoso-admin.sharepoint.com). This release supports the
    commercial cloud only; sovereign-cloud domains (sharepoint.us, .de, .cn),
    ports, paths, query strings and credentials in the URL are rejected before
    the vendor module loads or any sign-in starts.

.PARAMETER ClientId
    App registration (service principal) client ID.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER CertificatePath
    Path to a PFX file for the app registration.

.PARAMETER CertificatePassword
    SecureString for the PFX, if it is password-protected.

.PARAMETER Certificate
    Pre-loaded X509Certificate2 object, as an alternative to CertificatePath.

.PARAMETER UseSystemBrowser
    Starts native OAuthSession interactive auth using the system browser.
    This is the only interactive mode supported on Unix.

.PARAMETER UseEnvFile
    Opt in to reading ClientId, TenantId, password (PFX password), and
    optionally CertificatePath from a .env file instead of taking them on the
    command line.

.PARAMETER EnvPath
    Path to the .env file used when -UseEnvFile is set. Defaults to ./.env.

.PARAMETER ClientTag
    Optional client tag forwarded to CmdLetContext (appears in SharePoint ULS
    logs). Defaults to empty.

.EXAMPLE
    Connect-SPOServiceCrossPlatform -Url https://contoso-admin.sharepoint.com `
        -ClientId <guid> -TenantId <guid> `
        -CertificatePath ./app.pfx -CertificatePassword (Read-Host -AsSecureString)

    Explicit certificate-based auth.

.EXAMPLE
    Connect-SPOService -Url https://contoso-admin.sharepoint.com -UseSystemBrowser

    Launches the native system-browser flow on PowerShell 7.6+.
#>
    [CmdletBinding(DefaultParameterSetName = 'CertificatePath')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The .env file is already plaintext on disk; ConvertTo-SecureString here is the mandated bridge to X509Certificate2, not a new plaintext surface.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'UseEnvFile',
        Justification = 'Switch parameter selects the EnvFile ParameterSetName; runtime routing is via $PSCmdlet.ParameterSetName.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'UseSystemBrowser',
        Justification = 'Switch parameter selects the SystemBrowser ParameterSetName; runtime routing is via $PSCmdlet.ParameterSetName.')]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$Url,

        [Parameter(Mandatory = $true, ParameterSetName = 'CertificatePath')]
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateObject')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'CertificatePath')]
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateObject')]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'CertificatePath')]
        [string]$CertificatePath,

        [Parameter(ParameterSetName = 'CertificatePath')]
        [securestring]$CertificatePassword,

        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateObject')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory = $true, ParameterSetName = 'EnvFile')]
        [switch]$UseEnvFile,

        [Parameter(ParameterSetName = 'EnvFile')]
        [string]$EnvPath = (Join-Path (Get-Location) '.env'),

        [Parameter(Mandatory = $true, ParameterSetName = 'SystemBrowser')]
        [switch]$UseSystemBrowser,

        [string]$ClientTag = ''
    )

    Assert-SupportedRuntime

    # Validate the URL before loading the vendor module or touching any global
    # state, so a malformed or spoofed host never reaches authentication.
    if (-not (Test-SPOAdminUrlFormat -Url $Url)) {
        throw "'$($Url.OriginalString)' is not a supported SharePoint tenant admin URL. This release supports the commercial cloud only; use exactly https://<tenant>-admin.sharepoint.com (no port, path, query, credentials or sovereign-cloud domain)."
    }

    $reflection = Get-SPOModuleReflection
    Assert-NativeShim

    $context = New-SPOCmdletContext -Reflection $reflection -Url $Url -HostInstance $Host -ClientTag $ClientTag

    $authority = 'https://login.microsoftonline.com/organizations'

    switch ($PSCmdlet.ParameterSetName) {
        'CertificatePath' {
            $cert = if ($CertificatePassword) {
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath, $CertificatePassword)
            } else {
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
            }

            $oauthSession = New-SPOCertificateOAuthSession `
                -Reflection $reflection `
                -Settings @{
                    Authority   = $authority
                    Certificate = $cert
                    TenantId    = $TenantId
                    ClientId    = $ClientId
                    Url         = $Url
                }
        }
        'CertificateObject' {
            $oauthSession = New-SPOCertificateOAuthSession `
                -Reflection $reflection `
                -Settings @{
                    Authority   = $authority
                    Certificate = $Certificate
                    TenantId    = $TenantId
                    ClientId    = $ClientId
                    Url         = $Url
                }
        }
        'EnvFile' {
            $envMap = Get-LocalEnvMap -Path $EnvPath
            foreach ($required in 'ClientId', 'TenantId', 'password') {
                if (-not $envMap.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($envMap[$required])) {
                    throw "Missing '$required' in $EnvPath"
                }
            }
            $ClientId = $envMap.ClientId
            $TenantId = $envMap.TenantId
            $pfxPath = if ($envMap.ContainsKey('CertificatePath') -and $envMap.CertificatePath) {
                $envMap.CertificatePath
            } else {
                Join-Path (Split-Path -Parent $EnvPath) 'app.pfx'
            }
            if (-not (Test-Path $pfxPath)) {
                throw "Certificate file not found: $pfxPath"
            }
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath, (ConvertTo-SecureString $envMap.password -AsPlainText -Force))
            $oauthSession = New-SPOCertificateOAuthSession `
                -Reflection $reflection `
                -Settings @{
                    Authority   = $authority
                    Certificate = $cert
                    TenantId    = $TenantId
                    ClientId    = $ClientId
                    Url         = $Url
                }
        }
        'SystemBrowser' {
            $oauthSession = New-SPOSystemBrowserOAuthSession `
                -Reflection $reflection `
                -Authority $authority `
                -Url $Url
        }
    }

    $oauthSessionProp = $reflection.CmdLetContext.GetProperty(
        'OAuthSession',
        [Reflection.BindingFlags]'Public,NonPublic,Instance')
    if (-not $oauthSessionProp) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.CmdLetContext.OAuthSession is not present in the installed SPO module."
    }
    $oauthSessionProp.SetValue($context, $oauthSession)

    Assert-SPOAdminSite -Reflection $reflection -Context $context -Url $Url

    $svcCtor = $reflection.SPOService.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @($reflection.CmdLetContext),
        $null)
    $service = $svcCtor.Invoke(@($context))

    $currentServiceProp = $reflection.SPOService.GetProperty('CurrentService', [Reflection.BindingFlags]'Public,NonPublic,Static')
    $currentServiceProp.SetValue($null, $service)
}
