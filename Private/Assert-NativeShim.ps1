function Assert-NativeShim {
    [CmdletBinding()]
    param()

    # Every shim type the connect path uses. A loaded assembly cannot be
    # replaced, so a session that already loaded an older shim (for example
    # 0.3.0-rc1, before BackgroundInvoker existed) must be refused here with
    # new-session advice rather than fail later with a type-resolution error.
    $requiredTypes = 'SPOService.CrossPlatform.HttpClientExecutorFactory', 'SPOService.CrossPlatform.BackgroundInvoker'
    $loaded = 'SPOService.CrossPlatform.HttpClientExecutorFactory' -as [type]
    $missing = @($requiredTypes | Where-Object { -not ($_ -as [type]) })
    if ($loaded -and $missing.Count -eq 0) { return }
    if ($loaded) {
        throw "An older SPOService.CrossPlatform.dll is already loaded in this session from '$($loaded.Assembly.Location)' and lacks: $($missing -join ', '). A loaded assembly cannot be replaced; start a new pwsh session and import the module again."
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
