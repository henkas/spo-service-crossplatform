Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Intentionally refuse to load on Windows: the two defects this module works
# around only exist on .NET Core outside Windows, and silently shadowing the
# native Connect-SPOService cmdlet on Windows would hurt, not help.
if ($IsWindows) {
    throw "SPOService.CrossPlatform is for macOS/Linux only. On Windows, use the stock 'Microsoft.Online.SharePoint.PowerShell' module and its native Connect-SPOService cmdlet."
}

$script:ModuleRoot = $PSScriptRoot
$script:TokenProvider = $null

# Dot-source all Private helpers first, then Public cmdlets.
foreach ($scope in 'Private', 'Public') {
    $folder = Join-Path $script:ModuleRoot $scope
    if (-not (Test-Path $folder)) { continue }
    Get-ChildItem -Path $folder -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}

# Drop-in aliases matching the names of the broken native cmdlets. PowerShell's
# command precedence resolves aliases above cmdlets, so `Connect-SPOService`
# called in a session where both this module and Microsoft.Online.SharePoint.PowerShell
# are loaded will bind to our alias rather than the broken native cmdlet.
Set-Alias -Name Connect-SPOService    -Value Connect-SPOServiceCrossPlatform    -Scope Script -Force
Set-Alias -Name Disconnect-SPOService -Value Disconnect-SPOServiceCrossPlatform -Scope Script -Force

Export-ModuleMember `
    -Function @('Connect-SPOServiceCrossPlatform', 'Disconnect-SPOServiceCrossPlatform') `
    -Alias    @('Connect-SPOService', 'Disconnect-SPOService')
