# Security Policy

## Supported versions

Only the latest released version of `SPOService.CrossPlatform` on the
PowerShell Gallery receives security updates. Older versions will not be
patched — please upgrade before reporting an issue.

| Version | Supported |
| ------- | --------- |
| Latest release | :white_check_mark: |
| Older releases | :x: |

## Reporting a vulnerability

**Do not open a public GitHub issue for security reports.** Public issues
expose the vulnerability to every user of the module before a fix is
available.

Use one of the following channels, in order of preference:

1. **GitHub private vulnerability reporting** (preferred):
   [Report a vulnerability](https://github.com/nstophq/spo-service-crossplatform/security/advisories/new).
   This creates a private advisory that only the maintainers can see, and
   gives you a structured place to share a reproducer.

2. **Email**: `security@nstop.app`. Include "SPOService.CrossPlatform" in
   the subject line. PGP is available on request.

Please include, if you can:

- Affected version(s) of `SPOService.CrossPlatform`.
- The SharePoint / MSAL / .NET runtime versions on which you reproduced.
- A minimal proof-of-concept or steps to reproduce.
- Your assessment of impact (information disclosure, privilege escalation,
  denial of service, etc.).

## What to expect

- **Acknowledgement** within 3 business days.
- **Initial assessment** within 7 business days, including whether we can
  reproduce the issue and a rough severity.
- **Fix and coordinated disclosure**: we will work with you on a fix and
  on a disclosure timeline. The default is 90 days from acknowledgement,
  shorter for actively exploited issues, longer only if the fix has to
  cross a vendor boundary (e.g. the upstream
  `Microsoft.Online.SharePoint.PowerShell` module or
  `Microsoft.SharePoint.Client.Runtime`).
- **Credit** in the release notes and GitHub advisory, unless you prefer
  to stay anonymous.

## Scope

In scope:

- `Connect-SPOServiceCrossPlatform` / `Disconnect-SPOServiceCrossPlatform`
  and the private helpers in `Public/` and `Private/`.
- The native shim in `src/SPOService.CrossPlatform/` (the
  `HttpClientExecutor` and its factory).
- The PowerShell module manifest and build/release workflows.

Out of scope (please report upstream):

- Bugs in `Microsoft.Online.SharePoint.PowerShell` itself — report to
  Microsoft via the standard support channels.
- Bugs in `Microsoft.SharePoint.Client.Runtime` — same as above.
- Bugs in MSAL (`Microsoft.Identity.Client`) —
  <https://github.com/AzureAD/microsoft-authentication-library-for-dotnet>.
- Vulnerabilities that require the attacker to already have full control of
  the host on which the module runs (they can read the certificate, the
  `.env` file, or the MSAL token cache directly — this is not a module
  issue).

## Handling of secrets

`Connect-SPOServiceCrossPlatform` accepts a certificate (PFX path +
password, or an `X509Certificate2` object) and a client/tenant ID.

- The PFX password is accepted only as a `SecureString`.
- The `-UseEnvFile` path reads the password from a local `.env` file; this
  is a developer-ergonomics convenience and should never point at a file
  under source control. The `.env` loader deliberately does nothing fancy —
  no shell expansion, no network fetches — to keep the attack surface small.
- The module does not write the token, certificate, or password to disk or
  to any log. MSAL handles its own in-memory token cache.

If you find a path where any of the above is violated, that is a security
issue and we want to hear about it.
