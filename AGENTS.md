# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A PowerShell 7 module (`SPOService.CrossPlatform`) plus a small C#/.NET 10 native shim that makes the official `Microsoft.Online.SharePoint.PowerShell` cmdlets work on macOS and Linux. It is a workaround for two defects in the vendor module — nothing in this repo re-implements SharePoint cmdlets. The public surface is just `Connect-SPOServiceCrossPlatform` and `Disconnect-SPOServiceCrossPlatform` (exported as `Connect-SPOService` / `Disconnect-SPOService` aliases that shadow the broken native cmdlets).

## Commands

Build the native shim (required before `Import-Module` works):

```bash
dotnet build -c Release src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj
```

The csproj has an `InitialTarget` that globs for `Microsoft.SharePoint.Client.Runtime.dll` in standard PowerShell module paths. If it can't find the SPO module (e.g. on a clean CI), either `Install-Module Microsoft.Online.SharePoint.PowerShell` first or pass `/p:SpoRuntimePath=/abs/path/to/Microsoft.SharePoint.Client.Runtime.dll`.

Load the module locally:

```bash
pwsh -c 'Import-Module ./SPOService.CrossPlatform.psd1 -Force'
```

Import/alias smoke-test (CI also runs standalone contract scripts in `tests/`):

```bash
pwsh -c '
  Import-Module ./SPOService.CrossPlatform.psd1 -Force -ErrorAction Stop
  Get-Command Connect-SPOServiceCrossPlatform, Disconnect-SPOServiceCrossPlatform
  # aliases must resolve to the *CrossPlatform functions, not the broken native cmdlets
  (Get-Command Connect-SPOService).ResolvedCommand.Name
'
```

Build matrix (`.github/workflows/build.yml`) runs on macos-latest and ubuntu-latest. Release (`release.yml`) fires on `v*` tags, validates the tag against committed version/prerelease metadata before approval, stages the manifest unchanged with `Public/`, `Private/`, psd1/psm1, and the built DLL under `bin/net10.0/`, and publishes to PSGallery + attaches the DLL to the GitHub release. Changelog notes are passed directly to `Publish-Module -ReleaseNotes`.

## Architecture

Three layers cooperate through reflection and runtime monkey-patching of types owned by the vendor module:

**1. PowerShell entry point — `Public/Connect-SPOServiceCrossPlatform.ps1`**

The flow is load-sensitive and must stay in this order:

1. `Get-SPOModuleReflection` imports `Microsoft.Online.SharePoint.PowerShell`, loads its MSAL DLL, and reflects out the internal `CmdLetContext`, `OAuthSession`, `SPOService`, and `SPOServiceHelper` types (throws with an actionable message if any are missing from the installed SPO module).
2. `Assert-NativeShim` locates and `Add-Type`s the built `SPOService.CrossPlatform.dll`. It probes `bin/net10.0/` first (PSGallery install layout), then `src/.../bin/Release|Debug/net10.0/` (dev layout).
3. `New-SPOCmdletContext` constructs `CmdLetContext` **via reflection** on its non-public `(string, PSHost, string)` ctor — calling the normal factory goes through `SPOServiceHelper.InstantiateSPOService` which null-derefs `Microsoft.Win32.Registry.CurrentUser` on non-Windows. It also sets `context.WebRequestExecutorFactory` to the shim so all CSOM traffic routes through the HttpClient-based transport.
4. An `OAuthSession` is built via the vendor module's own auth path: `New-SPOCertificateOAuthSession` calls the reflected `OAuthSession(authority, cert, tenantId, clientId)` ctor + `SignInWithCert`; `New-SPOSystemBrowserOAuthSession` calls the `OAuthSession(authority, useSystemBrowser=$true)` ctor + `SignIn` and polls the returned `Task` via `Wait-SPOAuthenticationTask` so Ctrl+C escapes promptly. There is no custom MSAL client and no `$script:TokenProvider`; refresh/caching is handled by the native session.
5. The authenticated `OAuthSession` is assigned to `context.OAuthSession` via reflection, then `Assert-SPOAdminSite` runs the vendor's `IsTenantAdminSite` CSOM check (pre-auth validation is syntactic only via `Test-SPOAdminUrlFormat`). `SPOService` is reflection-constructed from the patched context, and the static `SPOService.CurrentService` property is assigned so the official cmdlets (`Get-SPOTenant`, `Get-SPOSite`, …) pick it up transparently.

**2. Native shim — `src/SPOService.CrossPlatform/HttpClientExecutor.cs`**

Subclasses `Microsoft.SharePoint.Client.WebRequestExecutor` and replaces the stock `HttpWebRequestExecutor` (which on .NET Core silently sends `Content-Length: 0` on CSOM POSTs). Key invariants worth preserving:

- `GetRequestStream()` returns a `NonClosingStream` wrapper — the SPC runtime calls `Close/Dispose` on the returned stream before `Execute()` runs, which would otherwise kill the backing `MemoryStream`.
- `RunAsync` has an **implicit GET→POST upgrade**: if method is GET but a body was written, it rewrites to POST. The runtime's `sites.asmx` digest pre-fetch relies on this; don't remove it.
- `HttpClient` is a single static instance (connection reuse).
- The `WebRequest` property returns a detached, never-executed `HttpWebRequest` purely so callers that read its properties don't NPE — the real wire call is always `HttpClient`.

**3. psd1/psm1 module glue**

`SPOService.CrossPlatform.psm1` dot-sources `Private/` then `Public/` under `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`, then declares `Connect-SPOService` / `Disconnect-SPOService` as aliases. PowerShell command resolution puts aliases above cmdlets, so the aliases shadow the broken native cmdlets of the same name in any session where both modules are loaded. The `.psd1` declares `Microsoft.Online.SharePoint.PowerShell` as a `RequiredModules` dependency so PSGallery pulls it in transitively.

## Conventions

- Both PowerShell files use `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` — keep new helpers compatible.
- Anything that pokes at vendor types (`CmdLetContext`, `SPOService`, `WebRequestExecutor`) goes through reflection because these are internal/non-public. Don't try to reference them at compile time from the PowerShell side.
- The C# project intentionally has `<Private>false</Private>` on the `Microsoft.SharePoint.Client.Runtime` reference — we do **not** redistribute that DLL. `dotnet build` output is a single `SPOService.CrossPlatform.dll`.
- `docs/investigation/` is preserved deliberately (IL inspector traces, reflection bypass notes, PnP bridge attempt, `ProcessQuery` direct helper). Consult it before proposing architectural changes — most "why not just …" alternatives were already tried.
- CI runs standalone PowerShell contract scripts under `tests/` plus import/alias checks. Pester adoption is planned separately.
