$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../Private/Assert-SupportedRuntime.ps1')
. (Join-Path $PSScriptRoot '../Private/Test-SPOAdminUrlFormat.ps1')

function Assert-ThrowsLike {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Pattern
    )

    try {
        & $ScriptBlock
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected error matching '$Pattern', got: $($_.Exception.Message)"
        }
        return
    }

    throw "Expected command to throw an error matching '$Pattern'."
}

function Assert-InvalidAdminUrl {
    [CmdletBinding()]
    param()

    foreach ($invalidUrl in 'http://contoso-admin.sharepoint.com', 'https://contoso.sharepoint.com', 'https://contoso-admin.sharepoint.com/sites/foo', 'https://contoso-admin.sharepoint.com?x=1') {
        if (Test-SPOAdminUrlFormat -Url ([uri]$invalidUrl)) {
            throw "Expected invalid admin URL to fail syntactic validation: $invalidUrl"
        }
    }
}

function Assert-RuntimeContract {
    [CmdletBinding()]
    param()

    Assert-SupportedRuntime -Version ([version]'7.6.0')

    Assert-ThrowsLike -Pattern 'PowerShell 7\.6 or newer' -ScriptBlock {
        Assert-SupportedRuntime -Version ([version]'7.5.4')
    }
}

function Assert-AdminUrlContract {
    [CmdletBinding()]
    param()

    if (-not (Test-SPOAdminUrlFormat -Url ([uri]'https://contoso-admin.sharepoint.com'))) {
        throw 'Expected canonical tenant admin URL to pass the syntactic validation helper.'
    }

    Assert-InvalidAdminUrl
}

function Get-ConnectCommandContract {
    [CmdletBinding()]
    param()

    $module = Import-Module (Join-Path $PSScriptRoot '../SPOService.CrossPlatform.psd1') -Force -PassThru
    return Get-Command Connect-SPOServiceCrossPlatform -Module $module
}

function Assert-ConnectCommandParameter {
    [CmdletBinding()]
    param(
        [System.Management.Automation.CommandInfo]$Command
    )

    foreach ($parameterName in 'UseSystemBrowser', 'ClientId', 'TenantId', 'CertificatePath', 'CertificatePassword', 'Certificate', 'UseEnvFile', 'EnvPath') {
        if (-not $Command.Parameters.ContainsKey($parameterName)) {
            throw "Expected Connect-SPOServiceCrossPlatform to expose parameter '$parameterName'."
        }
    }
}

function Assert-ConnectCommandParameterSet {
    [CmdletBinding()]
    param(
        [System.Management.Automation.CommandInfo]$Command
    )

    $parameterSetNames = @($Command.ParameterSets.Name)
    foreach ($parameterSetName in 'CertificatePath', 'CertificateObject', 'EnvFile', 'SystemBrowser') {
        if ($parameterSetNames -notcontains $parameterSetName) {
            throw "Expected Connect-SPOServiceCrossPlatform to expose parameter set '$parameterSetName'."
        }
    }
}

function Assert-SystemBrowserParameterSet {
    [CmdletBinding()]
    param(
        [System.Management.Automation.CommandInfo]$Command
    )

    $systemBrowserSet = $Command.ParameterSets | Where-Object Name -eq 'SystemBrowser'
    if (-not $systemBrowserSet) {
        throw "SystemBrowser parameter set not found."
    }

    if ($systemBrowserSet.Parameters.Name -notcontains 'UseSystemBrowser') {
        throw "SystemBrowser parameter set should include UseSystemBrowser."
    }

    if ($systemBrowserSet.Parameters.Name -contains 'ClientId' -or $systemBrowserSet.Parameters.Name -contains 'TenantId') {
        throw 'SystemBrowser parameter set should not require app-only certificate parameters.'
    }
}

function Invoke-ModuleContractTest {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Assert-RuntimeContract
    Assert-AdminUrlContract

    $cmd = Get-ConnectCommandContract
    Assert-ConnectCommandParameter -Command $cmd
    Assert-ConnectCommandParameterSet -Command $cmd
    Assert-SystemBrowserParameterSet -Command $cmd

    'PASS'
}

Invoke-ModuleContractTest
