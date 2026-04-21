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

    $ctor = $Reflection.OAuthSession.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @(
            [string],
            [System.Security.Cryptography.X509Certificates.X509Certificate2],
            [string],
            [string]
        ),
        $null)
    if (-not $ctor) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.OAuthSession(string, X509Certificate2, string, string) is not present in the installed SPO module. Certificate auth requires a compatible SPO module build."
    }
    $oauthSession = $ctor.Invoke(@(
        $Settings.Authority,
        $Settings.Certificate,
        $Settings.TenantId,
        $Settings.ClientId
    ))

    $signInMethod = $Reflection.OAuthSession.GetMethod(
        'SignInWithCert',
        [Reflection.BindingFlags]'Public,NonPublic,Instance')
    if (-not $signInMethod) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.OAuthSession.SignInWithCert is not present in the installed SPO module. Certificate auth requires a compatible SPO module build."
    }
    $null = $signInMethod.Invoke($oauthSession, @($Settings.Url.AbsoluteUri))

    return $oauthSession
}
