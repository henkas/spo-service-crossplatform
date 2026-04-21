@{
    RootModule           = 'SPOService.CrossPlatform.psm1'
    ModuleVersion        = '0.1.0'

    # A stable GUID for the module identity. Do not change across releases.
    GUID                 = 'b6e4f2e0-9b57-4f4e-9c1b-0c3a4a6a2a10'

    Author               = 'nstop'
    CompanyName          = 'nstop Ltd.'
    Copyright            = 'Copyright (c) 2026 nstop Ltd. Released under the MIT License.'

    Description          = 'Cross-platform Connect-SPOService replacement for PowerShell 7 on macOS and Linux only (import fails on Windows). Works around two defects in Microsoft.Online.SharePoint.PowerShell (null Win32 registry dereference in SPOServiceHelper.InstantiateSPOService, and empty-body HTTP requests from the 16.0.0.0 Microsoft.SharePoint.Client.Runtime on .NET Core) so the official SPO cmdlets run unmodified on the repaired CSOM pipeline.'

    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')

    # Consumers must have Microsoft.Online.SharePoint.PowerShell installed.
    # Installing this module from PSGallery will pull it in transitively.
    RequiredModules      = @(
        @{ ModuleName = 'Microsoft.Online.SharePoint.PowerShell'; ModuleVersion = '16.0.23408.12000' }
    )

    NestedModules        = @()

    FunctionsToExport    = @(
        'Connect-SPOServiceCrossPlatform'
        'Disconnect-SPOServiceCrossPlatform'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @(
        # Drop-in names matching the broken native SPO cmdlets. Aliases
        # outrank cmdlets in PowerShell command resolution, so `Connect-SPOService`
        # binds to Connect-SPOServiceCrossPlatform from this module.
        'Connect-SPOService'
        'Disconnect-SPOService'
    )
    DscResourcesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @(
                'SharePoint'
                'SharePointOnline'
                'SPO'
                'Office365'
                'CSOM'
                'CrossPlatform'
                'MacOS'
                'Linux'
                'PSEdition_Core'
            )
            LicenseUri   = 'https://github.com/nstophq/spo-service-crossplatform/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/nstophq/spo-service-crossplatform'
            IconUri      = 'https://nstop.app/img/icon-85x85.png'
            ReleaseNotes = 'https://github.com/nstophq/spo-service-crossplatform/blob/main/CHANGELOG.md'
        }
    }
}
