function New-SPOCertificateOAuthSession {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper invoked only by Connect-SPOServiceCrossPlatform; user-facing confirmation semantics belong on the public cmdlet, not the internal reflection bridge.')]
    param(
        [Parameter(Mandatory = $true)]
        $Reflection,

        [Parameter(Mandatory = $true)]
        [string]$Authority,

        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [uri]$Url
    )

    $oauthSession = $Reflection.OAuthSession.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @(
            [string],
            [System.Security.Cryptography.X509Certificates.X509Certificate2],
            [string],
            [string]
        ),
        $null).Invoke(@(
            $Authority,
            $Certificate,
            $TenantId,
            $ClientId
        ))

    $Reflection.OAuthSession.GetMethod(
        'SignInWithCert',
        [Reflection.BindingFlags]'Public,NonPublic,Instance').Invoke($oauthSession, @($Url.AbsoluteUri))

    return $oauthSession
}
