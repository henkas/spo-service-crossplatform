# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/nstophq/spo-service-crossplatform/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nstophq/spo-service-crossplatform/releases/tag/v0.1.0
