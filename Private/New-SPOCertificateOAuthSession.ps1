function New-SPOCertificateOAuthSession {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper invoked only by Connect-SPOServiceCrossPlatform; user-facing confirmation semantics belong on the public cmdlet, not the internal reflection bridge.')]
    param(
        [Parameter(Mandatory = $true)]
        $Reflection,

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
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
            $Settings.Authority,
            $Settings.Certificate,
            $Settings.TenantId,
            $Settings.ClientId
        ))

    $Reflection.OAuthSession.GetMethod(
        'SignInWithCert',
        [Reflection.BindingFlags]'Public,NonPublic,Instance').Invoke($oauthSession, @($Settings.Url.AbsoluteUri))

    return $oauthSession
}
