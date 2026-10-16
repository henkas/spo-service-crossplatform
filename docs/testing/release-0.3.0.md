# Release 0.3.0 manual verification

Manual, tenant-dependent checks run before tagging `0.3.0`. `0.3.0-rc1` was the
only published release candidate; the fixes for its two findings are verified
against a local build of the release branch rather than a second Gallery RC.
Automated CI already covers build, import, parameter binding, URL validation,
vendor-contract probing and packaging on macOS and Ubuntu; this file records
what CI cannot do: real authentication and real CSOM traffic.

**Sanitisation rule.** Record only what is listed under "Record". Never commit
tenant names, tenant or client IDs, admin URLs, certificate subjects or
thumbprints, usernames, quotas, site lists or any other tenant data. Use
`contoso` placeholders if an example is needed. The PR hygiene scan rejects
real `*.sharepoint.com` hosts and non-placeholder GUIDs, but it is a guard, not
a substitute for reading what you paste.

## Setup

Build the release branch and import it from the checkout in a fresh session
(the vendor module must already be installed, see Row 5 for the minimum):

```bash
git switch fix/rc2 && git pull
dotnet build -c Release src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj
pwsh
```

```powershell
Import-Module ./SPOService.CrossPlatform.psd1 -Force
(Get-Module SPOService.CrossPlatform).Version          # 0.3.0
(Get-Command Connect-SPOService).ResolvedCommand.Name   # Connect-SPOServiceCrossPlatform
```

Collect the environment facts once per machine:

```powershell
[System.Runtime.InteropServices.RuntimeInformation]::OSDescription
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$PSVersionTable.PSVersion
[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
(Get-Module Microsoft.Online.SharePoint.PowerShell -ListAvailable).Version
```

## Negative checks (no tenant needed, run first)

These take seconds and confirm the pre-auth boundary behaves on this machine.

| Check | Command | Expected |
| --- | --- | --- |
| Spoofed host refused | `Connect-SPOService -Url https://contoso-admin.sharepoint.com.example` | Error names the host only (no credentials or query echoed), mentions `https://<tenant>-admin.sharepoint.com`, no browser. The vendor module shows as loaded: `RequiredModules` imports it with ours, before any of our code runs |
| Headless guard | `$env:SSH_CONNECTION='x'; Remove-Item Env:DISPLAY,Env:WAYLAND_DISPLAY -EA 0; Connect-SPOService -Url https://contoso-admin.sharepoint.com` | Error mentions interactive sign-in and `-CertificatePath`; no browser opens. Then `Remove-Item Env:SSH_CONNECTION` |
| Tag too long | `Connect-SPOService -Url https://contoso-admin.sharepoint.com -ClientTag abcdefghijklmn` | Parameter validation error, 13-character limit |

## Matrix

Fill one block per row. Use a disposable lab tenant scope; never production or
employer resources. The reversible write must be something you can undo in the
same session (for example create and remove a test org-assets library, or set
and restore a harmless tenant property).

Read-only set:

```powershell
Get-SPOTenant | Select-Object -First 1 | Out-Null
Get-SPOSite -Limit 10 | Out-Null
Get-SPOOrgAssetsLibrary | Out-Null
Get-SPOUser -Site <a site you own> | Select-Object -First 1 | Out-Null
```

### Row 1: macOS arm64, current vendor, certificate auth (required)

```powershell
Connect-SPOService -Url <admin-url> -ClientId <id> -TenantId <id> -CertificatePath <pfx> -CertificatePassword (Read-Host -AsSecureString)
```

Record:

- OS/version, architecture: macOS 27.2.0, Arm64
- PowerShell version: 7.6.4
- Runtime (FrameworkDescription): .NET 10.0.10
- SPOService.CrossPlatform version: 0.3.0 (local build, commit: 075d9f2)
- Vendor module version loaded (`(Get-Module Microsoft.Online.SharePoint.PowerShell).Version`): 16.0.27709.12000
- Auth flow: certificate (PFX path), app-only with SharePoint `Sites.FullControl.All`
- Connect: pass
- Read-only cmdlets exercised and result: `Get-SPOTenant`, `Get-SPOSite -Limit 10`,
  `Get-SPOOrgAssetsLibrary`, `Get-SPOUser -Site <site URL>`: all pass
- Reversible write exercised, result, and confirmation it was undone:
  `Set-SPOTenant -ShowAllUsersClaim` flipped, read back flipped, restored, read
  back original: pass
- `Disconnect-SPOService` then a `Get-SPOTenant` fails as expected: pass ("No
  connection available")
- Sanitised error category/message, if any: none from the module. (`Get-SPOUser
  -Site` with a bare site name instead of a URL fails parameter binding in the
  vendor's `SpoSitePipeBind`; that is vendor input validation, not a defect.)
- Negative checks (same machine, vendor 16.0.27709.12000): spoofed host refused
  naming the host only, no browser: pass; headless guard refused and pointed at
  certificate auth: pass; 14-character `-ClientTag` rejected at binding: pass

### Row 2: macOS arm64, current vendor, system browser (required)

"Current vendor" is `16.0.27709.12000` or newer. That build changed the
system-browser `OAuthSession` constructor (it gained a trailing
`Action<string>`), so this row is the only end-to-end check of the new shape.

```powershell
Connect-SPOService -Url <admin-url>
```

Also confirm: browser opens, sign-in completes, control returns to the prompt, and a second Connect in the same session works after Disconnect.

Record: same fields as Row 1, auth flow "system browser (URL-only default)".

Ctrl+C check: start a URL-only Connect, then either press Ctrl+C or close the
browser without signing in. Expected: the prompt returns within about a second
(not after the vendor's 90-second timeout), `Get-SPOTenant` fails with no
connection, and the browser tab may remain until the vendor times out. Record:
pass / fail. (`0.3.0-rc1` failed this: the prompt was blocked for the full 90 s.)

Result (macOS 27.2.0 Arm64, PowerShell 7.6.4, .NET 10.0.10, vendor
16.0.27709.12000, local build commit d5df8a3):

- Browser sign-in: pass; `Get-SPOTenant` after connect: pass
- Second Connect in the same session after `Disconnect-SPOService`: pass
- Ctrl+C before signing in: prompt returned in about a second; `Get-SPOTenant`
  then failed with "No connection available": pass
- Sanitised error category/message, if any: none

### Row 3: Ubuntu x64, current vendor, certificate auth (required)

Same command as Row 1. Record the same fields. This is the first human-run
Linux authentication for the module; note anything surprising even if it passes.

Result: pass, reported by the maintainer as behaving exactly as on macOS. The
run was done separately and its outputs were not captured, so the per-field
record above is not available for this row.

### Row 4: Ubuntu x64, current vendor, system browser (if a desktop is available)

Same as Row 2 on a Linux desktop session. If only SSH is available, record
that the headless guard refused with the expected message and mark the row
"narrowed out: no desktop".

Result: pass, reported by the maintainer as behaving exactly as on macOS;
outputs not captured (same note as Row 3).

### Row 5: declared minimum vendor 16.0.26615.12013 (required, macOS or Ubuntu)

The connect cmdlet reuses whatever vendor version is already loaded if it meets
the floor, so load the minimum explicitly in a fresh session before connecting:

```powershell
Install-Module Microsoft.Online.SharePoint.PowerShell -RequiredVersion 16.0.26615.12013 -Scope CurrentUser -Force
Import-Module Microsoft.Online.SharePoint.PowerShell -RequiredVersion 16.0.26615.12013
Import-Module ./SPOService.CrossPlatform.psd1 -Force
Connect-SPOService -Url <admin-url> -ClientId <id> -TenantId <id> -CertificatePath <pfx> -CertificatePassword (Read-Host -AsSecureString)
Get-SPOTenant | Out-Null
Get-SPOSite -Limit 5 | Out-Null
```

Record: same fields as Row 1; vendor version must read 16.0.26615.12013.
Browser flow on this row is optional.

Result (macOS 27.2.0 Arm64, PowerShell 7.6.4, .NET 10.0.10, local build commit
d5df8a3):

- Vendor module version loaded: 16.0.26615.12013
- Auth flow: certificate (PFX path)
- Connect: pass; `Get-SPOTenant`: pass; `Get-SPOSite -Limit 5`: pass (the
  vendor's "more results were found" warning is expected with `-Limit`)
- `Disconnect-SPOService`: pass
- Sanitised error category/message, if any: none

## Result

- All required rows pass: yes (Rows 3 and 4 on the maintainer's report, outputs
  not captured)
- Defects found (link issues): none in manual testing. Found and fixed on the
  release branch before the run: vendor 16.0.27709.12000 changed the browser
  `OAuthSession` constructor; an older or stale shim DLL was not refused clearly.
- Decision: release 0.3.0
- Signed off by, date: Henki Papp, 2026-10-16

## Promotion steps (after sign-off)

1. Confirm `Prerelease = ''` in `SPOService.CrossPlatform.psd1` and the
   `## [0.3.0]` CHANGELOG date match the tagging day, commit the filled-in
   matrix above, and merge.
2. Tag `v0.3.0` on the merged commit and push; approve the `PSGallery Publishing`
   environment when the workflow pauses.
3. Confirm `Find-Module SPOService.CrossPlatform` shows 0.3.0 with the
   `Microsoft.Online.SharePoint.PowerShell >= 16.0.26615.12013` dependency.
4. Leave 0.2.0 listed. Its dependency-floor defect is documented in the CHANGELOG.
5. Confirm Zenodo archived the GitHub release and minted a version DOI with the
   metadata from `.zenodo.json` (title, creator ORCID, MIT licence). If it did
   not, check the repository's webhook delivery in Zenodo's GitHub settings.
