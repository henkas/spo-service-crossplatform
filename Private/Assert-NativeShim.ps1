function Assert-NativeShim {
    [CmdletBinding()]
    param()

    if ('SPOService.CrossPlatform.HttpClientExecutorFactory' -as [type]) {
        return
    }

    $candidates = @(
        Join-Path $script:ModuleRoot 'bin/net10.0/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'bin/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'src/SPOService.CrossPlatform/bin/Release/net10.0/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'src/SPOService.CrossPlatform/bin/Debug/net10.0/SPOService.CrossPlatform.dll'
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
the prebuilt DLL in bin/net10.0/.
"@
}
