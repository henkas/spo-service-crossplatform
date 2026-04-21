# SPOService.CrossPlatform

[![build](https://github.com/nstophq/spo-service-crossplatform/actions/workflows/build.yml/badge.svg)](https://github.com/nstophq/spo-service-crossplatform/actions/workflows/build.yml)
[![PSGallery](https://img.shields.io/powershellgallery/v/SPOService.CrossPlatform)](https://www.powershellgallery.com/packages/SPOService.CrossPlatform)
[![PSGallery downloads](https://img.shields.io/powershellgallery/dt/SPOService.CrossPlatform)](https://www.powershellgallery.com/packages/SPOService.CrossPlatform)
[![License](https://img.shields.io/github/license/nstophq/spo-service-crossplatform)](LICENSE)

**macOS / Linux only.** Cross-platform replacement for `Connect-SPOService`
that lets the official
[`Microsoft.Online.SharePoint.PowerShell`](https://learn.microsoft.com/powershell/sharepoint/sharepoint-online/introduction-sharepoint-online-management-shell)
cmdlets run unmodified on **PowerShell 7 / .NET 8 on macOS and Linux**.
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

Requires PowerShell 7.4+, .NET 8 SDK, and the SPO module installed (the
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

Authentication uses MSAL's `ConfidentialClientApplication` with an app
registration and a certificate. The app needs **`Sites.FullControl.All`**
(application permission) on the `Office 365 SharePoint Online` API.
Admin consent required.

Three ways to provide credentials:

### 1. Explicit certificate path (default)

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

Token refresh is automatic: MSAL caches tokens, and the executor re-asks on
every request, so expired tokens are transparently replaced.

## Disconnecting

```powershell
Disconnect-SPOServiceCrossPlatform
```

Clears `SPOService.CurrentService` and drops the cached token provider.

## Compatibility

- PowerShell 7.4+ (the shipped shim targets `net8.0`, matching the .NET 8
  runtime bundled with `pwsh` 7.4)
- macOS (tested on Darwin 25, arm64) and Linux (expected to work on the
  same .NET 8 runtime — please open an issue with your distro if not)
- `Microsoft.Online.SharePoint.PowerShell` 16.0.23408.12000 or newer

Windows is explicitly unsupported: importing this module on Windows
throws a terminating error. Windows users should keep using the stock
`Microsoft.Online.SharePoint.PowerShell` module and its native
`Connect-SPOService`.

### Supported auth flows

Only certificate-based app-only authentication is supported in this
release, via MSAL's `ConfidentialClientApplication`. Interactive,
credential, and managed-identity flows exposed by the native
`Connect-SPOService` are not wired up here yet.

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

[MIT](LICENSE). The module links against Microsoft-owned assemblies
(`Microsoft.SharePoint.Client.Runtime.dll` and friends) at runtime but does
not redistribute them — install them via `Microsoft.Online.SharePoint.PowerShell`
as usual.

## Related upstream issue

- [`SharePoint/sp-dev-docs#9434`](https://github.com/SharePoint/sp-dev-docs/issues/9434)
  — open bug report covering `Connect-SPOService` failures on
  macOS / Linux.
