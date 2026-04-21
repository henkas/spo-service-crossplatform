Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SPOWorkaroundTypes {
    [CmdletBinding()]
    param()

    $module = Get-Module Microsoft.Online.SharePoint.PowerShell -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $module) {
        throw 'Microsoft.Online.SharePoint.PowerShell is not installed.'
    }

    if (-not (Get-Module Microsoft.Online.SharePoint.PowerShell)) {
        Import-Module $module.Path | Out-Null
    }

    $dllPath = Join-Path $module.ModuleBase 'Microsoft.Online.SharePoint.PowerShell.dll'
    $assembly = [Reflection.Assembly]::LoadFrom($dllPath)

    @{
        Assembly         = $assembly
        OAuthSession     = $assembly.GetType('Microsoft.Online.SharePoint.PowerShell.OAuthSession', $true)
        CmdLetContext    = $assembly.GetType('Microsoft.Online.SharePoint.PowerShell.CmdLetContext', $true)
        SPOService       = $assembly.GetType('Microsoft.Online.SharePoint.PowerShell.SPOService', $true)
        SPOServiceHelper = $assembly.GetType('Microsoft.Online.SharePoint.PowerShell.SPOServiceHelper', $true)
        RegionEnum       = $assembly.GetType('Microsoft.Online.SharePoint.PowerShell.AADCrossTenantAuthenticationLocation', $true)
    }
}

function Get-RequiredMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Type]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Type[]]$ParameterTypes = @(),

        [Reflection.BindingFlags]$BindingFlags = [Reflection.BindingFlags]'Public,NonPublic,Instance,Static'
    )

    $method = $Type.GetMethod($Name, $BindingFlags, $null, $ParameterTypes, $null)
    if (-not $method) {
        $signature = if ($ParameterTypes.Count) {
            ($ParameterTypes | ForEach-Object FullName) -join ', '
        }
        else {
            '<none>'
        }

        throw "Method lookup failed: $($Type.FullName)::$Name($signature)"
    }

    return $method
}

function Get-RequiredConstructor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Type]$Type,

        [Type[]]$ParameterTypes = @(),

        [Reflection.BindingFlags]$BindingFlags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
    )

    $ctor = $Type.GetConstructor($BindingFlags, $null, $ParameterTypes, $null)
    if (-not $ctor) {
        $signature = if ($ParameterTypes.Count) {
            ($ParameterTypes | ForEach-Object FullName) -join ', '
        }
        else {
            '<none>'
        }

        throw "Constructor lookup failed: $($Type.FullName)::.ctor($signature)"
    }

    return $ctor
}

function Get-RequiredProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Type]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Reflection.BindingFlags]$BindingFlags = [Reflection.BindingFlags]'Public,NonPublic,Instance,Static'
    )

    $property = $Type.GetProperty($Name, $BindingFlags)
    if (-not $property) {
        throw "Property lookup failed: $($Type.FullName)::$Name"
    }

    return $property
}

function Clear-SPOCurrentServiceSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Types
    )

    $currentServiceProperty = Get-RequiredProperty -Type $Types.SPOService -Name 'CurrentService' -BindingFlags ([Reflection.BindingFlags]'Public,NonPublic,Static')

    $currentService = $currentServiceProperty.GetValue($null)
    if ($null -ne $currentService) {
        $currentServiceProperty.SetValue($null, $null)
    }
}

function New-SPOServiceFromOAuthSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Types,

        [Parameter(Mandatory = $true)]
        [uri]$Url,

        [Parameter(Mandatory = $true)]
        [object]$OAuthSession,

        [string]$ClientTag = '',

        [string]$Region = 'Default'
    )

    Clear-SPOCurrentServiceSafe -Types $Types

    $contextCtor = Get-RequiredConstructor -Type $Types.CmdLetContext -ParameterTypes @([string], [System.Management.Automation.Host.PSHost], [string])
    $context = $contextCtor.Invoke(@($Url.AbsoluteUri, $Host, $ClientTag))
    $oauthSessionProperty = Get-RequiredProperty -Type $Types.CmdLetContext -Name 'OAuthSession' -BindingFlags ([Reflection.BindingFlags]'Public,NonPublic,Instance')
    $oauthSessionProperty.SetValue($context, $OAuthSession)

    $isTenantAdminSiteMethod = Get-RequiredMethod -Type $Types.SPOServiceHelper -Name 'IsTenantAdminSite' -ParameterTypes @($Types.CmdLetContext) -BindingFlags ([Reflection.BindingFlags]'NonPublic,Static')

    if (-not $isTenantAdminSiteMethod.Invoke($null, @($context))) {
        throw "The URL '$($Url.AbsoluteUri)' is not a valid SharePoint admin center URL or the authenticated principal lacks access."
    }

    $serviceCtor = Get-RequiredConstructor -Type $Types.SPOService -ParameterTypes @($Types.CmdLetContext)
    $service = $serviceCtor.Invoke(@($context))
    $regionValue = [Enum]::Parse($Types.RegionEnum, $Region)
    $regionProperty = Get-RequiredProperty -Type $Types.SPOService -Name 'Region' -BindingFlags ([Reflection.BindingFlags]'Public,NonPublic,Instance')
    $currentServiceProperty = Get-RequiredProperty -Type $Types.SPOService -Name 'CurrentService' -BindingFlags ([Reflection.BindingFlags]'Public,NonPublic,Static')
    $regionProperty.SetValue($service, $regionValue)
    $currentServiceProperty.SetValue($null, $service)

    return $service
}

function Connect-SPOServiceMacWorkaround {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$Url,

        [string]$AuthenticationUrl = 'https://login.microsoftonline.com/organizations',

        [string]$ClientTag = '',

        [ValidateSet('Default', 'ITAR', 'Germany', 'China')]
        [string]$Region = 'Default'
    )

    $types = Get-SPOWorkaroundTypes

    # The native cmdlet crashes on macOS/Linux before auth because it dereferences
    # Win32 registry roots that are null on Unix. This bypasses that helper path and
    # forces the MSAL system-browser flow, which is the cross-platform-compatible path.
    $oauthSessionCtor = Get-RequiredConstructor -Type $types.OAuthSession -ParameterTypes @([string], [bool])
    $oauthSession = $oauthSessionCtor.Invoke(@($AuthenticationUrl, $true))
    $signInMethod = Get-RequiredMethod -Type $types.OAuthSession -Name 'SignIn' -ParameterTypes @([string]) -BindingFlags ([Reflection.BindingFlags]'Public,NonPublic,Instance')
    $signInTask = $signInMethod.Invoke($oauthSession, @($Url.AbsoluteUri))
    $signInTask.GetAwaiter().GetResult()

    New-SPOServiceFromOAuthSession -Types $types -Url $Url -OAuthSession $oauthSession -ClientTag $ClientTag -Region $Region
}

function Connect-SPOServiceMacCertificateWorkaround {
    [CmdletBinding(DefaultParameterSetName = 'CertificatePath')]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$Url,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'CertificatePath')]
        [string]$CertificatePath,

        [Parameter(ParameterSetName = 'CertificatePath')]
        [securestring]$CertificatePassword,

        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateObject')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [string]$AuthenticationUrl = 'https://login.microsoftonline.com/organizations',

        [string]$ClientTag = '',

        [ValidateSet('Default', 'ITAR', 'Germany', 'China')]
        [string]$Region = 'Default'
    )

    $types = Get-SPOWorkaroundTypes

    if ($PSCmdlet.ParameterSetName -eq 'CertificatePath') {
        $cert = if ($CertificatePassword) {
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath, $CertificatePassword)
        }
        else {
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
        }
    }
    else {
        $cert = $Certificate
    }

    $oauthSessionCtor = Get-RequiredConstructor -Type $types.OAuthSession -ParameterTypes @([string], [System.Security.Cryptography.X509Certificates.X509Certificate2], [string], [string])
    $oauthSession = $oauthSessionCtor.Invoke(@($AuthenticationUrl, $cert, $TenantId, $ClientId))
    $signInWithCertMethod = Get-RequiredMethod -Type $types.OAuthSession -Name 'SignInWithCert' -ParameterTypes @([string]) -BindingFlags ([Reflection.BindingFlags]'Public,NonPublic,Instance')
    $signInWithCertMethod.Invoke($oauthSession, @($Url.AbsoluteUri))

    New-SPOServiceFromOAuthSession -Types $types -Url $Url -OAuthSession $oauthSession -ClientTag $ClientTag -Region $Region
}
