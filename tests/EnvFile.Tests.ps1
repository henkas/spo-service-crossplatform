<#
    .env handling contract. The file is opt-in (-UseEnvFile), read only from
    the explicitly selected path, and parsed literally: no variable expansion,
    no shell evaluation, no tilde expansion. No vendor module or tenant needed
    for the parser cases; the last case imports the module (vendor needed, as
    CI does) but never authenticates.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'Private/Get-LocalEnvMap.ps1')
$failures = [System.Collections.Generic.List[string]]::new()
$dir = Join-Path ([IO.Path]::GetTempPath()) ('spo-envfile-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $dir

try {
    $envPath = Join-Path $dir 'test.env'
    @(
        '# comment line'
        ''
        'ClientId = 00000000-0000-0000-0000-000000000000'
        'TenantId=00000000-0000-0000-0000-000000000000'
        'password=p=ss=word'
        'CertificatePath=$HOME/certs/app.pfx'
        'Tilde=~/app.pfx'
        'Percent=%USERPROFILE%\app.pfx'
        'Backtick=`$(whoami)'
        'Quoted="keep the quotes"'
        'no equals sign here'
        '   # indented comment'
    ) | Set-Content -LiteralPath $envPath

    $map = Get-LocalEnvMap -Path $envPath
    $expected = @{
        ClientId        = '00000000-0000-0000-0000-000000000000'
        TenantId        = '00000000-0000-0000-0000-000000000000'
        password        = 'p=ss=word'
        CertificatePath = '$HOME/certs/app.pfx'
        Tilde           = '~/app.pfx'
        Percent         = '%USERPROFILE%\app.pfx'
        Backtick        = '`$(whoami)'
        Quoted          = '"keep the quotes"'
    }
    foreach ($key in $expected.Keys) {
        if (-not $map.ContainsKey($key)) { $failures.Add("Missing key '$key'."); continue }
        if ($map[$key] -cne $expected[$key]) { $failures.Add("Key '$key' parsed as '$($map[$key])', expected literal '$($expected[$key])'.") }
    }
    if ($map.Count -ne $expected.Count) { $failures.Add("Parsed $($map.Count) keys, expected $($expected.Count); comments and lines without '=' must be skipped.") }

    try { Get-LocalEnvMap -Path (Join-Path $dir 'does-not-exist.env'); $failures.Add('Missing env file should throw.') }
    catch { if ($_.Exception.Message -notmatch 'not found.*does-not-exist\.env') { $failures.Add("Missing-file error should name the path; got: $($_.Exception.Message)") } }

    # Only the explicitly selected path is read: a .env in the working directory
    # must not be discovered when -EnvPath points elsewhere.
    Import-Module (Join-Path $repo 'SPOService.CrossPlatform.psd1') -Force
    $cwdEnv = Join-Path $dir '.env'
    'ClientId=should-not-be-read' | Set-Content -LiteralPath $cwdEnv
    Push-Location $dir
    try {
        $explicit = Join-Path $dir 'explicit-missing.env'
        try {
            Connect-SPOServiceCrossPlatform -Url 'https://contoso-admin.sharepoint.com' -UseEnvFile -EnvPath $explicit
            $failures.Add('Connect with a missing explicit env path should fail.')
        } catch {
            if ($_.Exception.Message -notmatch 'not found.*explicit-missing\.env') { $failures.Add("Explicit -EnvPath must be the only file consulted; got: $($_.Exception.Message)") }
        }
    } finally { Pop-Location }
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}

if ($failures.Count) { throw ("Env file contract failed:`n" + ($failures -join "`n")) }
Write-Information "Env file contract: $($expected.Count) literal values, comment/blank skipping, missing-file error, explicit path only." -InformationAction Continue
