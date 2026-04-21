function New-SPOSystemBrowserOAuthSession {
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
        [uri]$Url
    )

    $oauthSession = $Reflection.OAuthSession.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string], [bool]),
        $null).Invoke(@($Authority, $true))

    $signInTask = $Reflection.OAuthSession.GetMethod(
        'SignIn',
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string]),
        $null).Invoke($oauthSession, @($Url.AbsoluteUri))

    Wait-SPOAuthenticationTask -Task $signInTask
    return $oauthSession
}
