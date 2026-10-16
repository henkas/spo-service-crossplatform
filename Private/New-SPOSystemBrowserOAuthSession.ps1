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

    $ctor = Get-SPOBrowserOAuthSessionConstructor -OAuthSession $Reflection.OAuthSession
    if (-not $ctor) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.OAuthSession(string, bool[, Action<string>]) is not present in the installed SPO module. System-browser interactive auth requires a newer SPO module."
    }
    # Newer vendors take a trailing warning callback; see the resolver for why it is null.
    $ctorArgs = [System.Collections.Generic.List[object]]::new()
    $ctorArgs.Add($Authority)
    $ctorArgs.Add($true)
    if ($ctor.GetParameters().Count -eq 3) { $ctorArgs.Add($null) }
    $oauthSession = $ctor.Invoke($ctorArgs.ToArray())

    $signInMethod = $Reflection.OAuthSession.GetMethod(
        'SignIn',
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string]),
        $null)
    if (-not $signInMethod) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.OAuthSession.SignIn(string) is not present in the installed SPO module. System-browser interactive auth requires a newer SPO module."
    }
    # The vendor's SignIn blocks its calling thread for the whole sign-in (see
    # BackgroundInvoker). Run it on the thread pool so this thread can poll and
    # Ctrl+C returns the prompt instead of waiting out the vendor's 90 s timer.
    $signInTask = [SPOService.CrossPlatform.BackgroundInvoker]::InvokeAsync(
        $signInMethod, $oauthSession, [object[]]@([string]$Url.AbsoluteUri))

    Wait-SPOAuthenticationTask -Task $signInTask
    return $oauthSession
}
