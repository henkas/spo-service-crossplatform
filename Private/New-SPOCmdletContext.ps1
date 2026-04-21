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

    $context = $ctxCtor.Invoke(@($Url.AbsoluteUri, $HostInstance, $ClientTag))
    $context.WebRequestExecutorFactory = [SPOService.CrossPlatform.HttpClientExecutorFactory]::new()
    return $context
}
