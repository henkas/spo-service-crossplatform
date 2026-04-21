# Defect #2 — CSOM pipeline sends empty request bodies on .NET Core

This is the second defect this module works around. The first is in
[`01-root-cause.md`](01-root-cause.md).

## Symptom

After bypassing defect #1 by any means (reflection-based SPOService
construction, or the PnP context), every CSOM call against SharePoint
Online still failed:

- `/_vti_bin/client.svc/ProcessQuery` → `ServerException: Invalid request.`
- `/_vti_bin/sites.asmx` → `400 Bad Request` with an HTML help page as
  the response body

Token, form digest, and URL were all valid — confirmed by POSTing the same
body via `Invoke-WebRequest` and getting `200 OK` from SharePoint.

## Root cause

`Microsoft.SharePoint.Client.Runtime.dll` version 16.0.0.0 (shipped with
`Microsoft.Online.SharePoint.PowerShell`) uses `HttpWebRequestExecutor`,
compiled against .NET Framework's `HttpWebRequest` pipeline. On .NET Core:

- The runtime calls `executor.GetRequestStream()` and writes the SOAP /
  CSOM XML body into it.
- The underlying `HttpWebRequest` compatibility shim on .NET Core does not
  flush that stream onto the wire.
- The request leaves the process with `Content-Length: 0` and an empty
  body.
- SharePoint rejects the empty body.

Proof, captured by pointing `ClientContext` at a local `HttpListener`:

```text
Method: POST
URL:    http://127.0.0.1:18087/_vti_bin/client.svc/ProcessQuery
ContentType: text/xml
Content-Length: 0
Body: (empty)
```

The same body, obtained from `PendingRequest.SetupQuery()` and POSTed with
`Invoke-WebRequest`, is accepted (200) and returns real CSOM responses.

This explains why:

- `PnP.PowerShell` works on macOS — it loads a newer
  `Microsoft.SharePoint.Client.Runtime` (16.1.x) that does not have the
  bug.
- [`Invoke-SPOBrandCenterDeactivation.ps1`](artifacts/Invoke-SPOBrandCenterDeactivation.ps1)
  works — it bypasses the runtime's HTTP pipeline entirely by reading the
  pending CSOM body out via reflection and POSTing it with
  `Invoke-WebRequest`.

## The shim

[`src/SPOService.CrossPlatform/HttpClientExecutor.cs`](../../src/SPOService.CrossPlatform/HttpClientExecutor.cs)
subclasses `Microsoft.SharePoint.Client.WebRequestExecutor` and routes
traffic through `HttpClient`:

- `GetRequestStream()` returns a `MemoryStream` wrapped so the runtime's
  `Close()` does not kill the buffer before `Execute()` runs.
- `Execute()` / `ExecuteAsync()` build an `HttpRequestMessage`, send the
  buffered body, and expose the response via `GetResponseStream()`.
- One compatibility quirk: the 16.0.0.0 runtime writes a body but does not
  always call the `RequestMethod` setter — it relied on `HttpWebRequest`
  auto-upgrading `GET` to `POST` when a body appears. The shim reproduces
  that upgrade so `sites.asmx` digest pre-fetches still succeed.

`HttpClientExecutorFactory` plugs into `ClientContext.WebRequestExecutorFactory`,
so every subsequent CSOM request goes through the replacement pipeline.

## How this is wired up

The PowerShell module (`Public/Connect-SPOServiceCrossPlatform.ps1`) combines the
two fixes into a single entry point:

- Skips `SPOServiceHelper.InstantiateSPOService` entirely by constructing
  `CmdLetContext` and `SPOService` directly via reflection (defect #1).
- Installs `HttpClientExecutorFactory` on the `CmdLetContext` (defect #2).
- Acquires tokens via MSAL `ConfidentialClientApplication` with a
  certificate; hooks `ExecutingWebRequest` to inject a fresh bearer on
  each request (MSAL's token cache handles expiry).
- Sets `SPOService.CurrentService`, so native cmdlets resolve it.

## Verified cmdlets

After `Connect-SPOServiceCrossPlatform`, the following official cmdlets were
observed running through the repaired pipeline against a real tenant:

- `Get-SPOTenant` — returns real tenant properties.
- `Get-SPOSite -Limit n` — returns real site collections.
- `Get-SPOOrgAssetsLibrary` — correctly reports the current state.
- `Get-SPOUser -Site … -Limit n` — returns real users.
- `Remove-SPOOrgAssetsLibrary` — reaches the server; real CSOM errors
  surface on bad IDs.

The broader cmdlet surface should work because every one of them funnels
through the same CSOM pipeline the shim repairs, but only the above were
exercised end-to-end.

## Recommended upstream fix

1. Gate the registry reads in `SPOServiceHelper.InstantiateSPOService` on
   `OperatingSystem.IsWindows()` — see
   [`01-root-cause.md`](01-root-cause.md).
2. Either retarget `Microsoft.SharePoint.Client.Runtime.dll` so its
   `HttpWebRequest` pipeline actually writes request bodies on .NET Core,
   or replace it with an `HttpClient`-based executor (what this module
   does out of process).
