function Assert-NativeShim {
    [CmdletBinding()]
    param()

    if ('SPOService.CrossPlatform.HttpClientExecutorFactory' -as [type]) {
        return
    }

    $candidates = @(
        Join-Path $script:ModuleRoot 'lib/net8.0/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'lib/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'src/SPOService.CrossPlatform/bin/Release/net8.0/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'src/SPOService.CrossPlatform/bin/Debug/net8.0/SPOService.CrossPlatform.dll'
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            Add-Type -Path $path -ErrorAction Stop
            return
        }
    }

    throw @"
SPOService.CrossPlatform.dll was not found in any of:
  $([string]::Join("`n  ", $candidates))

Build it with:
  dotnet build -c Release '$($script:ModuleRoot)/src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj'

Or install the module via 'Install-Module SPOService.CrossPlatform' which ships
the prebuilt DLL in lib/.
"@
}
