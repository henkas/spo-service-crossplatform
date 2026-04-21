# Investigation

Evidence and intermediate workarounds for the two defects in
`Microsoft.Online.SharePoint.PowerShell` that this module works around.
Not required reading for users — the main `README.md` at the repo root
is. This folder exists so the claims in the root README can be verified
independently.

## Defect write-ups

- [`01-root-cause.md`](01-root-cause.md) — defect #1: the null Win32
  registry dereference in `SPOServiceHelper.InstantiateSPOService` that
  kills `Connect-SPOService` before auth runs on non-Windows. IL-level
  evidence and a minimal upstream patch sketch.

- [`03-real-fix.md`](03-real-fix.md) — defect #2: the 16.0.0.0
  `Microsoft.SharePoint.Client.Runtime`'s `HttpWebRequestExecutor` sends
  `Content-Length: 0` POSTs on .NET Core because the request stream
  never flushes. This is what kept CSOM calls failing with `Invalid request.`
  even after defect #1 was bypassed. Includes a local-HTTP-listener
  capture of the bad request.

- [`02-journey.md`](02-journey.md) — short log of the four intermediate
  approaches tried before the real fix (reflection bypass, PnP bridge,
  org-assets reimplementation, direct `ProcessQuery`). All now
  superseded by the shim; kept for context.

## Artifacts

Preserved under [`artifacts/`](artifacts/):

| Script | What it does |
|---|---|
| [`Inspect-MethodIL.ps1`](artifacts/Inspect-MethodIL.ps1) | Dumps IL for any method in a .NET assembly. Used to confirm the unconditional `Registry.CurrentUser.OpenSubKey(...)` in `InstantiateSPOService`. |
| [`Connect-SPOServiceMacWorkaround.ps1`](artifacts/Connect-SPOServiceMacWorkaround.ps1) | Reflection-based bypass of `InstantiateSPOService`. Got past defect #1; hit defect #2. |
| [`Connect-PnPSPOWorkaround.ps1`](artifacts/Connect-PnPSPOWorkaround.ps1) | Cert-based `Connect-PnPOnline` wrapper. PnP's newer SPC runtime is immune to defect #2, so this was the working auth path during the investigation. |
| [`SPOOrgAssetsMacWorkaround.ps1`](artifacts/SPOOrgAssetsMacWorkaround.ps1) | `Get-`/`Add-`/`Remove-SPOOrgAssetsLibrary` reimplemented on top of PnP's `ClientContext`, calling the underlying Tenant CSOM methods directly. |
| [`Invoke-SPOBrandCenterDeactivation.ps1`](artifacts/Invoke-SPOBrandCenterDeactivation.ps1) | Deactivates Brand Center by serializing the CSOM body via `ClientRequest.SetupQuery()` and POSTing it with `Invoke-WebRequest`, bypassing the runtime HTTP pipeline. Was necessary before the shim existed because PnP's 16.1.0.0 `Tenant` type does not expose `DeactivateBrandCenterFeatures()`. |

None of these are recommended for production use once the shim is in
place. Use the official SPO cmdlets after `Connect-SPOServiceCrossPlatform` instead.
