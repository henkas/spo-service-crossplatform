# Native `OAuthSession` viability and interactive auth on `pwsh 7.6+`

Follow-up investigation after the original two-defect write-up in
[`01-root-cause.md`](01-root-cause.md) and
[`03-real-fix.md`](03-real-fix.md). The earlier docs established the two
upstream failures:

1. `SPOServiceHelper.InstantiateSPOService(...)` dereferences Windows-only
   registry roots on non-Windows.
2. `Microsoft.SharePoint.Client.Runtime` 16.0.0.0 sends empty POST bodies
   on .NET Core unless the transport is replaced.

What remained open was whether, once defect #2 was neutralized with the
`HttpClientExecutorFactory` shim, the native SPO auth/session model could
actually be used on macOS/Linux instead of a custom token-provider
closure.

This note captures that investigation and the resulting conclusion:

- native `OAuthSession` is viable on Unix
- certificate auth works through native `OAuthSession`
- interactive auth is blocked on `pwsh 7.5.x / .NET 9`
- interactive `-UseSystemBrowser` works on `pwsh 7.6.0 / .NET 10`
- the official SPO module still does **not** become natively usable on
  Unix by itself; the transport shim is still required

## Questions investigated

The investigation focused on six concrete questions.

### 1. Is native `OAuthSession` itself usable on Unix?

If the native cert-backed session object could be built and routed into a
shimmed `CmdLetContext`, then the abandoned reflection path in
[`02-journey.md`](02-journey.md) would be reclassified as a transport
failure, not an auth failure.

### 2. Is `OAuthSession` MSAL-backed or legacy ADAL?

If the native session already used MSAL internally, replacing the custom
closure with native `OAuthSession` would be an architectural alignment
exercise, not a move to a fundamentally different token stack.

### 3. Does `OAuthSession.GetAuthorizationHeaderValue()` refresh tokens?

If it only returned a stored token string, it would not buy much over the
existing custom closure. If it managed its own refresh lifecycle, the
native session model would be much more valuable.

### 4. Are there more Windows-only calls in the native auth/session path?

The original evidence only proved the registry dereference in
`InstantiateSPOService`. The question here was whether the reachable
`OAuthSession` path itself also contained hard Windows dependencies such
as registry, `WindowsIdentity`, DPAPI, `System.Management`, or CAPI/CNG
store assumptions.

### 5. Does native interactive auth fail because of SPO/MSAL design, or
because of the host runtime?

The original docs already noted that the default interactive path looked
Windows-centric. The missing detail was whether `UseSystemBrowser` was
actually impossible on macOS/Linux, or just blocked in the tested host.

### 6. Does any of this remove the need for the transport shim?

This was the architectural tie-breaker. If native auth started working on
Unix under a newer runtime, did that make this whole module obsolete, or
did the CSOM transport defect still force a repaired execution pipeline?

## Environment used

Investigation date: `2026-04-21`

Primary host:

- macOS Darwin 25.x, arm64
- `Microsoft.Online.SharePoint.PowerShell` `16.0.27111.12000`
- PowerShell `7.5.4` on `.NET 9.0.10`
- PowerShell `7.6.0` on `.NET 10.0.5`

The `7.6.0` host came from Homebrew at:

```text
/opt/homebrew/Cellar/powershell/7.6.0/bin/pwsh
```

## Static findings from IL / reflection

### `OAuthSession` constructor and method surface

Reflected members present in the SPO module assembly:

```text
Void .ctor(System.String)
Void .ctor(System.String, Boolean)
Void .ctor(System.String, System.Security.Cryptography.X509Certificates.X509Certificate2, System.String, System.String)

System.Threading.Tasks.Task SignIn(System.String)
Void SignIn(System.String, System.Management.Automation.PSCredential)
Void SignInWithCert(System.String)
System.String GetAuthorizationHeaderValue()
```

This was enough to support both candidate auth shapes needed by the
module:

- certificate auth:
  `OAuthSession(string authority, X509Certificate2 cert, string tenantId, string clientId)`
  + `SignInWithCert(string adminUrl)`
- interactive system-browser auth:
  `OAuthSession(string authority, bool useSystemBrowser)` +
  `SignIn(string adminUrl)`

### `OAuthSession` is MSAL-backed, not ADAL-backed

The reachable code path references `Microsoft.Identity.Client`
constructors/builders rather than
`Microsoft.IdentityModel.Clients.ActiveDirectory`.

Observed behavior from IL walk:

- public-client interactive auth goes through MSAL
  `AcquireTokenInteractive(...)`
- certificate auth goes through MSAL
  `AcquireTokenForClient(...)`
- username/password path goes through MSAL
  `AcquireTokenByUsernamePassword(...)`

Conclusion: native `OAuthSession` is already on MSAL. Rebuilding around it
does not mean switching token stacks; it means restoring the native SPO
session shape while keeping the custom transport fix.

### `GetAuthorizationHeaderValue()` refreshes tokens

The method is not just a trivial property getter. The reachable path
checks the cached token expiry and refreshes early.

Observed behavior:

- compares token expiry against roughly `ExpiresOn - 30 seconds`
- if token is stale or close to stale, calls the internal refresh path
- certificate path refreshes through MSAL client-credential flow
- interactive path refreshes through the native session cache/silent flow

Conclusion: native `OAuthSession` owns useful token lifecycle behavior.

### `SPOServiceHelper.IsTenantAdminSite(...)` is a real server round-trip

The method is not local parsing of the URL. It constructs a `Tenant`
object and calls `ExecuteQuery()`.

That matters because admin URL validation is not free: every connect that
uses it pays an extra CSOM round-trip before `SPOService.CurrentService`
is assigned.

### Native `Disconnect-SPOService` is minimal

The reflected native disconnect behavior only clears
`SPOService.CurrentService`. It does not revoke tokens, dispose a session
object, or tear down a custom socket/cache layer.

Conclusion: matching native disconnect semantics in this module is simply
to null that static property.

## Live cert-auth investigation

### Private-key certificate import works on macOS

The first practical blocker was whether `X509Certificate2` private-key
PFX import actually worked on the macOS host. That proved to be fine on
the user's machine. Certificate identifying fields are omitted:

```text
HasPrivateKey : True
```

That eliminated a major source of uncertainty: the native cert path was
not failing because of a broken cross-platform `X509Certificate2`
implementation.

### Native cert-backed `OAuthSession` works on macOS

Using reflection, the following sequence succeeded on macOS:

1. construct native cert-backed `OAuthSession`
2. call `SignInWithCert(adminUrl)`
3. construct `CmdLetContext`
4. install `HttpClientExecutorFactory`
5. assign the native `OAuthSession` onto the context
6. construct `SPOService`
7. assign `SPOService.CurrentService`
8. run `Get-SPOTenant`

`Get-SPOTenant` returned real tenant data.

This is the key result that reclassified the original reflection journey:
the session/auth model was not the blocker. The blocker in the earlier
attempt was the transport wall documented in [`03-real-fix.md`](03-real-fix.md).

### `CmdLetContext` has a client-tag length limit

An incidental native constraint surfaced during the cert smoke:

- a long custom `ClientTag` caused `CmdLetContext` constructor failure
- the failure surfaced as `ArgumentOutOfRangeException`
- appended custom tags of length `0..13` were accepted
- length `14+` failed on the tested build

The native implementation appears to append the custom client tag to an
existing base tag (`TAPS (16.0.27111.0)`), with an effective total length
cap around `32`.

This was not an auth defect, but it is worth documenting because it
looked like a session-construction failure at first.

## Interactive auth investigation

### `pwsh 7.5.4 / .NET 9.0.10`: blocked before browser auth starts

In the original host (`pwsh 7.5.4` on `.NET 9.0.10`), both of these
failed before any browser/UI decision mattered:

- plain `new CookieContainer()`
- plain `HttpClient` GET to login.microsoftonline.com
- native `OAuthSession(..., useSystemBrowser=$true).SignIn(...)`

The common failure was:

```text
System.InvalidOperationException: GetDomainName: -1
at Interop.Sys.GetDomainName()
at System.Net.CookieContainer.CreateFqdnMyDomain()
at System.Net.CookieContainer..cctor()
```

This was an important narrowing result:

- the failure was not SPO-specific
- the failure was not `OAuthSession`-specific
- the failure was not a browser-launch/UI problem
- the failure was a host/runtime-level networking issue

At that point, interactive auth was effectively impossible in the tested
`pwsh 7.5` host.

### Plain .NET 10 on the same machine did not have the blocker

A small .NET 10 console probe was created during the investigation and
run on the same machine. It succeeded with both:

```text
COOKIE_OK
HTTP_OK
```

That established the key differential:

- same machine
- same OS
- same network
- different runtime
- no CookieContainer failure

Conclusion: the blocker was specific to the tested PowerShell/.NET 9 host,
not an inherent limitation of macOS/Linux.

### `pwsh 7.6.0 / .NET 10.0.5`: native system-browser flow is viable

Under PowerShell `7.6.0`, the previous host-level blocker disappeared.

Observed results:

- `CookieContainer` creation succeeded
- plain `HttpClient` requests succeeded
- native `OAuthSession(string authority, bool useSystemBrowser)` could be
  constructed
- `SignIn(adminUrl)` no longer threw immediately
- while blocked inside `SignIn(...)`, the process opened a localhost
  listener on `::1:<port>`

That localhost listener is the expected MSAL loopback listener for
system-browser auth. It showed that the flow had progressed to the real
browser-callback wait state.

### Final proof: interactive browser flow completed successfully

The decisive end-to-end manual smoke was then run through the module
itself:

```powershell
Import-Module ./SPOService.CrossPlatform.psd1 -Force -ErrorAction Stop
Connect-SPOServiceCrossPlatform -Url https://contoso-admin.sharepoint.com -UseSystemBrowser
Get-SPOTenant | Select-Object -First 1 StorageQuota,SharingCapability | Format-List
```

Observed result: `Get-SPOTenant` completed successfully and returned tenant
properties. The captured quota and sharing-policy values are omitted.

That establishes the full chain:

- native system-browser `OAuthSession` starts on macOS
- the browser round-trip completes
- the resulting native SPO session is usable by official cmdlets
- the repaired transport still matters, because those cmdlets are running
  through the shimmed CSOM pipeline

## What this changed in the module

The findings above justified a significant architectural change in the
module for the `0.2.0` line.

### Before

The module:

- bypassed `InstantiateSPOService`
- installed the `HttpClientExecutorFactory`
- authenticated certificate-based app-only via a custom MSAL
  `ConfidentialClientApplication`
- injected bearer headers through `ExecutingWebRequest`

That was enough for the original release objective, but it did not restore
the native SPO session model and it could not support native interactive
auth.

### After

The module now:

- requires `PowerShell 7.6+`
- still bypasses `InstantiateSPOService`
- still installs `HttpClientExecutorFactory`
- constructs a native `OAuthSession`
- uses native `SignInWithCert()` for certificate auth
- uses native `SignIn()` with `-UseSystemBrowser` for interactive auth
- assigns the native `OAuthSession` directly onto `CmdLetContext`
- validates the admin URL before mutating `SPOService.CurrentService`
- keeps disconnect semantics aligned with native behavior by only clearing
  `SPOService.CurrentService`

This changes the role of the module:

- it is no longer a custom token-provider workaround
- it becomes a Unix-only shim around the native SPO session model
- the only layer it still truly owns is the transport repair

## Conclusions

### 1. Native `OAuthSession` is viable on Unix

This is a hard pass. The cert-backed path was proven through to
`Get-SPOTenant`, and the interactive system-browser path was proven
through a real browser round-trip to the same command result.

### 2. Interactive auth is not universally impossible on Unix

It is impossible in the tested `pwsh 7.5.4 / .NET 9.0.10` host, but not
because of SPO design. It works in `pwsh 7.6.0 / .NET 10.0.5`.

### 3. The official SPO package still does not just “start working”

Even under `pwsh 7.6`, the transport defect from
[`03-real-fix.md`](03-real-fix.md) still exists. Native auth viability
does **not** remove the need for the `HttpClientExecutorFactory` shim.

### 4. `-UseSystemBrowser` is the credible interactive contract on Unix

The default native embedded-webview path remains unproven and
Windows-centric. The viable Unix interactive story is:

- `PowerShell 7.6+`
- native `OAuthSession`
- system-browser flow only

### 5. Rebuilding around native `OAuthSession` buys real behavioral parity

This is not pure architectural purism:

- native token refresh behavior is reused
- native SPO session shape is preserved
- cmdlets that inspect or expect `Context.OAuthSession` are better served
  than they were by a pure bearer-token header injection closure

## Artifacts

- [`artifacts/Inspect-MethodIL.ps1`](artifacts/Inspect-MethodIL.ps1) —
  original IL dumper used to inspect reachable methods
- [`artifacts/Test-NativeOAuthSessionSmoke.ps1`](artifacts/Test-NativeOAuthSessionSmoke.ps1) —
  direct reflection-based native-session smoke helper added as part of this
  investigation

## Recommended follow-up documentation

If the root `README.md` stays intentionally user-focused, the main points
worth carrying out of this note are:

- `PowerShell 7.6+` is an intentional floor, not an arbitrary bump
- cert auth and `-UseSystemBrowser` are the supported auth shapes
- the module still exists because of the CSOM transport defect, even
  though native `OAuthSession` itself now works on Unix
