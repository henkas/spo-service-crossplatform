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

- PowerShell 7.6 on macOS or Linux.
- .NET 10 SDK.
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

Import/alias smoke-test (CI also runs the standalone contract scripts in
`tests/`; Pester adoption is planned separately):

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

1. Validates the tag against committed `ModuleVersion` and
   `PrivateData.PSData.Prerelease` before builds or environment approval.
2. Builds and smoke-tests on macOS and Ubuntu.
3. After protected-environment approval, builds the release shim and uses
   `build/Stage-Module.ps1` to copy the module unchanged and validate it.
4. Passes changelog notes directly to `Publish-Module -ReleaseNotes`,
   publishes to PSGallery, and attaches the DLL to the GitHub release.

Tags must be `vMAJOR.MINOR.PATCH[-PRERELEASE]`, with no leading zeros and
an alphanumeric prerelease suffix (for example, `v0.2.1-rc1`). Suffixes
are never silently normalized.

Before tagging, commit the numeric version in the source manifest. For an
RC, commit `Prerelease = 'rc1'`; clear it to `''` for stable. Promote
completed `Unreleased` notes to a dated `## [0.2.1-rc1]` or
`## [0.2.1]` section. The resolver prefers RC-specific notes and falls
back to the numeric section. Missing/blank notes remain empty; Gallery
uses the manifest's notes link and GitHub uses generated notes.

Contributors do not cut releases themselves; a maintainer owns tagging
and protected-environment approval.

Run the standalone, non-tenant checks after installing the vendor dependency:

```pwsh
./tests/ModuleContract.Tests.ps1
./tests/AdminUrl.Tests.ps1
./tests/ConnectBinding.Tests.ps1
./tests/StageModule.Tests.ps1
```

The release tests use synthetic shim bytes to check copying, version/tag
agreement, literal changelog notes, and cleanup after validation failure.
PSScriptAnalyzer runs separately in `.github/workflows/lint.yml` on pushes
and PRs, including `build/` and `tests/`.

After building the real shim, stage the currently committed version:

```pwsh
$candidateRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('spo-candidate-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $candidateRoot 'SPOService.CrossPlatform'
./build/Stage-Module.ps1 -OutputPath $stage
Import-Module (Join-Path $stage 'SPOService.CrossPlatform.psd1') -Force -ErrorAction Stop
```

Staging never changes the manifest or overwrites existing output. It validates
in a temporary sibling directory, cleans that directory on failure, and moves
it into place only on success, allowing the same output path to be retried.
Import is non-authenticating and does not load the shim until connection;
these checks do not replace native build or manual authentication testing.

## Source privacy checks

Run `./tests/SourceHygiene.Tests.ps1` to check tracked source files and
non-ignored additions, including hidden files and `docs/investigation/`.
The lint workflow runs it on PRs only; staging and binary artifacts do not
use this check. There is no organization-name blocklist.

Use `contoso` or `contoso-*` hosts (including `contoso-my.sharepoint.com`)
and all-zero or symbolic IDs in examples. GUID assignments in the module
manifest are exempt as module identity metadata; this is not a pinned-GUID
check. The scanner honors Unicode BOMs and reports locations/categories
without echoing values. Its rules cover recognizable tenant hosts, UUIDs,
certificate fields, private keys, JWT-shaped tokens, and captured quotas.
They do not prove arbitrary secrets are absent. Review documentation and
examples manually too; ignored local files and Git history are not scanned.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
