function Assert-SPOVendorContract {
    <#
    .SYNOPSIS
        Throws one actionable compatibility error if the vendor contract fails.
    .DESCRIPTION
        Runs before authentication and before any global state is touched. The
        message carries what a bug report needs (vendor version and path,
        PowerShell, runtime, OS, architecture, missing members) and nothing
        tenant-specific.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Reflection
    )

    $report = Test-SPOVendorContract -Reflection $Reflection
    if ($report.Compatible) { return }

    $env = $report.Environment
    $missing = ($report.Missing | ForEach-Object { "  - $_" }) -join "`n"
    throw @"
SPOService.CrossPlatform is not compatible with the loaded Microsoft.Online.SharePoint.PowerShell $($report.Vendor.Version) at $($report.Vendor.ModuleBase). Its internal API is missing $($report.Missing.Count) member(s) this module relies on:
$missing
Environment: PowerShell $($env.PowerShell); $($env.Runtime); $($env.OS); $($env.Architecture).
Minimum supported vendor version: $($report.Vendor.MinimumVersion). Nothing was authenticated or changed.
Please report this at https://github.com/henkas/spo-service-crossplatform/issues and include the vendor version and environment above (no tenant details are needed).
"@
}
