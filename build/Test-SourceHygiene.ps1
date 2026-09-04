<#
.SYNOPSIS
    Rejects recognizable tenant-data patterns in source text without printing values.
.DESCRIPTION
    Scans explicitly supplied files, including hidden files. This is a bounded
    regression guard, not proof that arbitrary secrets or tenant data are absent.
    Binary artifacts are excluded. Text decoding honors Unicode byte-order marks.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$guidPattern = '(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b'
$hostPattern = '(?i)(?<![a-z0-9.\-])(?<tenant>[a-z0-9][a-z0-9-]*)\.(?:sharepoint\.(?:com|us|de|cn)|onmicrosoft\.com)(?![a-z0-9])'
$rules = [ordered]@{
    'certificate thumbprint' = '(?im)^[ \t]*Thumbprint[ \t]*[:=][ \t]*[0-9a-f]{40,64}\b'
    'certificate subject' = '(?im)^[ \t]*Subject[ \t]*[:=][ \t]*CN='
    'captured tenant quota' = '(?im)^[ \t]*StorageQuota[ \t]*:[ \t]*[0-9]+'
    'private key' = ('-----BEGIN ' + '(?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----')
    'JWT-shaped token' = '\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'
}
$findings = [System.Collections.Generic.List[string]]::new()
$scanned = 0
foreach ($file in $Path) {
    $item = Get-Item -LiteralPath $file -Force
    if ($item.PSIsContainer) { throw 'Pass individual files to the hygiene check, not directories.' }
    if ($item.Extension -in '.dll', '.exe', '.pdb', '.png', '.jpg', '.gif', '.zip', '.nupkg') { continue }
    $scanned++
    # ReadAllText detects UTF-8/UTF-16/UTF-32 BOMs; BOM-less files use UTF-8.
    $content = [System.IO.File]::ReadAllText($item.FullName)
    foreach ($rule in $rules.GetEnumerator()) {
        foreach ($match in [regex]::Matches($content, $rule.Value)) {
            $line = 1 + [regex]::Matches($content.Substring(0, $match.Index), "`n").Count
            $findings.Add("$($item.Name):${line}: $($rule.Key)")
        }
    }
    foreach ($match in [regex]::Matches($content, $hostPattern)) {
        if ($match.Groups['tenant'].Value -notmatch '^contoso(?:-[a-z0-9-]+)?$') {
            $line = 1 + [regex]::Matches($content.Substring(0, $match.Index), "`n").Count
            $findings.Add("$($item.Name):${line}: non-example tenant host")
        }
    }
    foreach ($match in [regex]::Matches($content, $guidPattern)) {
        if ($match.Value -eq [guid]::Empty.ToString()) { continue }
        # Manifest GUID assignments are module identity metadata, not
        # auth settings. This exception deliberately does not pin a value.
        $lineStart = $content.LastIndexOf("`n", $match.Index) + 1
        $prefix = $content.Substring($lineStart, $match.Index - $lineStart)
        if ($item.Name -eq 'SPOService.CrossPlatform.psd1' -and $prefix -match '^[ \t]*GUID[ \t]*=[ \t]*''$') { continue }
        $line = 1 + [regex]::Matches($content.Substring(0, $match.Index), "`n").Count
        $findings.Add("$($item.Name):${line}: non-placeholder identifier")
    }
}
if ($findings.Count) {
    throw ("Source hygiene check failed (values omitted):`n" + (($findings | Select-Object -Unique) -join "`n"))
}
Write-Information "Source hygiene: $scanned text files passed." -InformationAction Continue
