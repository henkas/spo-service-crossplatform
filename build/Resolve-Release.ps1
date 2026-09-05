<#
.SYNOPSIS
    Validates a release tag against committed metadata and reads changelog notes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '../SPOService.CrossPlatform.psd1'),
    [string]$ChangelogPath = (Join-Path $PSScriptRoot '../CHANGELOG.md')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$pattern = '\Av(?<version>(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-(?<pre>[A-Za-z0-9]+))?\z'
$match = [regex]::Match($Tag, $pattern)
if (-not $match.Success) { throw 'Tag must be vMAJOR.MINOR.PATCH[-PRERELEASE], without leading zeros and with an alphanumeric suffix.' }
$version = $match.Groups['version'].Value
$pre = $match.Groups['pre'].Value
$data = Import-PowerShellDataFile -LiteralPath $ManifestPath
$manifestPre = if ($data.PrivateData.PSData.ContainsKey('Prerelease')) { [string]$data.PrivateData.PSData.Prerelease } else { '' }
if ($data.ModuleVersion -cne $version -or $manifestPre -cne $pre) {
    throw 'Tag does not match committed ModuleVersion and PSData.Prerelease. Update the source manifest before tagging.'
}

$lines = @(Get-Content -LiteralPath $ChangelogPath)
$notes = ''
foreach ($candidate in @($Tag.Substring(1), $version) | Select-Object -Unique) {
    $collect = $false
    $body = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -match '^##[ \t]+\[') {
            if ($collect) { break }
            $collect = $line -match ('^##[ \t]+\[' + [regex]::Escape($candidate) + '\]')
        } elseif ($collect) { $body.Add($line) }
    }
    $notes = ($body -join "`n").Trim()
    if (-not [string]::IsNullOrWhiteSpace($notes)) { break }
}
[pscustomobject]@{ Version = $version; Prerelease = $pre; IsPrerelease = [bool]$pre; ReleaseNotes = $notes }
