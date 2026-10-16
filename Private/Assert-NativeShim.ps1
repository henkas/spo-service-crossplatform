function Assert-NativeShim {
    [CmdletBinding()]
    param()

    # A loaded assembly cannot be replaced, so an older shim (for example
    # 0.3.0-rc1) already in the session, or a stale build found on disk, must be
    # refused here with clear advice rather than fail later with a
    # type-resolution error. BackgroundInvoker is the newest shim type and,
    # unlike HttpClientExecutorFactory, resolves without the vendor runtime, so
    # it is what tells a current shim from an older one.
    $isCurrent = { [bool]('SPOService.CrossPlatform.BackgroundInvoker' -as [type]) }
    if (& $isCurrent) { return }   # only a current shim defines BackgroundInvoker

    $loaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { -not $_.IsDynamic -and [IO.Path]::GetFileName($_.Location) -eq 'SPOService.CrossPlatform.dll' } |
        Select-Object -First 1
    if ($loaded) {
        throw "An older SPOService.CrossPlatform.dll is already loaded in this session from '$($loaded.Location)' and lacks BackgroundInvoker. A loaded assembly cannot be replaced; start a new pwsh session and import the module again."
    }

    $candidates = @(
        Join-Path $script:ModuleRoot 'bin/net10.0/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'bin/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'src/SPOService.CrossPlatform/bin/Release/net10.0/SPOService.CrossPlatform.dll'
        Join-Path $script:ModuleRoot 'src/SPOService.CrossPlatform/bin/Debug/net10.0/SPOService.CrossPlatform.dll'
    )
    $path = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $path) {
        throw @"
SPOService.CrossPlatform.dll was not found in any of:
  $([string]::Join("`n  ", $candidates))

Build it with:
  dotnet build -c Release '$($script:ModuleRoot)/src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj'

Or install the module via 'Install-Module SPOService.CrossPlatform' which ships
the prebuilt DLL in bin/net10.0/.
"@
    }

    Add-Type -Path $path -ErrorAction Stop
    if (& $isCurrent) { return }
    throw "SPOService.CrossPlatform.dll at '$path' is out of date and lacks BackgroundInvoker. Rebuild it with 'dotnet build -c Release' (or reinstall the module), then start a new pwsh session; the stale assembly is already loaded in this one."
}
