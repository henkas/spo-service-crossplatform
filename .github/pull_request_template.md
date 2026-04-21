## Summary

<!-- 1–3 sentences: what this PR changes and why. -->

## Changes

<!-- Bullet list of user-visible changes. -->

-

## Verification

<!-- How you verified the change works. Include the commands you ran. -->

- [ ] `dotnet build -c Release src/SPOService.CrossPlatform/SPOService.CrossPlatform.csproj` succeeds
- [ ] `Import-Module ./SPOService.CrossPlatform.psd1` succeeds
- [ ] `Connect-SPOServiceCrossPlatform` still works against a real tenant (or: N/A for this PR)

## Related issues

<!-- Link any related issues. Use "Closes #N" to auto-close on merge. -->
