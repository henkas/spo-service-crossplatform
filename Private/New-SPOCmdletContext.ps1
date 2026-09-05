function New-SPOCmdletContext {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper that materializes the reflected SPO CmdLetContext object. It is not a user-invoked state-changing cmdlet surface.')]
    param(
        [Parameter(Mandatory = $true)]
        $Reflection,

        [Parameter(Mandatory = $true)]
        [uri]$Url,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Host.PSHost]$HostInstance,

        [string]$ClientTag = ''
    )

    $ctxCtor = $Reflection.CmdLetContext.GetConstructor(
        [Reflection.BindingFlags]'Public,NonPublic,Instance',
        $null,
        @([string], [System.Management.Automation.Host.PSHost], [string]),
        $null)
    if (-not $ctxCtor) {
        throw "Internal error: Microsoft.Online.SharePoint.PowerShell.CmdLetContext(string, PSHost, string) is not present in the installed SPO module."
    }

    try {
        $context = $ctxCtor.Invoke(@($Url.AbsoluteUri, $HostInstance, $ClientTag))
    } catch [System.Reflection.TargetInvocationException] {
        $inner = $_.Exception.InnerException
        if ($ClientTag -and $inner -is [System.ArgumentOutOfRangeException]) {
            # Connect already caps ClientTag at 13 characters; this covers a
            # vendor build whose own prefix leaves even less room.
            throw "Microsoft.Online.SharePoint.PowerShell $($Reflection.Version) rejected ClientTag '$ClientTag' ($($ClientTag.Length) characters): the vendor prepends its own tag and CSOM caps the combined value at 32 characters. Use a shorter tag or omit it. Underlying error: $($inner.Message)"
        }
        throw
    }
    $context.WebRequestExecutorFactory = [SPOService.CrossPlatform.HttpClientExecutorFactory]::new()
    return $context
}
