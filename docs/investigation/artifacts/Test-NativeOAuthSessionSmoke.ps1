param(
    [Parameter(Mandatory = $true)]
    [string]$AdminUrl,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$CertificatePath,

    [Parameter(ParameterSetName = 'Certificate')]
    [securestring]$CertificatePassword,

    [Parameter(Mandatory = $true, ParameterSetName = 'SystemBrowser')]
    [switch]$UseSystemBrowser,

    [string]$ClientTag = ''
)

$ErrorActionPreference = 'Stop'

$moduleRoot = Resolve-Path (Join-Path $PSScriptRoot '../../..')
. (Join-Path $moduleRoot 'Private/Get-SPOModuleReflection.ps1')
. (Join-Path $moduleRoot 'Private/Assert-NativeShim.ps1')

$reflection = Get-SPOModuleReflection
Assert-NativeShim

$authority = 'https://login.microsoftonline.com/organizations'
$oauthSession = $null

if ($UseSystemBrowser) {
    $oauthSession = $reflection.OAuthSession.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string], [bool]),
        $null).Invoke(@($authority, $true))

    $signInTask = $reflection.OAuthSession.GetMethod(
        'SignIn',
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string]),
        $null).Invoke($oauthSession, @($AdminUrl))

    $null = $signInTask.GetAwaiter().GetResult()
} else {
    if (-not $CertificatePath) {
        throw 'CertificatePath is required for the certificate parameter set.'
    }

    $certificate = if ($CertificatePassword) {
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath, $CertificatePassword)
    } else {
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
    }

    $oauthSession = $reflection.OAuthSession.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @(
            [string],
            [System.Security.Cryptography.X509Certificates.X509Certificate2],
            [string],
            [string]
        ),
        $null).Invoke(@(
            $authority,
            $certificate,
            $TenantId,
            $ClientId
        ))

    $reflection.OAuthSession.GetMethod(
        'SignInWithCert',
        [Reflection.BindingFlags]'Public,NonPublic,Instance').Invoke($oauthSession, @($AdminUrl))
}

$ctxCtor = $reflection.CmdLetContext.GetConstructor(
    [Reflection.BindingFlags]'Public,NonPublic,Instance',
    $null,
    @([string], [System.Management.Automation.Host.PSHost], [string]),
    $null)
$context = $ctxCtor.Invoke(@($AdminUrl, $Host, $ClientTag))

$context.WebRequestExecutorFactory = [SPOService.CrossPlatform.HttpClientExecutorFactory]::new()
$reflection.CmdLetContext.GetProperty(
    'OAuthSession',
    [Reflection.BindingFlags]'Public,NonPublic,Instance').SetValue($context, $oauthSession)

$isAdminMethod = $reflection.SPOServiceHelper.GetMethod(
    'IsTenantAdminSite',
    [Reflection.BindingFlags]'Public,NonPublic,Static')
if (-not $isAdminMethod.Invoke($null, @($context))) {
    throw "'$AdminUrl' is not a SharePoint tenant admin URL."
}

$svcCtor = $reflection.SPOService.GetConstructor(
    [Reflection.BindingFlags]'Public,NonPublic,Instance',
    $null,
    @($reflection.CmdLetContext),
    $null)
$service = $svcCtor.Invoke(@($context))

$currentServiceProp = $reflection.SPOService.GetProperty(
    'CurrentService',
    [Reflection.BindingFlags]'Public,NonPublic,Static')
$currentServiceProp.SetValue($null, $service)

Get-SPOTenant | Select-Object -First 1
