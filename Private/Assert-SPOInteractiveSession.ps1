function Assert-SPOInteractiveSession {
    <#
    .SYNOPSIS
        Fails fast when system-browser sign-in cannot work in this session.
    .DESCRIPTION
        System-browser auth starts a loopback listener and opens a browser on
        this host. Interactive sign-in is the default when only -Url is given,
        so a script running over SSH, on a headless Linux box or in Azure Cloud
        Shell would otherwise hang until the sign-in times out. This check is
        deliberately conservative: it only refuses when the environment shows
        there is no display to open a browser on.

        Rules:
        - Azure Cloud Shell (ACC_CLOUD set): refuse; no local browser exists.
        - A display is present (DISPLAY or WAYLAND_DISPLAY): allow. This also
          covers SSH with X forwarding.
        - No display on Linux/FreeBSD: refuse.
        - No display on macOS: allow for a local terminal (macOS does not set
          DISPLAY), refuse inside an SSH session (SSH_CONNECTION/SSH_TTY set).

        Platform and Environment are parameters only so the rules can be unit
        tested; callers use the defaults.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Linux', 'OSX', 'FreeBSD', 'Windows')]
        [string]$Platform = $(
            if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) { 'OSX' }
            elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::FreeBSD)) { 'FreeBSD' }
            elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) { 'Windows' }
            else { 'Linux' }
        ),

        [hashtable]$Environment = $(
            $map = @{}
            foreach ($entry in Get-ChildItem Env:) { $map[$entry.Name] = $entry.Value }
            $map
        )
    )

    # Names of variables that are set to a non-blank value.
    $present = @($Environment.Keys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$Environment[$_]) })

    $reason = $null
    if ($present -contains 'ACC_CLOUD') {
        $reason = 'this is an Azure Cloud Shell session (ACC_CLOUD is set), which has no local browser'
    } elseif (-not ($present -contains 'DISPLAY' -or $present -contains 'WAYLAND_DISPLAY')) {
        $overSsh = $present -contains 'SSH_CONNECTION' -or $present -contains 'SSH_TTY' -or $present -contains 'SSH_CLIENT'
        if ($overSsh) {
            $reason = 'this is an SSH session with no forwarded display (SSH_CONNECTION/SSH_TTY set, DISPLAY not set)'
        } elseif ($Platform -ne 'OSX') {
            $reason = 'no DISPLAY or WAYLAND_DISPLAY is set, so there is no desktop to open a browser on'
        }
    }

    if ($reason) {
        throw "Interactive sign-in needs a local desktop session with a browser, but $reason. Interactive sign-in is the default when only -Url is given. For unattended or remote sessions use certificate auth: -ClientId, -TenantId and -CertificatePath (or -Certificate), or -UseEnvFile."
    }
}
