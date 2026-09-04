<#
.SYNOPSIS
    Copies the module unchanged and validates the staged package.
.DESCRIPTION
    Version and prerelease metadata must be committed before tagging.
    Existing output is never overwritten. A temporary sibling directory is
    validated before moving into place and removed if validation fails.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SourcePath = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourcePath).Path
$stage = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $stage) { throw "OutputPath already exists: '$stage'." }

$manifestName = 'SPOService.CrossPlatform.psd1'
$sourceManifest = Join-Path $source $manifestName
$data = Import-PowerShellDataFile -LiteralPath $sourceManifest
$items = @($manifestName, $data.RootModule, 'Public', 'Private', 'LICENSE', 'NOTICE', 'README.md', 'CHANGELOG.md')
$shim = Join-Path $source 'src/SPOService.CrossPlatform/bin/Release/net10.0/SPOService.CrossPlatform.dll'
foreach ($path in (@($items | ForEach-Object { Join-Path $source $_ }) + $shim)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required staging input is missing: $path" }
}

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
    $null = Test-ModuleManifest -Path $stagedManifest -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $sourceManifest).Hash -ne (Get-FileHash -LiteralPath $stagedManifest).Hash) {
        throw 'Staging changed the manifest bytes.'
    }
    # A unique validation path also avoids PowerShell caching a previously
    # failed manifest when the caller fixes the source and retries.
    [IO.Directory]::Move($candidate, $stage)
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
Write-Information "Staged and validated unchanged module at $stage" -InformationAction Continue
