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

    Authentication uses MSAL's ConfidentialClientApplication with an app
    registration certificate. The token provider is hooked onto
    ExecutingWebRequest so MSAL's own cache handles expiry and refresh.

.PARAMETER Url
    The SharePoint admin URL, e.g. https://tenant-admin.sharepoint.com.

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
    Connect-SPOService -Url https://contoso-admin.sharepoint.com -UseEnvFile `
        -ClientId <guid> -TenantId <guid> `
        -CertificatePath ./app.pfx -CertificatePassword (Read-Host -AsSecureString)

    Same as above, using the drop-in alias Connect-SPOService (from this
    module; shadows the broken native cmdlet for the same session).
#>
    [CmdletBinding(DefaultParameterSetName = 'CertificatePath')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The .env file is already plaintext on disk; ConvertTo-SecureString here is the mandated bridge to X509Certificate2, not a new plaintext surface.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'UseEnvFile',
        Justification = 'Switch parameter selects the EnvFile ParameterSetName; runtime routing is via $PSCmdlet.ParameterSetName.')]
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

        [string]$ClientTag = ''
    )

    $reflection = Get-SPOModuleReflection
    Assert-NativeShim

    switch ($PSCmdlet.ParameterSetName) {
        'CertificatePath' {
            $cert = if ($CertificatePassword) {
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath, $CertificatePassword)
            } else {
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
            }
        }
        'CertificateObject' {
            $cert = $Certificate
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
        }
    }

    $resource = "$($Url.Scheme)://$($Url.Host)/.default"

    $app = [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::Create($ClientId).
        WithAuthority("https://login.microsoftonline.com/$TenantId", $false).
        WithCertificate($cert).
        Build()

    # MSAL caches and refreshes the token across calls to AcquireTokenForClient,
    # so re-invoking it from ExecutingWebRequest is cheap and handles expiry.
    $tokenProvider = {
        $app.AcquireTokenForClient([string[]]@($resource)).ExecuteAsync().GetAwaiter().GetResult().AccessToken
    }.GetNewClosure()

    $ctxCtor = $reflection.CmdLetContext.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string], [System.Management.Automation.Host.PSHost], [string]),
        $null)
    $context = $ctxCtor.Invoke(@($Url.AbsoluteUri, $Host, $ClientTag))

    $context.WebRequestExecutorFactory = [SPOService.CrossPlatform.HttpClientExecutorFactory]::new()

    $context.add_ExecutingWebRequest([System.EventHandler[Microsoft.SharePoint.Client.WebRequestEventArgs]]{
        param($evSource, $ea)
        # The delegate signature requires (sender, args); sender is unused.
        # Consumed here so PSScriptAnalyzer's PSReviewUnusedParameter rule
        # does not fire. The parameter is not named $sender because that is
        # PowerShell's automatic variable for Register-ObjectEvent scripts.
        $null = $evSource
        $ea.WebRequestExecutor.RequestHeaders['Authorization'] = "Bearer $(& $tokenProvider)"
    }.GetNewClosure())

    # Reject non-admin URLs (e.g. https://contoso.sharepoint.com) before we mutate
    # SPOService.CurrentService. SPOServiceHelper.IsTenantAdminSite is the same
    # check the native module uses.
    $isAdminMethod = $reflection.SPOServiceHelper.GetMethod(
        'IsTenantAdminSite',
        [Reflection.BindingFlags]'Public,NonPublic,Static')
    if (-not $isAdminMethod) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.SPOServiceHelper.IsTenantAdminSite is not present in the installed SPO module. Upgrade 'Microsoft.Online.SharePoint.PowerShell' or file an issue."
    }
    if (-not $isAdminMethod.Invoke($null, @($context))) {
        throw "'$($Url.AbsoluteUri)' is not a SharePoint tenant admin URL. Use the admin site, e.g. https://<tenant>-admin.sharepoint.com."
    }

    $svcCtor = $reflection.SPOService.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @($reflection.CmdLetContext),
        $null)
    $service = $svcCtor.Invoke(@($context))

    $currentServiceProp = $reflection.SPOService.GetProperty('CurrentService', [Reflection.BindingFlags]'Public,NonPublic,Static')
    $currentServiceProp.SetValue($null, $service)

    # Set module-scope token handle only after the full connect succeeds, so a
    # failed Connect-* leaves no stale state behind for Disconnect-* to chase.
    $script:TokenProvider = $tokenProvider
}
