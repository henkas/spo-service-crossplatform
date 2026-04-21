# Defect #1 — `Connect-SPOService` null registry dereference on non-Windows

Evidence for the first of two defects this module works around. The second
is documented in [`03-real-fix.md`](03-real-fix.md).

## Symptom

On PowerShell 7 / .NET Core on macOS or Linux:

```powershell
Connect-SPOService -Url https://<tenant>-admin.sharepoint.com
```

fails immediately with:

```text
Object reference not set to an instance of an object.
```

## Root cause

`Microsoft.Online.SharePoint.PowerShell.SPOServiceHelper.InstantiateSPOService(...)`
reads four Windows-only switches from the registry and does so without any
platform guard or null check. On .NET Core outside Windows,
`Microsoft.Win32.Registry.CurrentUser` and `LocalMachine` are both `null`,
so the first `OpenSubKey(...)` call throws.

Decompiled IL from the module assembly (reproduce with
[`artifacts/Inspect-MethodIL.ps1`](artifacts/Inspect-MethodIL.ps1)):

```text
IL_0020: ldsfld   Microsoft.Win32.RegistryKey CurrentUser
IL_0025: ldstr    "SOFTWARE\Microsoft\SPO\CMDLETS\"
IL_002a: callvirt Microsoft.Win32.RegistryKey OpenSubKey(System.String)
...
IL_0088: ldsfld   Microsoft.Win32.RegistryKey LocalMachine
IL_008d: ldstr    "SOFTWARE\Microsoft\SPO\CMDLETS\"
IL_0092: callvirt Microsoft.Win32.RegistryKey OpenSubKey(System.String)
```

No null check before either `OpenSubKey`. The registry values read are
`UseOrgID`, `ForceOAuth`, `UseAdalAuth` (from `HKCU`) and `UseSystemBrowser`
(from `HKLM`) — all Windows-only configuration.

Direct reproduction in PowerShell 7 on macOS:

```powershell
[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("SOFTWARE\Microsoft\SPO\CMDLETS\")
# → You cannot call a method on a null-valued expression.
```

## Secondary finding: interactive auth is Windows-centric

Even with the null-deref patched, the MSAL interactive path in
`OAuthSession.get_PublicClientApplication()` still uses
`https://oauth.spops.microsoft.com` as its redirect URI unless
`-UseSystemBrowser` is supplied, and forces the embedded web view
(`WithUseEmbeddedWebView(!useSystemBrowser)`). Per MSAL.NET guidance for
.NET Core and later, embedded web view is not available cross-platform by
default; system-browser flows require `http://localhost`. So the module's
non-`UseSystemBrowser` default cannot succeed on macOS/Linux.

This module avoids both by not calling `InstantiateSPOService` at all and
authenticating via `ConfidentialClientApplication` with a certificate
instead. Interactive auth is out of scope.

## Minimal upstream fix

Gate the registry reads on `OperatingSystem.IsWindows()` and null-check
each key:

```csharp
if (OperatingSystem.IsWindows())
{
    using var currentUser = Registry.CurrentUser?.OpenSubKey(@"SOFTWARE\Microsoft\SPO\CMDLETS\");
    if (currentUser != null)
    {
        _ = Convert.ToUInt32(currentUser.GetValue("UseOrgID", 0));
        if (!forceOAuth)
            forceOAuth = Convert.ToUInt32(currentUser.GetValue("ForceOAuth", 0)) > 0;
        useAdalAuth = Convert.ToUInt32(currentUser.GetValue("UseAdalAuth", 0)) > 0;
    }

    using var localMachine = Registry.LocalMachine?.OpenSubKey(@"SOFTWARE\Microsoft\SPO\CMDLETS\");
    if (localMachine != null)
    {
        useSystemBrowser |= Convert.ToUInt32(localMachine.GetValue("UseSystemBrowser", 0)) > 0;
    }
}
```

If Microsoft decides not to support macOS/Linux at all, the bare minimum is
still to replace the null reference with `PlatformNotSupportedException`.

## Environment where reproduced

- PowerShell 7.5.4
- macOS Darwin 25.2.0, arm64
- `Microsoft.Online.SharePoint.PowerShell` 16.0.27111.12000

## Upstream tracking

- [`SharePoint/sp-dev-docs#9434`](https://github.com/SharePoint/sp-dev-docs/issues/9434)
  — open since 2024-01-04. Microsoft's stated position (as of 2026-02-24) is
  that the SPO Management Shell is supported on Windows PowerShell 5.1 only.

## Relevant MSAL / SPO documentation

- [MSAL browser guidance](https://learn.microsoft.com/entra/msal/dotnet/acquiring-tokens/using-web-browsers)
- [`Connect-SPOService` reference](https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice)
- [SharePoint Management Shell intro](https://learn.microsoft.com/powershell/sharepoint/sharepoint-online/introduction-sharepoint-online-management-shell)
