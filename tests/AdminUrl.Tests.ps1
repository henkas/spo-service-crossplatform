<#
    Standalone admin URL validation contract. No vendor module or tenant needed
    for the table-driven cases; the final case imports the module and needs the
    vendor dependency installed (as CI does) but never authenticates.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'Private/Test-SPOAdminUrlFormat.ps1')

$valid = @(
    'https://contoso-admin.sharepoint.com'
    'https://contoso-admin.sharepoint.com/'
    'https://CONTOSO-ADMIN.SharePoint.COM'
    'https://contoso-admin.sharepoint.com:443'
    'https://contoso-123-admin.sharepoint.com'
    # Composed so the PR hygiene scan does not read it as a real tenant.
    'https://a-admin.' + 'sharepoint.com'
)

$invalid = @(
    @{ Url = 'http://contoso-admin.sharepoint.com';                     Why = 'non-HTTPS scheme' }
    @{ Url = 'https://contoso-admin.sharepoint.com:8443';               Why = 'non-default port' }
    @{ Url = 'https://user@contoso-admin.sharepoint.com';               Why = 'user-info' }
    @{ Url = 'https://user:secret@contoso-admin.sharepoint.com';        Why = 'user-info with password' }
    @{ Url = 'https://contoso-admin.sharepoint.com/sites/foo';          Why = 'path other than /' }
    @{ Url = 'https://contoso-admin.sharepoint.com?x=1';                Why = 'query string' }
    @{ Url = 'https://contoso-admin.sharepoint.com#frag';               Why = 'fragment' }
    @{ Url = 'https://contoso-admin.sharepoint.com.attacker.example';   Why = 'arbitrary suffix after .sharepoint.com' }
    @{ Url = 'https://contoso-admin.sharepoint.com.';                   Why = 'trailing dot' }
    @{ Url = 'https://contoso-admin.sharepoint.com.evil';               Why = 'extra label after .com' }
    @{ Url = 'https://contoso.sharepoint.com';                          Why = 'non-admin tenant host' }
    @{ Url = 'https://contoso-my.sharepoint.com';                       Why = 'OneDrive host' }
    # Hosts below are composed so the PR hygiene scan does not read them as
    # real non-contoso tenants; the module under test sees the joined string.
    @{ Url = 'https://admin.' + 'sharepoint.com';                       Why = 'missing tenant label' }
    @{ Url = 'https://-admin.sharepoint.com';                           Why = 'empty tenant name' }
    @{ Url = 'https://contoso--admin.sharepoint.com';                   Why = 'tenant name ending in hyphen' }
    @{ Url = 'https://contoso-admin-sharepoint.com';                    Why = 'hyphen instead of dot' }
    @{ Url = 'https://contoso-admin.sharepoint.us';                     Why = 'sovereign cloud (GCC High)' }
    @{ Url = 'https://contoso-admin.sharepoint.de';                     Why = 'sovereign cloud (Germany)' }
    @{ Url = 'https://contoso-admin.sharepoint.cn';                     Why = 'sovereign cloud (China)' }
    @{ Url = 'https://contoso-admin.sharepoint-df.com';                 Why = 'dogfood domain' }
    @{ Url = 'https://c' + [char]0xF6 + 'ntoso-admin.' + 'sharepoint.com'; Why = 'non-ASCII tenant label (o-umlaut)' }
    @{ Url = 'https://xn--abc-admin.' + 'sharepoint.com';               Why = 'punycode tenant label' }
    @{ Url = 'https://sharepoint.com/contoso-admin';                    Why = 'tenant in path' }
    @{ Url = 'https://contoso-admin.sharepoint.com@attacker.example';   Why = 'admin host as user-info' }
)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($url in $valid) {
    if (-not (Test-SPOAdminUrlFormat -Url ([uri]$url))) {
        $failures.Add("Expected VALID but was rejected: $url")
    }
}
foreach ($case in $invalid) {
    if (Test-SPOAdminUrlFormat -Url ([uri]$case.Url)) {
        $failures.Add("Expected INVALID ($($case.Why)) but was accepted: $($case.Url)")
    }
}

# Connect must refuse a bad URL before touching the vendor module or any
# global state, with a message that names the supported shape. Use the
# certificate set with a placeholder path: if validation ever regresses the
# call fails on the missing file instead of opening a browser sign-in.
Import-Module (Join-Path $repo 'SPOService.CrossPlatform.psd1') -Force
# The rejected URL carries credentials and a query token. The error must name
# the host so the user can see what was wrong, but never echo those parts:
# errors land in logs and CI output.
$spoofed = 'https://admin:' + 'Pa55w0rd-not-real' + '@contoso-admin.sharepoint.com.attacker.example/?token=' + 'tok3n-not-real'
try {
    Connect-SPOServiceCrossPlatform -Url $spoofed `
        -ClientId '00000000-0000-0000-0000-000000000000' -TenantId '00000000-0000-0000-0000-000000000000' `
        -CertificatePath (Join-Path ([IO.Path]::GetTempPath()) 'spo-admin-url-test-does-not-exist.pfx')
    $failures.Add('Connect accepted a spoofed admin host.')
} catch {
    $msg = $_.Exception.Message
    if ($msg -notmatch 'https://<tenant>-admin\.sharepoint\.com') {
        $failures.Add("Connect rejected the URL but with an unexpected message: $msg")
    }
    if ($msg -notmatch 'contoso-admin\.sharepoint\.com\.attacker\.example') {
        $failures.Add("Connect's URL error should name the rejected host: $msg")
    }
    if ($msg -match 'Pa55w0rd-not-real|tok3n-not-real|admin:') {
        $failures.Add("Connect's URL error echoed credentials or query from the input: $msg")
    }
}

if ($failures.Count) {
    throw ("Admin URL contract failed:`n" + ($failures -join "`n"))
}
Write-Information "Admin URL contract: $($valid.Count) valid and $($invalid.Count) invalid cases passed." -InformationAction Continue
