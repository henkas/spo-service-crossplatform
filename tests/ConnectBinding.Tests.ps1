<#
    Parameter-set binding contract for Connect-SPOServiceCrossPlatform, plus the
    headless-session guard for the interactive default.

    Binding is probed with a proxy built from the command's own metadata, so
    the function body never runs and nothing can reach sign-in. The probe runs
    in a child non-interactive pwsh so a missing mandatory parameter errors
    instead of prompting. Needs the vendor module installed for Import-Module
    (as CI does); no tenant, no browser.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

# --- 1. Binding probe -------------------------------------------------------

$probe = @'
param([string]$ManifestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module $ManifestPath -Force
$meta = [System.Management.Automation.CommandMetadata]::new((Get-Command Connect-SPOServiceCrossPlatform))
$sets = [scriptblock]::Create(
    [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($meta) + "`nparam(" +
    [System.Management.Automation.ProxyCommand]::GetParamBlock($meta) + ")`n`$PSCmdlet.ParameterSetName")

$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    'CN=binding-probe', $rsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
$cert = $req.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddHours(1))
$url = 'https://contoso-admin.sharepoint.com'
$id = '00000000-0000-0000-0000-000000000000'
$pfx = Join-Path ([IO.Path]::GetTempPath()) 'binding-probe-does-not-exist.pfx'

$cases = [ordered]@{
    'url only'                              = { & $sets -Url $url }
    'url + UseSystemBrowser'                = { & $sets -Url $url -UseSystemBrowser }
    'url + cert path'                       = { & $sets -Url $url -ClientId $id -TenantId $id -CertificatePath $pfx }
    'url + cert path + password'            = { & $sets -Url $url -ClientId $id -TenantId $id -CertificatePath $pfx -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) }
    'url + cert object'                     = { & $sets -Url $url -ClientId $id -TenantId $id -Certificate $cert }
    'url + UseEnvFile'                      = { & $sets -Url $url -UseEnvFile }
    'url + UseEnvFile + EnvPath'            = { & $sets -Url $url -UseEnvFile -EnvPath $pfx }
    'url + ClientId + TenantId (no cert)'   = { & $sets -Url $url -ClientId $id -TenantId $id }
    'url + ClientId only'                   = { & $sets -Url $url -ClientId $id }
    'url + CertificatePath only'            = { & $sets -Url $url -CertificatePath $pfx }
    'url + UseSystemBrowser + ClientId'     = { & $sets -Url $url -UseSystemBrowser -ClientId $id }
    'url + UseEnvFile + UseSystemBrowser'   = { & $sets -Url $url -UseEnvFile -UseSystemBrowser }
    'no url'                                = { & $sets -UseSystemBrowser }
    'url + 13-char ClientTag'               = { & $sets -Url $url -ClientTag 'abcdefghijklm' }
    'url + 14-char ClientTag'               = { & $sets -Url $url -ClientTag 'abcdefghijklmn' }
}
foreach ($case in $cases.GetEnumerator()) {
    try { $result = & $case.Value; $error_ = '' } catch { $result = ''; $error_ = $_.Exception.Message }
    [pscustomobject]@{ Case = $case.Key; Set = [string]$result; Error = $error_ } | ConvertTo-Json -Compress
}

# Integration: the headless guard fires before the vendor module or a browser
# is touched. Simulate an SSH session with no display.
$env:SSH_CONNECTION = '10.0.0.1 1 10.0.0.2 22'
Remove-Item Env:DISPLAY, Env:WAYLAND_DISPLAY -ErrorAction SilentlyContinue
try { Connect-SPOServiceCrossPlatform -Url $url; $error_ = '' } catch { $error_ = $_.Exception.Message }
[pscustomobject]@{ Case = 'headless connect'; Set = ''; Error = $error_ } | ConvertTo-Json -Compress
'@
$probePath = Join-Path ([IO.Path]::GetTempPath()) ('spo-binding-probe-' + [guid]::NewGuid().ToString('N') + '.ps1')
Set-Content -LiteralPath $probePath -Value $probe
try {
    $raw = & pwsh -NoProfile -NonInteractive -File $probePath -ManifestPath (Join-Path $repo 'SPOService.CrossPlatform.psd1') 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Binding probe exited with $LASTEXITCODE`n$($raw -join "`n")" }
} finally {
    Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
}
$results = @{}
foreach ($line in $raw) {
    if ("$line".StartsWith('{')) { $r = "$line" | ConvertFrom-Json; $results[$r.Case] = $r }
}

$expectedSet = [ordered]@{
    'url only'                   = 'SystemBrowser'
    'url + UseSystemBrowser'     = 'SystemBrowser'
    'url + cert path'            = 'CertificatePath'
    'url + cert path + password' = 'CertificatePath'
    'url + cert object'          = 'CertificateObject'
    'url + UseEnvFile'           = 'EnvFile'
    'url + UseEnvFile + EnvPath' = 'EnvFile'
    'url + 13-char ClientTag'    = 'SystemBrowser'
}
$expectedBindingError = [ordered]@{
    'url + ClientId + TenantId (no cert)' = 'cannot be resolved|missing mandatory'
    'url + ClientId only'                 = 'cannot be resolved|missing mandatory'
    'url + CertificatePath only'          = 'missing mandatory'
    'url + UseSystemBrowser + ClientId'   = 'cannot be resolved'
    'url + UseEnvFile + UseSystemBrowser' = 'cannot be resolved'
    'no url'                              = 'missing mandatory'
    'url + 14-char ClientTag'             = 'Cannot validate argument.*13'
}
foreach ($case in $expectedSet.GetEnumerator()) {
    $r = $results[$case.Key]
    if (-not $r) { $failures.Add("No probe result for '$($case.Key)'."); continue }
    if ($r.Error) { $failures.Add("'$($case.Key)' should bind to $($case.Value) but failed: $($r.Error)"); continue }
    if ($r.Set -ne $case.Value) { $failures.Add("'$($case.Key)' bound to '$($r.Set)', expected '$($case.Value)'.") }
}
foreach ($case in $expectedBindingError.GetEnumerator()) {
    $r = $results[$case.Key]
    if (-not $r) { $failures.Add("No probe result for '$($case.Key)'."); continue }
    if (-not $r.Error) { $failures.Add("'$($case.Key)' should fail binding but bound to '$($r.Set)'."); continue }
    if ($r.Error -notmatch $case.Value) { $failures.Add("'$($case.Key)' failed with an unexpected message: $($r.Error)") }
}
$headless = $results['headless connect']
if (-not $headless) {
    $failures.Add('No probe result for the headless connect case.')
} elseif ($headless.Error -notmatch 'interactive sign-in' -or $headless.Error -notmatch '-CertificatePath') {
    $failures.Add("Headless URL-only connect should refuse before sign-in and point at certificate auth; got: $($headless.Error)")
}

# --- 2. Headless guard unit cases -------------------------------------------

$guardScript = Join-Path $repo 'Private/Assert-SPOInteractiveSession.ps1'
if (Test-Path -LiteralPath $guardScript) { . $guardScript } else { $failures.Add("Missing helper: $guardScript") }
$guardCases = if (Test-Path -LiteralPath $guardScript) { @(
    @{ Platform = 'Linux'; Env = @{};                                       Throws = $true;  Why = 'Linux without DISPLAY or WAYLAND_DISPLAY' }
    @{ Platform = 'Linux'; Env = @{ DISPLAY = ':0' };                       Throws = $false; Why = 'Linux X11 desktop' }
    @{ Platform = 'Linux'; Env = @{ WAYLAND_DISPLAY = 'wayland-0' };        Throws = $false; Why = 'Linux Wayland desktop' }
    @{ Platform = 'Linux'; Env = @{ DISPLAY = ':10'; SSH_CONNECTION = 'x' }; Throws = $false; Why = 'SSH with X forwarding' }
    @{ Platform = 'OSX';   Env = @{};                                       Throws = $false; Why = 'local macOS terminal' }
    @{ Platform = 'OSX';   Env = @{ SSH_CONNECTION = 'x' };                 Throws = $true;  Why = 'SSH into macOS without display' }
    @{ Platform = 'OSX';   Env = @{ SSH_TTY = '/dev/ttys001' };             Throws = $true;  Why = 'SSH TTY into macOS' }
    @{ Platform = 'Linux'; Env = @{ DISPLAY = ':0'; ACC_CLOUD = 'PROD' };   Throws = $true;  Why = 'Azure Cloud Shell' }
) } else { @() }
foreach ($case in $guardCases) {
    $threw = $false
    try { Assert-SPOInteractiveSession -Platform $case.Platform -Environment $case.Env } catch {
        $threw = $true
        if ($_.Exception.Message -notmatch 'interactive sign-in' -or $_.Exception.Message -notmatch '-CertificatePath') {
            $failures.Add("Guard message for '$($case.Why)' should explain and point at certificate auth: $($_.Exception.Message)")
        }
    }
    if ($threw -ne $case.Throws) {
        $failures.Add("Guard for '$($case.Why)' expected Throws=$($case.Throws) but Throws=$threw.")
    }
}

if ($failures.Count) {
    throw ("Connect binding contract failed:`n" + ($failures -join "`n"))
}
Write-Information "Connect binding contract: $($expectedSet.Count) sets, $($expectedBindingError.Count) binding errors, $($guardCases.Count) guard cases passed." -InformationAction Continue
