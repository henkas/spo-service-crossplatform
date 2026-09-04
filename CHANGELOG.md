# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Release staging now copies the manifest unchanged, preserving the SPO
  dependency floor at `16.0.23408.12000`. The `0.2.0`
  Gallery package incorrectly declared `0.2.0` as its dependency minimum
  because the release workflow replaced both assignments.
- Tags must match committed version and prerelease metadata before builds
  or publishing approval. Changelog notes are passed directly to publishing,
  avoiding manifest quoting problems. Failed staging cleans up its output.
- Removed identifying certificate fields and captured tenant properties from
  investigation notes; added source-only privacy checks for pull requests.

## [0.2.0] - 2026-04-22

Drops the hand-rolled MSAL token closure in favour of the vendor module's
own `OAuthSession`, and adds native interactive auth on macOS/Linux. The
module now only replaces the broken CSOM transport — authentication goes
through the official code path, which is what made interactive auth
reachable in the first place. Runtime floor raised to PowerShell 7.6 /
.NET 10.

### Added

- `-UseSystemBrowser` parameter set on `Connect-SPOServiceCrossPlatform`
  for interactive auth via the OS default browser. Calls the reflected
  `OAuthSession(authority, useSystemBrowser:$true)` ctor + `SignIn` and
  polls the returned `Task` so Ctrl+C escapes promptly. Embedded-webview
  interactive auth is intentionally still not supported.
- `Private/Assert-SupportedRuntime.ps1` — runtime floor guard called from
  both `psm1` import and the top of `Connect-*`, belt-and-braces with the
  manifest's `PowerShellVersion = '7.6'` so non-7.6 hosts fail fast with
  an actionable message instead of a late reflection error.
- `tests/ModuleContract.Tests.ps1` covering `Assert-SupportedRuntime`
  behaviour and the `Connect-*` parameter-set / shape contract (including
  the new `SystemBrowser` set), wired into build and release smoke jobs.
- `docs/investigation/04-native-session-and-interactive-auth.md` plus a
  smoke artifact, preserving the reasoning for the auth rework alongside
  the existing investigation trail.

### Changed

- Raised the supported runtime floor to `PowerShell 7.6 / .NET 10`.
  Previous `7.4 / net8.0` target is dropped; 0.2.0 will not import on
  7.4/7.5 hosts.
- Retargeted the native shim and packaged DLL layout from `net8.0` to
  `net10.0` to match the new floor. PSGallery layout now ships the shim
  under `bin/net10.0/`.
- Certificate-based auth now runs through the reflected native
  `OAuthSession` ctor + `SignInWithCert()` and is attached to
  `CmdLetContext.OAuthSession`. Token refresh/caching is handled by the
  native session instead of an MSAL cache we owned.
- Moved the authenticated `SPOServiceHelper.IsTenantAdminSite` check to
  **after** `OAuthSession` attachment. Pre-auth validation is now purely
  syntactic (`Test-SPOAdminUrlFormat`); the tenant-admin CSOM check still
  runs before `SPOService.CurrentService` is mutated, so non-admin URLs
  still fail without disturbing any prior connection.
- Hardened the `pwsh 7.6` installer action with SHA256 verification of
  the downloaded archive so CI cannot be silently poisoned by a bad
  mirror.
- Kept the native `HttpClientExecutor` shim as the sole transport repair
  layer — same GET→POST upgrade, `NonClosingStream` wrapping, and static
  `HttpClient` reuse as 0.1.0.

### Removed

- Custom MSAL `ConfidentialClientApplication` setup and the
  `ExecutingWebRequest` bearer-injection closure that 0.1.0 used to
  stitch tokens onto each CSOM call. The native `OAuthSession` does both
  jobs, and keeping our own token plumbing duplicated logic the vendor
  module already ships.
- `$script:TokenProvider` cache and the corresponding teardown in
  `Disconnect-SPOServiceCrossPlatform`. Disconnect now only clears
  `SPOService.CurrentService`; the native session owns its own lifetime.

## [0.1.0] - 2026-04-21

Initial release. Scope: PowerShell 7.4+ on macOS/Linux, certificate-based
app-only auth only.

### Added

- `Connect-SPOServiceCrossPlatform` function — cross-platform replacement
  for `Connect-SPOService` on PowerShell 7 / .NET 8 on macOS and Linux.
  Works around two defects in `Microsoft.Online.SharePoint.PowerShell` so
  the official SPO cmdlets run unmodified on the repaired CSOM pipeline.
- `Disconnect-SPOServiceCrossPlatform` function — clears
  `SPOService.CurrentService` and drops the cached token provider.
- `Connect-SPOService` and `Disconnect-SPOService` aliases — drop-in names
  matching the broken native cmdlets, so existing Windows-authored scripts
  work unchanged after importing this module.
- Native `SPOService.CrossPlatform.dll` shim (`HttpClientExecutor`,
  `HttpClientExecutorFactory`) replacing the SPO runtime's broken
  `HttpWebRequestExecutor` with an `HttpClient`-based executor.
- Certificate-based auth via MSAL `ConfidentialClientApplication` with
  automatic token refresh through MSAL's cache.
- Three parameter sets for credentials: explicit `CertificatePath`,
  preloaded `Certificate`, and convenience `.env` file loading.
- Import-time Windows rejection: the module refuses to load on Windows
  with a terminating error pointing users at the stock SPO module.
- Admin URL validation via
  `SPOServiceHelper.IsTenantAdminSite` before `SPOService.CurrentService`
  is mutated, so non-admin URLs (e.g. `https://contoso.sharepoint.com`)
  fail fast and leave any prior connection intact.

### Changed

- Declared `PowerShellVersion = '7.4'` in the manifest so it matches the
  `net8.0` target of the shipped shim DLL. (0.1.0 does not claim 7.2/7.3
  support; those runtimes ship .NET 6/7 and cannot load a `net8.0`
  assembly.)
- `Connect-SPOServiceCrossPlatform` no longer returns a diagnostic
  `pscustomobject` on success; matches the silent-success convention of
  the native `Connect-SPOService`.
- Native shim's static `HttpClient` now runs with `UseCookies = false`.
  CSOM is bearer-token authenticated and does not need cookie state; this
  also prevents the process-wide client from accumulating cross-session
  cookie state across reconnects.

[Unreleased]: https://github.com/henkas/spo-service-crossplatform/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/henkas/spo-service-crossplatform/releases/tag/v0.2.0
[0.1.0]: https://github.com/henkas/spo-service-crossplatform/releases/tag/v0.1.0
