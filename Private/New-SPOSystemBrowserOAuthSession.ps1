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

    $ctor = $Reflection.OAuthSession.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string], [bool]),
        $null)
    if (-not $ctor) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.OAuthSession(string, bool) is not present in the installed SPO module. System-browser interactive auth requires a newer SPO module."
    }
    $oauthSession = $ctor.Invoke(@($Authority, $true))

    $signInMethod = $Reflection.OAuthSession.GetMethod(
        'SignIn',
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string]),
        $null)
    if (-not $signInMethod) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.OAuthSession.SignIn(string) is not present in the installed SPO module. System-browser interactive auth requires a newer SPO module."
    }
    $signInTask = $signInMethod.Invoke($oauthSession, @($Url.AbsoluteUri))

    Wait-SPOAuthenticationTask -Task $signInTask
    return $oauthSession
}
