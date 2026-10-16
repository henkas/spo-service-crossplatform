<#
.SYNOPSIS
    Copies the module and validates the staged package.
.DESCRIPTION
    Version and prerelease metadata must be committed before tagging.
    Existing output is never overwritten. A temporary sibling directory is
    validated before moving into place and removed if validation fails.

    Without -ReleaseNotesPath the manifest is copied byte for byte. With it,
    the staged manifest's single-line ReleaseNotes value is replaced by those
    notes as plain text (ConvertTo-GalleryReleaseNotes), because the
    PowerShell Gallery displays the notes from the packaged manifest, not
    from the nuspec. The staged manifest is then re-parsed and must equal the
    source in every other key, so nothing but ReleaseNotes can change.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SourcePath = (Join-Path $PSScriptRoot '..'),
    # Markdown changelog section (as written by Resolve-Release.ps1).
    [string]$ReleaseNotesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourcePath).Path
$stage = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $stage) { throw "OutputPath already exists: '$stage'." }

function ConvertTo-CanonicalJson($Value) {
    # Hashtables from Import-PowerShellDataFile have no stable key order.
    if ($Value -is [System.Collections.IDictionary]) {
        $sorted = [ordered]@{}
        foreach ($key in ($Value.Keys | Sort-Object)) { $sorted[$key] = ConvertTo-CanonicalJson $Value[$key] }
        return $sorted
    }
    if ($Value -is [array]) { return , @($Value | ForEach-Object { ConvertTo-CanonicalJson $_ }) }
    $Value
}
function Get-ComparableManifest([string]$Path) {
    $parsed = Import-PowerShellDataFile -LiteralPath $Path
    $parsed.PrivateData.PSData.Remove('ReleaseNotes')
    ConvertTo-CanonicalJson $parsed | ConvertTo-Json -Depth 20 -Compress
}
function Get-GalleryNote([string]$Path) {
    if (-not $Path) { return '' }
    $markdown = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
    & (Join-Path $PSScriptRoot 'ConvertTo-GalleryReleaseNotes.ps1') -Markdown $markdown
}
function Assert-StagedManifest([string]$Source, [string]$Staged, [string]$Notes) {
    $sameBytes = (Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Staged).Hash
    if (-not $Notes) {
        if (-not $sameBytes) { throw 'Staging changed the manifest bytes.' }
        return
    }
    $stagedNotes = (Import-PowerShellDataFile -LiteralPath $Staged).PrivateData.PSData.ReleaseNotes -replace "`r`n", "`n"
    if ($stagedNotes -cne ($Notes -replace "`r`n", "`n")) { throw 'Staged ReleaseNotes do not round-trip.' }
    if ((Get-ComparableManifest $Staged) -cne (Get-ComparableManifest $Source)) {
        throw 'Staging changed manifest keys other than ReleaseNotes.'
    }
}
function Write-StagedReleaseNote([string]$Path, [string]$Notes) {
    if ($Notes -match "(?m)^'@") { throw "Release notes contain a line starting with '@, which would end the manifest here-string." }
    $text = [IO.File]::ReadAllText($Path)
    $pattern = "(?m)^(?<lead>[ \t]*ReleaseNotes[ \t]*=[ \t]*)'(?:[^'\r\n]|'')*'[ \t]*(?=\r?$)"
    $found = [regex]::Matches($text, $pattern)
    if ($found.Count -ne 1) { throw "Expected exactly one single-line ReleaseNotes = '...' entry in the manifest; found $($found.Count)." }
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $body = ($Notes -replace "`r`n", "`n") -replace "`n", $nl
    $replacement = $found[0].Groups['lead'].Value + "@'" + $nl + $body + $nl + "'@"
    [IO.File]::WriteAllText($Path, $text.Remove($found[0].Index, $found[0].Length).Insert($found[0].Index, $replacement))
}

$manifestName = 'SPOService.CrossPlatform.psd1'
$sourceManifest = Join-Path $source $manifestName
$data = Import-PowerShellDataFile -LiteralPath $sourceManifest
$items = @($manifestName, $data.RootModule, 'Public', 'Private', 'LICENSE', 'NOTICE', 'README.md', 'CHANGELOG.md')
$shim = Join-Path $source 'src/SPOService.CrossPlatform/bin/Release/net10.0/SPOService.CrossPlatform.dll'
foreach ($path in (@($items | ForEach-Object { Join-Path $source $_ }) + $shim)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required staging input is missing: $path" }
}
$galleryNotes = Get-GalleryNote $ReleaseNotesPath

$parent = Split-Path -Parent $stage
$null = New-Item -ItemType Directory -Path $parent -Force
$scratch = Join-Path $parent ('.spo-stage-' + [guid]::NewGuid().ToString('N'))
$candidate = Join-Path $scratch 'SPOService.CrossPlatform'
try {
    $null = New-Item -ItemType Directory -Path $candidate -Force
    foreach ($item in $items) {
        Copy-Item -LiteralPath (Join-Path $source $item) -Destination $candidate -Recurse
    }
    $bin = Join-Path $candidate 'bin/net10.0'
    $null = New-Item -ItemType Directory -Path $bin -Force
    Copy-Item -LiteralPath $shim -Destination $bin
    $stagedManifest = Join-Path $candidate $manifestName
    if ($galleryNotes) { Write-StagedReleaseNote -Path $stagedManifest -Notes $galleryNotes }
    $null = Test-ModuleManifest -Path $stagedManifest -ErrorAction Stop
    Assert-StagedManifest -Source $sourceManifest -Staged $stagedManifest -Notes $galleryNotes
    # A unique validation path also avoids PowerShell caching a previously
    # failed manifest when the caller fixes the source and retries.
    [IO.Directory]::Move($candidate, $stage)
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
$what = if ($galleryNotes) { 'module (ReleaseNotes set from the changelog)' } else { 'unchanged module' }
Write-Information "Staged and validated $what at $stage" -InformationAction Continue
