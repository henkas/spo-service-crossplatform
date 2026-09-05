<#
    Standalone release tests. Requires the installed vendor dependency for
    Test-ModuleManifest; synthetic shim bytes do not test binary loadability.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$stageScript = Join-Path $repo 'build/Stage-Module.ps1'
$resolve = Join-Path $repo 'build/Resolve-Release.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('spo-release-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$script:passed = 0

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Failure {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected failure matching: $Pattern"
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:passed++
    Write-Information "PASS: $Name" -InformationAction Continue
}
try {
    $fixture = Join-Path $testRoot 'source'
    $null = New-Item -ItemType Directory -Path $fixture
    foreach ($item in 'SPOService.CrossPlatform.psm1', 'Public', 'Private', 'LICENSE', 'NOTICE', 'README.md', 'CHANGELOG.md') {
        Copy-Item -LiteralPath (Join-Path $repo $item) -Destination $fixture -Recurse
    }
    $manifest = Join-Path $fixture 'SPOService.CrossPlatform.psd1'
    $changelog = Join-Path $fixture 'CHANGELOG.md'
    $bin = Join-Path $fixture 'src/SPOService.CrossPlatform/bin/Release/net10.0'
    $null = New-Item -ItemType Directory -Path $bin -Force
    $shim = Join-Path $bin 'SPOService.CrossPlatform.dll'
    Set-Content -LiteralPath $shim -Value 'synthetic shim bytes'
    foreach ($version in '0.2.1', '9.8.7') {
        foreach ($pre in '', 'rc1') {
            Test-Case "$version prerelease='$pre': tag and unchanged staging" {
                # Fixture owns its version; no substitutions in a live manifest.
                $options = @{ Path = $manifest; RootModule = 'SPOService.CrossPlatform.psm1'; ModuleVersion = $version; Author = 'Example'; Description = 'Example'; RequiredModules = @(@{ ModuleName = 'Microsoft.Online.SharePoint.PowerShell'; ModuleVersion = '16.0.23408.12000' }) }
                if ($pre) { $options.Prerelease = $pre }
                New-ModuleManifest @options
                $tag = "v$version" + $(if ($pre) { "-$pre" })
                Set-Content -LiteralPath $changelog -Value "## [$version]`n`nNumeric notes.`n"
                $release = & $resolve -Tag $tag -ManifestPath $manifest -ChangelogPath $changelog
                Assert-Condition ($release.ReleaseNotes -ceq 'Numeric notes.') 'Notes gained whitespace.'
                $output = Join-Path $testRoot ("stage-$version-$pre/SPOService.CrossPlatform")
                & $stageScript -SourcePath $fixture -OutputPath $output
                $stagedManifest = Join-Path $output 'SPOService.CrossPlatform.psd1'
                Assert-Condition ((Get-FileHash $manifest).Hash -eq (Get-FileHash $stagedManifest).Hash) 'Manifest bytes changed.'
                $data = Import-PowerShellDataFile $stagedManifest
                Assert-Condition ($data.RequiredModules[0].ModuleVersion -eq '16.0.23408.12000') 'Dependency floor changed.'
                Assert-Condition ((Get-FileHash $shim).Hash -eq (Get-FileHash (Join-Path $output 'bin/net10.0/SPOService.CrossPlatform.dll')).Hash) 'Shim bytes changed.'
                Assert-Failure { & $stageScript -SourcePath $fixture -OutputPath $output } 'already exists'
                Assert-Condition (Test-Path $stagedManifest) 'Existing output was removed.'
            }
        }
    }
    Test-Case 'reject malformed tags and committed metadata mismatches' {
        foreach ($tag in 'v09.8.7', 'v9.08.7', 'v9.8.07', 'v9.8.7-rc.1', 'v9.8.7-', '9.8.7') {
            Assert-Failure { & $resolve -Tag $tag -ManifestPath $manifest -ChangelogPath $changelog } 'Tag must be'
        }
        foreach ($tag in 'v9.8.8-rc1', 'v9.8.7', 'v9.8.7-rc2') {
            Assert-Failure { & $resolve -Tag $tag -ManifestPath $manifest -ChangelogPath $changelog } 'does not match'
        }
    }
    Test-Case 'literal typographic quotes and RC notes override numeric notes' {
        $body = "Don$([char]0x2019)t rewrite $([char]0x2018)quoted$([char]0x2019) text or ASCII ' and `$variables."
        Set-Content -LiteralPath $changelog -Value "## [9.8.7-rc1]`n`n$body`n`n## [9.8.7]`nNumeric notes."
        $release = & $resolve -Tag v9.8.7-rc1 -ManifestPath $manifest -ChangelogPath $changelog
        Assert-Condition ($release.ReleaseNotes -ceq $body) 'Literal notes changed.'
    }
    Test-Case 'missing and empty final changelog sections return empty notes' {
        foreach ($text in @('## [Unreleased]', '## [9.8.7-rc1]', "## [9.8.7-rc1]`n `n")) {
            Set-Content -LiteralPath $changelog -Value $text
            $release = & $resolve -Tag v9.8.7-rc1 -ManifestPath $manifest -ChangelogPath $changelog
            Assert-Condition ($release.ReleaseNotes.Length -eq 0) 'Blank notes were not empty.'
        }
    }
    Test-Case 'validation failure cleans output and allows retry' {
        $output = Join-Path $testRoot 'retry/SPOService.CrossPlatform'
        $saved = Get-Content -LiteralPath $manifest -Raw
        $invalid = [regex]::Replace($saved, '(?m)^@\{', "@{`nRequiredAssemblies = @('missing-assembly.dll')")
        Set-Content -LiteralPath $manifest -Value $invalid -NoNewline
        Assert-Failure { & $stageScript -SourcePath $fixture -OutputPath $output } 'missing-assembly'
        Assert-Condition (-not (Test-Path $output)) 'Failed output remained.'
        Set-Content -LiteralPath $manifest -Value $saved -NoNewline
        & $stageScript -SourcePath $fixture -OutputPath $output
    }
    Test-Case 'missing input never creates output' {
        Remove-Item -LiteralPath $shim
        $output = Join-Path $testRoot 'missing/SPOService.CrossPlatform'
        Assert-Failure { & $stageScript -SourcePath $fixture -OutputPath $output } 'Required staging input'
        Assert-Condition (-not (Test-Path $output)) 'Missing input created output.'
    }
    Write-Information "Release contract: $script:passed cases passed." -InformationAction Continue
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
