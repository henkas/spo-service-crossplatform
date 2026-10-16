function Get-SPOBrowserOAuthSessionConstructor {
    <#
    .SYNOPSIS
        Resolves the vendor's system-browser OAuthSession constructor.
    .DESCRIPTION
        Vendor 16.0.27709.12000 replaced OAuthSession(string, bool) with
        OAuthSession(string, bool, Action<string>); the new argument is a
        warning callback the vendor invokes null-conditionally (its own
        InstantiateSPOService passes null). Returns whichever shape the loaded
        build has, newest first, or $null. Callers pass $null for the callback:
        SignIn runs on a background thread, where calling back into the
        PowerShell host is unsafe, and the warnings it carries are for the WAM
        broker path, which the vendor disables when useSystemBrowser is true.
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.ConstructorInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [type]$OAuthSession
    )

    $instance = [Reflection.BindingFlags]'Public,NonPublic,Instance'
    # Binary comma, not @(...): array subexpressions would flatten the signatures.
    $signatures = [type[]]@([string], [bool], [System.Action[string]]),
                  [type[]]@([string], [bool])
    foreach ($signature in $signatures) {
        $ctor = $OAuthSession.GetConstructor($instance, $null, $signature, $null)
        if ($ctor) { return $ctor }
    }
    return $null
}
