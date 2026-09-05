function Test-SPOVendorContract {
    <#
    .SYNOPSIS
        Probes every non-public vendor member the connect path relies on.
    .DESCRIPTION
        Non-authenticating. Resolves each constructor, method and settable
        property by exact signature and reports which are missing, so a vendor
        update that changes its internals is caught before any sign-in or
        global state change. Returns a report; Assert-SPOVendorContract turns a
        failing report into one actionable exception.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Reflection
    )

    $instance = [Reflection.BindingFlags]'Public,NonPublic,Instance'
    $static = [Reflection.BindingFlags]'Public,NonPublic,Static'
    $cmdletContext = $Reflection.CmdLetContext
    $oauthSession = $Reflection.OAuthSession
    $spoService = $Reflection.SPOService
    $helper = $Reflection.SPOServiceHelper
    $x509 = [System.Security.Cryptography.X509Certificates.X509Certificate2]
    $psHost = [System.Management.Automation.Host.PSHost]

    $settableProperty = {
        param([type]$Type, [string]$Name, [Reflection.BindingFlags]$Flags)
        $property = $Type.GetProperty($Name, $Flags)
        if ($property -and $property.GetSetMethod($true)) { $property } else { $null }
    }

    # The shim type is only present once Assert-NativeShim has run. When it is,
    # also require that the factory property can actually accept it.
    $executorFactory = & $settableProperty $cmdletContext 'WebRequestExecutorFactory' $instance
    $shimType = 'SPOService.CrossPlatform.HttpClientExecutorFactory' -as [type]
    if ($executorFactory -and $shimType -and -not $executorFactory.PropertyType.IsAssignableFrom($shimType)) {
        $executorFactory = $null
    }

    $members = [ordered]@{
        'CmdLetContext(string, PSHost, string)'                 = $cmdletContext.GetConstructor($instance, $null, @([string], $psHost, [string]), $null)
        'CmdLetContext.OAuthSession setter'                     = & $settableProperty $cmdletContext 'OAuthSession' $instance
        'CmdLetContext.WebRequestExecutorFactory setter'        = $executorFactory
        'OAuthSession(string, bool)'                            = $oauthSession.GetConstructor($instance, $null, @([string], [bool]), $null)
        'OAuthSession.SignIn(string)'                           = $oauthSession.GetMethod('SignIn', $instance, $null, @([string]), $null)
        'OAuthSession(string, X509Certificate2, string, string)' = $oauthSession.GetConstructor($instance, $null, @([string], $x509, [string], [string]), $null)
        'OAuthSession.SignInWithCert(string)'                   = $oauthSession.GetMethod('SignInWithCert', $instance, $null, @([string]), $null)
        'SPOService(CmdLetContext)'                             = $spoService.GetConstructor($instance, $null, @([type]$cmdletContext), $null)
        'SPOService.CurrentService static setter'               = & $settableProperty $spoService 'CurrentService' $static
        'SPOServiceHelper.IsTenantAdminSite(CmdLetContext)'     = $helper.GetMethod('IsTenantAdminSite', $static, $null, @([type]$cmdletContext), $null)
    }

    $missing = @($members.GetEnumerator() | Where-Object { $null -eq $_.Value } | ForEach-Object { $_.Key })

    [pscustomobject]@{
        Compatible  = ($missing.Count -eq 0)
        Missing     = [string[]]$missing
        Members     = $members
        Vendor      = [pscustomobject]@{
            Version        = $Reflection.Version
            ModuleBase     = $Reflection.ModuleBase
            MinimumVersion = $Reflection.MinimumVersion
        }
        Environment = $Reflection.Environment
    }
}
