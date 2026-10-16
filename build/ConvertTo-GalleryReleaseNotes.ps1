<#
.SYNOPSIS
    Turns a Keep a Changelog section into plain text for the PowerShell Gallery.
.DESCRIPTION
    The Gallery shows a package's release notes verbatim: Markdown emphasis,
    code spans and headings appear as literal characters, and the changelog's
    hard wraps break lines mid-sentence. This keeps the structure and drops
    the markup: headings become "Heading:", each bullet and paragraph is one
    line, emphasis and code markers are removed, and [text](url) becomes
    "text (url)". The GitHub release keeps the original Markdown.
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Markdown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-Inline([string]$Text) {
    $Text = [regex]::Replace($Text, '\[([^\]]+)\]\(([^)\s]+)\)', '$1 ($2)')
    $Text = $Text -replace '\*\*(.+?)\*\*', '$1' -replace '__(.+?)__', '$1'
    $Text -replace '`+([^`]+?)`+', '$1'
}

function Get-Block([string]$Text) {
    $blocks = [System.Collections.Generic.List[string]]::new()
    $current = $null   # the bullet or paragraph being joined onto one line
    foreach ($line in ($Text -replace "`r`n", "`n") -split "`n") {
        $heading = [regex]::Match($line, '^#{1,6}[ \t]+(.+?)[ \t]*#*[ \t]*$')
        $bullet = [regex]::Match($line, '^[ \t]{0,3}[-*+][ \t]+(.*)$')
        $blank = [string]::IsNullOrWhiteSpace($line)
        if (($blank -or $heading.Success -or $bullet.Success) -and $null -ne $current) {
            $blocks.Add((Format-Inline $current))
            $current = $null
        }
        if ($blank) { $blocks.Add('') }
        elseif ($heading.Success) { $blocks.Add((Format-Inline $heading.Groups[1].Value) + ':') }
        elseif ($bullet.Success) { $current = '- ' + $bullet.Groups[1].Value.Trim() }
        elseif ($null -eq $current) { $current = $line.Trim() }
        else { $current = $current + ' ' + $line.Trim() }
    }
    if ($null -ne $current) { $blocks.Add((Format-Inline $current)) }
    $blocks
}

$blocks = @(Get-Block $Markdown)

# Collapse runs of blank lines and trim the ends.
(($blocks -join "`n") -replace "\n{3,}", "`n`n").Trim()
