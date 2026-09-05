<#
    Failure-path contract for Connect-SPOServiceCrossPlatform.

    A failed connection must leave an existing SPOService.CurrentService
    untouched and surface the original error. Needs the vendor module and the
    built shim (as CI does); nothing authenticates: the certificate path does
    not exist, so the connect fails after the vendor context is created and
    before any sign-in.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'SPOService.CrossPlatform.psd1') -Force
$failures = [System.Collections.Generic.List[string]]::new()

# Build a sentinel service the same way Connect does, without authenticating,
# and install it as the current connection.
$reflection = & (Get-Module SPOService.CrossPlatform) { Get-SPOModuleReflection }
$flags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
$ctxCtor = $reflection.CmdLetContext.GetConstructor($flags, $null, @([string], [System.Management.Automation.Host.PSHost], [string]), $null)
$sentinelContext = $ctxCtor.Invoke(@('https://contoso-admin.sharepoint.com', $Host, ''))
$svcCtor = $reflection.SPOService.GetConstructor($flags, $null, @([type]$reflection.CmdLetContext), $null)
$sentinel = $svcCtor.Invoke(@($sentinelContext))
$currentServiceProp = $reflection.SPOService.GetProperty('CurrentService', [Reflection.BindingFlags]'Public,NonPublic,Static')
$currentServiceProp.SetValue($null, $sentinel)

function Get-CurrentService { $script:currentServiceProp.GetValue($null) }

$id = '00000000-0000-0000-0000-000000000000'
$missingPfx = Join-Path ([IO.Path]::GetTempPath()) ('spo-connect-failure-' + [guid]::NewGuid().ToString('N') + '.pfx')

# 1. Failure after the vendor context exists (certificate file missing).
try {
    Connect-SPOServiceCrossPlatform -Url 'https://contoso-admin.sharepoint.com' -ClientId $id -TenantId $id -CertificatePath $missingPfx
    $failures.Add('Connect with a missing certificate file should fail.')
} catch {
    $msg = $_.Exception.Message
    if ($msg -notmatch [regex]::Escape((Split-Path -Leaf $missingPfx)) -and $msg -notmatch 'file|find|exist|path') {
        $failures.Add("Original certificate error should surface unmasked; got: $msg")
    }
    if ($msg -match 'Dispose|disposed') { $failures.Add("Cleanup must not mask the original error; got: $msg") }
}
if (-not [object]::ReferenceEquals((Get-CurrentService), $sentinel)) {
    $failures.Add('A failed certificate connect replaced or cleared the existing CurrentService.')
}

# 2. Failure before anything is built (URL rejected).
try {
    Connect-SPOServiceCrossPlatform -Url 'https://contoso.sharepoint.com' -ClientId $id -TenantId $id -CertificatePath $missingPfx
    $failures.Add('Connect with a non-admin URL should fail.')
} catch {
    if ($_.Exception.Message -notmatch 'https://<tenant>-admin\.sharepoint\.com') { $failures.Add("Unexpected URL error: $($_.Exception.Message)") }
}
if (-not [object]::ReferenceEquals((Get-CurrentService), $sentinel)) {
    $failures.Add('A rejected URL replaced or cleared the existing CurrentService.')
}

# 3. Disconnect clears it, and is idempotent.
Disconnect-SPOServiceCrossPlatform
if ($null -ne (Get-CurrentService)) { $failures.Add('Disconnect did not clear CurrentService.') }
Disconnect-SPOServiceCrossPlatform
if ($null -ne (Get-CurrentService)) { $failures.Add('Second Disconnect changed state unexpectedly.') }

if ($failures.Count) { throw ("Connect failure contract failed:`n" + ($failures -join "`n")) }
Write-Information 'Connect failure contract: existing connection preserved on failure, original error surfaced, disconnect idempotent.' -InformationAction Continue
