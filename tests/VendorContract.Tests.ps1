<#
    Vendor module selection and reflection contract.

    A: version selection policy on synthetic module lists (no vendor needed).
    B: the minimum version comes from the manifest, not a second constant.
    C: against the installed vendor module, the reflection helper picks the
       highest supported version and every private member the connect path
       relies on is present (non-authenticating).
    D: a synthetic incompatible module yields one actionable error naming the
       missing members, the vendor version and the issue tracker.
    E: if an installed version below the minimum exists, a child session that
       already loaded it is refused with advice to start a new session.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script:ModuleRoot = $repo
Get-ChildItem -Path (Join-Path $repo 'Private') -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
$failures = [System.Collections.Generic.List[string]]::new()
$vendorName = 'Microsoft.Online.SharePoint.PowerShell'
$manifestFloor = [version](Import-PowerShellDataFile (Join-Path $repo 'SPOService.CrossPlatform.psd1')).RequiredModules[0].ModuleVersion

function Assert-That([bool]$Condition, [string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Failure([scriptblock]$Action, [string]$Pattern, [string]$What) {
    try { & $Action; $script:failures.Add("$What should have thrown (pattern: $Pattern).") } catch {
        if ($_.Exception.Message -notmatch $Pattern) { $script:failures.Add("$What threw an unexpected message: $($_.Exception.Message)") }
    }
}
function Get-FakeModule([string]$Version) {
    [pscustomobject]@{ Name = $vendorName; Version = [version]$Version; ModuleBase = "/fake/$Version" }
}

# --- A. Selection policy ----------------------------------------------------
$min = [version]'16.0.23408.12000'
$old = Get-FakeModule '16.0.9119.1200'
$ok1 = Get-FakeModule '16.0.23408.12000'
$ok2 = Get-FakeModule '16.0.27515.12000'

$sel = Select-SPOVendorModule -Loaded @() -Available @($old, $ok1, $ok2) -MinimumVersion $min
Assert-That ($sel.Action -eq 'Import' -and $sel.Version -eq $ok2.Version) 'Nothing loaded: should import the highest installed version at or above the minimum.'

$sel = Select-SPOVendorModule -Loaded @() -Available @($ok2, $old, $ok1) -MinimumVersion $min
Assert-That ($sel.Version -eq $ok2.Version) 'Selection must not depend on directory or list order.'

$sel = Select-SPOVendorModule -Loaded @($ok1) -Available @($old, $ok1, $ok2) -MinimumVersion $min
Assert-That ($sel.Action -eq 'UseLoaded' -and $sel.Version -eq $ok1.Version) 'A supported version already loaded must be reused, not replaced, even if a newer one is installed.'

Assert-Failure { Select-SPOVendorModule -Loaded @($old) -Available @($old, $ok2) -MinimumVersion $min } '16\.0\.9119\.1200.*already loaded.*new (pwsh|PowerShell) session' 'Old version already loaded'
Assert-Failure { Select-SPOVendorModule -Loaded @() -Available @($old) -MinimumVersion $min } '16\.0\.9119\.1200.*(below|older than).*16\.0\.23408\.12000.*Update-Module' 'Only an old version installed'
Assert-Failure { Select-SPOVendorModule -Loaded @() -Available @() -MinimumVersion $min } 'not installed.*Install-Module' 'Nothing installed'
Assert-Failure { Select-SPOVendorModule -Loaded @($ok1, $ok2) -Available @($ok1, $ok2) -MinimumVersion $min } 'more than one version.*loaded' 'Two versions loaded'

# --- B. Minimum version comes from the manifest -----------------------------
Assert-That ((Get-SPOVendorMinimumVersion) -eq $manifestFloor) "Get-SPOVendorMinimumVersion must return the manifest floor $manifestFloor."

# --- C. Real vendor module: selection and full member contract --------------
$available = @(Get-Module -ListAvailable $vendorName)
$expectedVersion = ($available | Where-Object { $_.Version -ge $manifestFloor } | Sort-Object Version -Descending | Select-Object -First 1).Version
$reflection = Get-SPOModuleReflection
Assert-That ($reflection.Version -eq $expectedVersion) "Reflection loaded $($reflection.Version); expected the highest supported installed version $expectedVersion."
Assert-That ([string]$reflection.ModuleBase -and (Test-Path (Join-Path $reflection.ModuleBase 'Microsoft.Online.SharePoint.PowerShell.dll'))) 'Reflection must report the loaded module path.'
foreach ($field in 'PowerShell', 'Runtime', 'OS', 'Architecture') {
    Assert-That (-not [string]::IsNullOrWhiteSpace([string]$reflection.Environment.$field)) "Reflection environment must include $field for diagnostics."
}

# Load the built shim first so the probe also checks that the vendor's
# WebRequestExecutorFactory property can accept our factory type. Without the
# shim that branch is skipped and a vendor type change would go unnoticed.
Assert-NativeShim
$shimType = 'SPOService.CrossPlatform.HttpClientExecutorFactory' -as [type]
Assert-That ($null -ne $shimType) 'Native shim must be loaded so the executor-factory assignability check runs.'

$report = Test-SPOVendorContract -Reflection $reflection
$expectedMembers = @(
    'CmdLetContext(string, PSHost, string)'
    'CmdLetContext.OAuthSession setter'
    'CmdLetContext.WebRequestExecutorFactory setter'
    'OAuthSession(string, bool)'
    'OAuthSession.SignIn(string)'
    'OAuthSession(string, X509Certificate2, string, string)'
    'OAuthSession.SignInWithCert(string)'
    'SPOService(CmdLetContext)'
    'SPOService.CurrentService static setter'
    'SPOServiceHelper.IsTenantAdminSite(CmdLetContext)'
)
Assert-That ($report.Compatible) "Installed vendor $($reflection.Version) should satisfy the contract; missing: $($report.Missing -join ', ')"
foreach ($m in $expectedMembers) {
    Assert-That ($report.Members.Contains($m)) "Contract report must probe '$m'."
}
Assert-That ($report.Members.Count -eq $expectedMembers.Count) "Contract probes $($report.Members.Count) members; expected $($expectedMembers.Count)."
Assert-That ($report.Vendor.Version -eq $reflection.Version) 'Report must carry the vendor version.'
try { Assert-SPOVendorContract -Reflection $reflection } catch { $failures.Add("Assert-SPOVendorContract threw for a compatible module: $($_.Exception.Message)") }

# --- D. Synthetic incompatible module ---------------------------------------
$fake = [pscustomobject]@{
    Version          = [version]'99.0.0.1'
    ModuleBase       = '/fake/99.0.0.1'
    MinimumVersion   = $manifestFloor
    Environment      = $reflection.Environment
    Assembly         = $null
    CmdLetContext    = [object]
    OAuthSession     = [object]
    SPOService       = [object]
    SPOServiceHelper = [object]
}
$fakeReport = Test-SPOVendorContract -Reflection $fake
Assert-That (-not $fakeReport.Compatible -and $fakeReport.Missing.Count -eq $expectedMembers.Count) "Synthetic module should miss all $($expectedMembers.Count) members; missed $($fakeReport.Missing.Count)."
try {
    Assert-SPOVendorContract -Reflection $fake
    $failures.Add('Assert-SPOVendorContract should throw for an incompatible module.')
} catch {
    $msg = $_.Exception.Message
    Assert-That ($msg -match '99\.0\.0\.1') 'Compatibility error must name the vendor version.'
    Assert-That ($msg -match '/fake/99\.0\.0\.1') 'Compatibility error must name the module path.'
    Assert-That ($msg -match 'github\.com/henkas/spo-service-crossplatform/issues') 'Compatibility error must link to the issue tracker.'
    Assert-That ($msg -match [regex]::Escape($reflection.Environment.PowerShell)) 'Compatibility error must include the PowerShell version.'
    foreach ($m in $expectedMembers) { Assert-That ($msg.Contains($m)) "Compatibility error must list missing member '$m'." }
}

# --- D2. Executor-factory property exists but cannot accept the shim --------
# A context type whose WebRequestExecutorFactory setter has the wrong type must
# be reported as missing, while an object-typed OAuthSession setter still passes.
Add-Type -TypeDefinition @'
namespace SPOServiceContractTests {
    public class WrongFactoryContext {
        public string WebRequestExecutorFactory { get; set; }
        public object OAuthSession { get; set; }
    }
}
'@
$wrongFactory = [pscustomobject]@{
    Version          = [version]'99.0.0.2'
    ModuleBase       = '/fake/99.0.0.2'
    MinimumVersion   = $manifestFloor
    Environment      = $reflection.Environment
    Assembly         = $null
    CmdLetContext    = [SPOServiceContractTests.WrongFactoryContext]
    OAuthSession     = [object]
    SPOService       = [object]
    SPOServiceHelper = [object]
}
$wrongReport = Test-SPOVendorContract -Reflection $wrongFactory
Assert-That ($wrongReport.Missing -contains 'CmdLetContext.WebRequestExecutorFactory setter') 'A factory property that cannot accept the shim type must be reported as missing.'
Assert-That ($wrongReport.Missing -notcontains 'CmdLetContext.OAuthSession setter') 'A settable OAuthSession property must not be reported as missing.'

# --- E. Already-loaded version below the minimum (only where one exists) ----
$belowFloor = $available | Where-Object { $_.Version -lt $manifestFloor } | Sort-Object Version -Descending | Select-Object -First 1
if ($belowFloor) {
    $child = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
Import-Module '$vendorName' -RequiredVersion '$($belowFloor.Version)' -WarningAction SilentlyContinue
`$script:ModuleRoot = '$repo'
Get-ChildItem -Path '$(Join-Path $repo 'Private')' -Filter '*.ps1' -File | ForEach-Object { . `$_.FullName }
try { `$null = Get-SPOModuleReflection; 'NO-ERROR' } catch { `$_.Exception.Message }
"@
    $out = & pwsh -NoProfile -NonInteractive -Command $child 2>&1 | Out-String
    Assert-That ($out -match [regex]::Escape("$($belowFloor.Version)") -and $out -match 'already loaded' -and $out -match 'new (pwsh|PowerShell) session') "Already-loaded $($belowFloor.Version) should be refused with new-session advice; got: $out"
    Write-Information "Ran already-loaded check against installed $($belowFloor.Version)." -InformationAction Continue
} else {
    Write-Information 'No installed vendor version below the minimum; already-loaded check exercised on synthetic data only.' -InformationAction Continue
}

if ($failures.Count) { throw ("Vendor contract failed:`n" + ($failures -join "`n")) }
Write-Information "Vendor contract: selection policy, manifest floor, $($expectedMembers.Count) members against $($reflection.Version), synthetic failure report passed." -InformationAction Continue
