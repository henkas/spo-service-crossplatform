# SPOService.CrossPlatform

[![PSGallery Version](https://img.shields.io/powershellgallery/v/SPOService.CrossPlatform?style=flat&logo=data:image/svg%2Bxml;base64,PHN2ZyBpZD0iTGF5ZXJfMSIgZGF0YS1uYW1lPSJMYXllciAxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI0MCIgaGVpZ2h0PSIzOCIgdmlld0JveD0iMCAwIDQxIDM4Ij4NCiAgPHRpdGxlPkFydGJvYXJkIDE8L3RpdGxlPg0KICA8ZyBpZD0iZzM3NzIiPg0KICAgIDxnIGlkPSJnMzc3MCI+DQogICAgICA8cGF0aCBpZD0icGF0aDM3NjgiIGQ9Ik0zOS41LDMuODVIOS4yNDlhMi4yMzcsMi4yMzcsMCwwLDAtMi4xLDEuN2wtNi4xLDI2LjZhMS4zLDEuMywwLDAsMCwxLjMsMS43aDMwLjNhMi4yMzcsMi4yMzcsMCwwLDAsMi4xLTEuN2w2LjEtMjYuNTVBMS4zNTUsMS4zNTUsMCwwLDAsMzkuNSwzLjg1WiIgZmlsbD0iIzAwNzJjNiIvPg0KICAgIDwvZz4NCiAgPC9nPg0KICA8cGF0aCBpZD0icGF0aDM3NzgiIGQ9Ik0yNC40LDE5LjNjLS4xLjMtLjQuNS0uOS45TDkuOSwzMGExLjg2OCwxLjg2OCwwLDAsMS0yLjQtLjQsMS43MywxLjczLDAsMCwxLC4zLTIuNGwxMi4zLTguOXYtLjJMMTIuNCw5LjlhMS43MiwxLjcyLDAsMCwxLC4xLTIuNCwxLjYzMywxLjYzMywwLDAsMSwyLjQsMGw5LjMsOS45QTEuMywxLjMsMCwwLDEsMjQuNCwxOS4zWiIgZmlsbD0iI2ZmZiIvPg0KICA8cGF0aCBpZD0icGF0aDM3ODAiIGQ9Ik0xOS44LDI2LjdoNy40YTEuNSwxLjUsMCwxLDEsMCwzSDE5LjhhMS41LDEuNSwwLDEsMSwwLTNaIiBmaWxsPSIjZmZmIi8+DQo8L3N2Zz4NCg==)](https://www.powershellgallery.com/packages/SPOService.CrossPlatform)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/nstophq/spo-service-crossplatform/build.yml?branch=main&style=flat&logo=github&logoColor=%23fff)](https://github.com/nstophq/spo-service-crossplatform/actions/workflows/build.yml)
[![GitHub Issues](https://img.shields.io/github/issues/nstophq/spo-service-crossplatform?style=flat&logo=github&logoColor=%23fff)](https://github.com/nstophq/spo-service-crossplatform/issues)
[![GitHub License](https://img.shields.io/github/license/nstophq/spo-service-crossplatform?style=flat&logo=github&logoColor=%23fff)](LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/nstophq/spo-service-crossplatform?style=flat&logo=github&logoColor=%23fff)](https://github.com/nstophq/spo-service-crossplatform/releases/latest)

**macOS / Linux only.** Cross-platform replacement for `Connect-SPOService`
that lets the official
[`Microsoft.Online.SharePoint.PowerShell`](https://learn.microsoft.com/powershell/sharepoint/sharepoint-online/introduction-sharepoint-online-management-shell)
cmdlets run unmodified on **PowerShell 7.6+ on macOS and Linux**.
Importing this module on Windows fails intentionally — use the stock SPO
module there.

```powershell
Connect-SPOServiceCrossPlatform -Url https://contoso-admin.sharepoint.com

Get-SPOTenant
Get-SPOSite -Limit 10
Get-SPOOrgAssetsLibrary
```

The module also exports a `Connect-SPOService` alias (and
`Disconnect-SPOService`) that shadow the broken native cmdlets of the same
name for the current session. Existing scripts written for Windows can
import `SPOService.CrossPlatform` on macOS/Linux and keep calling
`Connect-SPOService` unchanged.

The module's role is to get the CSOM transport working, not to vet every
cmdlet. The following have been exercised end-to-end against a real
tenant: `Get-SPOTenant`, `Get-SPOSite`, `Get-SPOOrgAssetsLibrary`,
`Get-SPOUser`, `Remove-SPOOrgAssetsLibrary`. The broader cmdlet surface
routes through the same pipeline and should work — please open an issue
if you hit a cmdlet that doesn't.

## Why this exists

The SPO Management Shell is Microsoft-supported on **Windows PowerShell 5.1
only**. Running `Connect-SPOService` on macOS fails with
`Object reference not set to an instance of an object`, and even after that
is bypassed every CSOM call fails with `Invalid request.` or
`400 Bad Request`. This module works around both defects:

1. **Null Win32 registry dereference.** `SPOServiceHelper.InstantiateSPOService`
   unconditionally calls `Microsoft.Win32.Registry.CurrentUser.OpenSubKey(...)`
   and `LocalMachine.OpenSubKey(...)`. Both properties return `null` on
   non-Windows .NET Core. The module crashes before auth even runs.

2. **Empty-body HTTP requests.** The module ships
   `Microsoft.SharePoint.Client.Runtime` 16.0.0.0, compiled against .NET
   Framework's `HttpWebRequest`. On .NET Core, `HttpWebRequestExecutor.GetRequestStream()`
   does not flush the body to the socket, so SharePoint receives
   `Content-Length: 0` and returns `Invalid request.` for every CSOM POST.

A native shim (`src/SPOService.CrossPlatform/HttpClientExecutor.cs`) replaces
the broken executor with an `HttpClient`-based one. The PowerShell entry
point (`Connect-SPOServiceCrossPlatform`) builds `CmdLetContext` + `SPOService`
directly via reflection to skip the null-deref path, installs the shim on
the context, and sets `SPOService.CurrentService` so the official cmdlets
pick it up transparently.

Full root-cause analysis and evidence: [`docs/investigation/`](docs/investigation/).

## Installation

### From PSGallery

```powershell
Install-Module SPOService.CrossPlatform
```

The published package includes the prebuilt shim DLL under `lib/net8.0/`.

### From source

Requires PowerShell 7.6+, .NET 8 SDK, and the SPO module installed (the
shim references its `Microsoft.SharePoint.Client.Runtime.dll`).

```bash
git clone https://github.com/nstophq/spo-service-crossplatform.git
cd spo-service-crossplatform

# Install the official SPO module once if you don't have it
pwsh -c 'Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser'

# Build the native shim
dotnet build -c Release src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj

# Load the module
pwsh -c 'Import-Module ./SPOService.CrossPlatform.psd1'
```

The module auto-discovers the DLL from
`src/SPOService.CrossPlatform/bin/Release/net8.0/` or `lib/net8.0/`.

## Authentication

Authentication uses the native reflected `OAuthSession` model from the
official SPO module. On Unix, this module keeps the native auth/session
shape and only replaces the broken CSOM transport.

Supported auth flows:

### 1. Certificate-based app-only auth

```powershell
Connect-SPOServiceCrossPlatform `
    -Url https://contoso-admin.sharepoint.com `
    -ClientId <app-id> -TenantId <tenant-id> `
    -CertificatePath ./app.pfx `
    -CertificatePassword (Read-Host -AsSecureString 'PFX password')
```

### 2. Preloaded X509Certificate2

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath, $pwd)

Connect-SPOServiceCrossPlatform `
    -Url https://contoso-admin.sharepoint.com `
    -ClientId <app-id> -TenantId <tenant-id> `
    -Certificate $cert
```

### 3. `.env` file (opt-in convenience)

For local development. Create a `.env` next to where you run the cmdlet:

```ini
ClientId=00000000-0000-0000-0000-000000000000
TenantId=00000000-0000-0000-0000-000000000000
password=<pfx-password>
# Optional. Defaults to ./app.pfx
# CertificatePath=/absolute/path/to/cert.pfx
```

```powershell
Connect-SPOServiceCrossPlatform -Url https://contoso-admin.sharepoint.com -UseEnvFile
```

Ensure restrictive permissions on the file (`chmod 600 .env`) and never
commit it. See [`.env.example`](.env.example). For production, prefer
`Microsoft.PowerShell.SecretManagement` or another secret store.

### 4. Interactive system browser

```powershell
Connect-SPOServiceCrossPlatform `
    -Url https://contoso-admin.sharepoint.com `
    -UseSystemBrowser
```

This is the only interactive mode supported on Unix in this release.
Embedded-webview interactive auth is intentionally not supported.

> **Azure Cloud Shell is not supported by this flow.** `-UseSystemBrowser`
> spins up a local HTTP listener on `127.0.0.1` and opens a browser on the
> host to receive the OAuth redirect. Cloud Shell's session has no local
> browser and no way to reach the listener from outside the container, so
> the sign-in hangs until it times out. A future release may add a
> terminal-only flow (print the authorization URL, let the user open it
> in their own browser, and paste the final redirect URL back into the
> terminal) to cover this case; it is not in scope for this release.

## Disconnecting

```powershell
Disconnect-SPOServiceCrossPlatform
```

Clears `SPOService.CurrentService`.

## Compatibility

- PowerShell 7.6+
- macOS (tested on Darwin 25, arm64) and Linux (expected to work on the
  same runtime — please open an issue with your distro if not)
- `Microsoft.Online.SharePoint.PowerShell` 16.0.23408.12000 or newer

Windows is explicitly unsupported: importing this module on Windows
throws a terminating error. Windows users should keep using the stock
`Microsoft.Online.SharePoint.PowerShell` module and its native
`Connect-SPOService`.

### Supported auth flows

Supported in this release:

- certificate-based app-only auth
- system-browser interactive auth via `-UseSystemBrowser`

Not supported in this release:

- embedded-webview interactive auth
- username/password auth
- managed identity
- Azure Cloud Shell (no local browser / no reachable loopback listener;
  see the note under [Interactive system browser](#4-interactive-system-browser))

## Contributing

Issues and PRs welcome. The `docs/investigation/` folder is intentionally
preserved so future contributors have the full trace of root-cause
analysis: the IL inspector, the reflection-based bypass, the PnP bridge,
and the `ProcessQuery` direct helper are all there.

For a bug that looks module-specific (e.g. a particular SPO cmdlet still
fails after `Connect-SPOServiceCrossPlatform`), please include:

- exact PowerShell version (`$PSVersionTable.PSVersion`)
- SPO module version (`Get-Module Microsoft.Online.SharePoint.PowerShell -ListAvailable | Select Version`)
- full error, ideally with `$ErrorActionPreference = 'Stop'` and
  `-ErrorAction Stop`

## License

This project is licensed under the [MIT License](LICENSE).

It is an interoperability layer, not a fork. Runtime dependencies retain
their own licenses and are not bundled, redistributed, or modified by this
package — consumers install them via PSGallery as usual:

- [`Microsoft.Online.SharePoint.PowerShell`](https://www.powershellgallery.com/packages/Microsoft.Online.SharePoint.PowerShell)
  — Apache License 2.0 (ships the `Microsoft.SharePoint.Client.Runtime`
  CSOM assemblies referenced at build and load time).
- [`Microsoft.Identity.Client`](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet)
  (MSAL.NET) — MIT License (pulled in transitively via the SPO module;
  used for certificate-based app-only auth and token caching).

Under Apache License 2.0 § 1, a work that "remain[s] separable from, or
merely link[s] (or bind[s] by name) to the interfaces of, the Work" is
explicitly not a Derivative Work. `SPOService.CrossPlatform` binds to the
SPO module's interfaces by reflection and compile-time reference, copies
no Apache 2.0 source, and redistributes no Apache 2.0 binaries; it is
therefore not a Derivative Work under that definition. See the [`NOTICE`](NOTICE)
file for the full third-party attribution.

## Related upstream issue

- [`SharePoint/sp-dev-docs#9434`](https://github.com/SharePoint/sp-dev-docs/issues/9434)
  — open bug report covering `Connect-SPOService` failures on
  macOS / Linux.

---

<p align="center">
  <sub>An open source module published by</sub>
  <a href="https://nstop.app">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://nstop.app/img/wordmark-light.png">
      <img src="https://nstop.app/img/wordmark-dark.png" alt="nstop" height="18">
    </picture>
  </a>
</p>
