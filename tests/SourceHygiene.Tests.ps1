[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$check = Join-Path $repo 'build/Test-SourceHygiene.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('spo-hygiene-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
try {
    $fixture = Join-Path $testRoot 'example.md'
    # Compose forbidden examples so this test source itself stays clean.
    $cases = @(
        @{ Text = 'https://not-an-example-admin.' + 'sharepoint.com'; Rule = 'non-example tenant host' }
        @{ Text = 'not-an-example.' + 'onmicrosoft.com'; Rule = 'non-example tenant host' }
        @{ Text = [guid]::NewGuid().ToString(); Rule = 'non-placeholder identifier' }
        @{ Text = 'Thumbprint : ' + ('A' * 40); Rule = 'certificate thumbprint' }
        @{ Text = 'Subject : ' + 'CN=example'; Rule = 'certificate subject' }
        @{ Text = 'StorageQuota : ' + '12345'; Rule = 'captured tenant quota' }
        @{ Text = '-----BEGIN ' + 'PRIVATE KEY-----'; Rule = 'private key' }
        @{ Text = 'eyJ' + ('a' * 25) + '.example.example'; Rule = 'JWT-shaped token' }
    )
    $rejected = 0
    foreach ($extension in '.md', '.ps1') {
        $fixture = Join-Path $testRoot ("example$extension")
        foreach ($encoding in @([System.Text.UTF8Encoding]::new($false), [System.Text.Encoding]::Unicode, [System.Text.Encoding]::BigEndianUnicode)) {
            foreach ($case in $cases) {
                [IO.File]::WriteAllBytes($fixture, [byte[]]($encoding.GetPreamble() + $encoding.GetBytes("`n`n$($case.Text)")))
                $caught = $false
                try { & $check -Path $fixture } catch {
                    if ($_.Exception.Message -notmatch $case.Rule) { throw }
                    if ($_.Exception.Message -notmatch ':3:') { throw 'Hygiene diagnostics reported the wrong line.' }
                    if ($_.Exception.Message.Contains($case.Text)) { throw 'Hygiene diagnostics exposed the matched value.' }
                    $caught = $true
                }
                if (-not $caught) { throw "Hygiene check missed: $($case.Rule)" }
                $rejected++
            }
        }
    }
    Set-Content -LiteralPath $fixture -Value 'nonstop unstoppable https://contoso-admin.sharepoint.com https://contoso-my.sharepoint.com https://contoso-other-example.sharepoint.com https://contoso.onmicrosoft.com 00000000-0000-0000-0000-000000000000'
    & $check -Path $fixture
    $manifest = Join-Path $testRoot 'SPOService.CrossPlatform.psd1'
    $identity = [guid]::NewGuid().ToString()
    Set-Content -LiteralPath $manifest -Value "GUID = '$identity'"
    & $check -Path $manifest
    Set-Content -LiteralPath $manifest -Value "TenantId = '$identity'"
    $caught = $false
    try { & $check -Path $manifest } catch {
        if ($_.Exception.Message -notmatch 'non-placeholder identifier') { throw }
        $caught = $true
    }
    if (-not $caught) { throw 'Module identity exemption also exempted an auth-setting value.' }
    # Binary strings, regardless of alignment, are outside this source check.
    $dll = Join-Path $testRoot 'example.dll'
    [IO.File]::WriteAllBytes($dll, [byte[]](@(0) + [Text.Encoding]::Unicode.GetBytes('https://not-an-example-admin.' + 'sharepoint.com')))
    & $check -Path $dll
    Write-Information "Hygiene regression: $rejected encoded-text cases, GUID scope, examples and binary exclusion passed." -InformationAction Continue
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}

# Scan tracked files plus non-ignored additions, including dotfiles. Do not
# inspect ignored local credentials, .git, or build outputs during this pass.
$names = (& git -C $repo ls-files --cached --others --exclude-standard -z) -split "`0" | Where-Object { $_ }
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate repository files.' }
$files = @($names | Sort-Object -Unique | ForEach-Object { Join-Path $repo $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
& $check -Path $files
