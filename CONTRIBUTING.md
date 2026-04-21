# Contributing to SPOService.CrossPlatform

Thanks for your interest. This repo is deliberately small — it exists to
work around two specific defects in the vendor module
`Microsoft.Online.SharePoint.PowerShell`, not to re-implement SharePoint
cmdlets. Please read this file before opening a PR so we're aligned on
scope.

If you are reporting a **security** issue, follow [SECURITY.md](SECURITY.md)
instead of opening a public issue or PR.

## What belongs here

In scope:

- Fixes or hardening of `Connect-SPOServiceCrossPlatform` /
  `Disconnect-SPOServiceCrossPlatform`.
- Fixes to the native shim (`src/SPOService.CrossPlatform/`) —
  `HttpClientExecutor`, the factory, or the build machinery.
- Compatibility work for newer versions of the vendor module,
  `Microsoft.SharePoint.Client.Runtime`, MSAL, or .NET.
- Cross-platform bugs on macOS / Linux.
- Documentation, CI, and release-pipeline improvements.

Out of scope:

- New SharePoint cmdlets. The point of this module is that the native
  cmdlets (`Get-SPOTenant`, `Get-SPOSite`, …) work unmodified once our
  `Connect-*` replaces the broken native one. If a cmdlet is broken on
  macOS/Linux, investigate the shim before adding a cmdlet here.
- Windows support. The module deliberately refuses to load on Windows
  (see `SPOService.CrossPlatform.psm1`). Use the stock vendor module
  there.
- Features that don't have a concrete upstream defect behind them. When
  in doubt, open an issue first.

## Before proposing architectural changes

Read `docs/investigation/`. Several obvious alternatives — rewriting the
runtime, bridging via PnP, direct `ProcessQuery` — were already tried and
have documented trade-offs. Most "why not just …" answers live there.

## Development

Prerequisites:

- PowerShell 7.4+ on macOS or Linux.
- .NET 8 SDK.
- `Microsoft.Online.SharePoint.PowerShell` installed (the csproj resolves
  `Microsoft.SharePoint.Client.Runtime.dll` from it).

Install the SPO module if you don't have it:

```pwsh
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser
```

Build the native shim:

```bash
dotnet build -c Release src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj
```

If the csproj can't find the vendor runtime DLL, pass an explicit path:

```bash
dotnet build -c Release \
  /p:SpoRuntimePath=/abs/path/to/Microsoft.SharePoint.Client.Runtime.dll \
  src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj
```

Load the module locally:

```bash
pwsh -c 'Import-Module ./SPOService.CrossPlatform.psd1 -Force'
```

Smoke-test — the same checks CI runs; there is no test framework in this
repo:

```pwsh
Import-Module ./SPOService.CrossPlatform.psd1 -Force -ErrorAction Stop
Get-Command Connect-SPOServiceCrossPlatform, Disconnect-SPOServiceCrossPlatform
(Get-Command Connect-SPOService).ResolvedCommand.Name   # must end in CrossPlatform
```

End-to-end verification requires a tenant, an app registration with a
certificate, and a `.env` — keep those out of the repo.

## Style and conventions

- PowerShell files use `Set-StrictMode -Version Latest` and
  `$ErrorActionPreference = 'Stop'`. Keep new helpers compatible.
- Anything that touches vendor types (`CmdLetContext`, `SPOService`,
  `WebRequestExecutor`) goes through reflection — the types are
  `internal`/non-public and cannot be referenced at compile time from the
  PowerShell side.
- The C# project has `<Private>false</Private>` on the
  `Microsoft.SharePoint.Client.Runtime` reference on purpose. Do not
  redistribute that DLL. The build output is exactly one file:
  `SPOService.CrossPlatform.dll`.
- Run PSScriptAnalyzer locally before opening a PR:
  ```pwsh
  Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
  Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning
  ```
  CI runs the same check.

## Commits and pull requests

- Branch from `main`. One logical change per PR; unrelated cleanup belongs
  in a separate PR.
- Reference the issue being fixed in the PR body.
- Keep the PR description focused on *why*. Avoid narrating every file
  change — the diff already does that.
- The build matrix (`macos-latest`, `ubuntu-latest`) must stay green.
  CodeQL and PSScriptAnalyzer must be clean.
- If your change touches the HTTP shim, note whether you verified it
  against a real tenant (the CI smoke test does not cover wire traffic).

## Releases

Releases are tag-driven. Pushing a tag matching `v*` (e.g. `v0.2.0`) on
`main` triggers `.github/workflows/release.yml`, which:

1. Builds the shim with `/p:Version=<tag>`.
2. Stages the module, rewrites `ModuleVersion` in the `.psd1` from the
   tag.
3. Publishes to PSGallery (requires the `PSGALLERY_API_KEY` secret).
4. Attaches the built DLL to the GitHub release.

The tag format is strict semver: `vMAJOR.MINOR.PATCH[-PRERELEASE]`. A tag
that does not match is refused in the `Resolve version from tag` step.

Contributors do not cut releases themselves — open a PR, and a maintainer
will tag.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
