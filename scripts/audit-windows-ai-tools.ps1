#Requires -Version 5.1
<#
.SYNOPSIS
Read-only Windows inventory for AI and development command-line tools.

.PARAMETER KeepOnWindows
Command names to label keep. Supply a string array, for example:
  -KeepOnWindows codex,kiro-cli

.PARAMETER RemoveFromWindows
Command names to label remove. Supply a string array, for example:
  -RemoveFromWindows claude,opencode

.PARAMETER IncludeWinget
Include the complete winget inventory.

.NOTES
Known command names are inventory candidates and default to review. This script
does not remove or modify installed software.
#>
[CmdletBinding()]
param(
    [switch]$IncludeWinget,
    [string[]]$KeepOnWindows = @(),
    [string[]]$RemoveFromWindows = @()
)

$ErrorActionPreference = 'SilentlyContinue'

function Test-CommandName {
    param([string]$Name)

    return $Name -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

foreach ($name in @($KeepOnWindows + $RemoveFromWindows)) {
    if (-not (Test-CommandName $name)) {
        throw "Invalid command name '$name'. Use only letters, digits, dots, underscores, and hyphens."
    }
}

$overlap = @($KeepOnWindows | Where-Object { $RemoveFromWindows -contains $_ } | Sort-Object -Unique)
if ($overlap.Count -gt 0) {
    throw "A command cannot be both kept and removed: $($overlap -join ', ')"
}

# This is an inventory, not a default keep/remove policy.
$knownCommandNames = @(
    'codex', 'kiro', 'kiro-cli', 'claude', 'opencode', 'aider',
    'gemini', 'micode', 'crush', 'paseo', 'happy', 'happy-coder',
    'uipro', 'uipro-cli', 'agentic-hackathon', 'figma-mcp', 'gerrit-mcp',
    'playwright-cli', 'defuddle', 'feishu', 'feishu-mcp-pro', 'lark-cli',
    'ast-grep', 'git', 'gh', 'node', 'npm', 'npx', 'corepack', 'pnpm',
    'yarn', 'bun', 'uv', 'uvx', 'docker'
)

function Get-Policy {
    param([string]$Name)

    if ($keepOnWindows -contains $Name) {
        return 'keep'
    }
    if ($removeFromWindows -contains $Name) {
        return 'remove'
    }
    return 'review'
}

Write-Host '== Command resolution =='
$allCommandNames = @($knownCommandNames + $KeepOnWindows + $RemoveFromWindows) | Sort-Object -Unique
$commandRows = foreach ($name in $allCommandNames) {
    $matches = @(Get-Command $name -All -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 0) {
        [PSCustomObject]@{
            Name   = $name
            Policy = Get-Policy $name
            State  = 'absent'
            Path   = ''
        }
        continue
    }

    foreach ($match in $matches) {
        $resolvedPath = $match.Path
        if (-not $resolvedPath) {
            $resolvedPath = $match.Source
        }
        [PSCustomObject]@{
            Name   = $name
            Policy = Get-Policy $name
            State  = 'present'
            Path   = $resolvedPath
        }
    }
}
$commandRows | Sort-Object Policy, Name, Path | Format-Table -AutoSize

Write-Host "`n== Matching Appx packages =="
$packagePattern = 'Codex|Kiro|ChatGPT|Claude|OpenCode|Gemini|Paseo|Happy|Uipro|Crush'
$appxRows = @(Get-AppxPackage | Where-Object {
    $_.Name -match $packagePattern -or $_.PackageFullName -match $packagePattern
} | Select-Object Name, Version, PackageFullName)
if ($appxRows.Count -gt 0) {
    $appxRows | Format-Table -AutoSize
} else {
    Write-Host 'No matching Appx packages found.'
}

Write-Host "`n== Matching uninstall registrations =="
$uninstallRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$uninstallPattern = 'Codex|Kiro|ChatGPT|Claude|OpenCode|Gemini|MiCode|Crush|Paseo|Happy|UIPro|Feishu|Lark'
$uninstallRows = @(Get-ItemProperty $uninstallRoots | Where-Object {
    $_.DisplayName -match $uninstallPattern
} | Select-Object DisplayName, DisplayVersion, Publisher, PSPath)
if ($uninstallRows.Count -gt 0) {
    $uninstallRows | Sort-Object DisplayName | Format-Table -AutoSize
} else {
    Write-Host 'No matching uninstall registrations found.'
}

Write-Host "`n== npm shim residue =="
$npmBin = Join-Path $env:APPDATA 'npm'
$npmRows = @()
if (Test-Path -LiteralPath $npmBin) {
    $npmRows = @(Get-ChildItem -LiteralPath $npmBin -File | Where-Object {
        $allCommandNames -contains $_.BaseName
    } | Select-Object Name, Length, FullName)
}
if ($npmRows.Count -gt 0) {
    $npmRows | Sort-Object Name | Format-Table -AutoSize
} else {
    Write-Host 'No matching npm shims found.'
}

if ($IncludeWinget) {
    Write-Host "`n== winget inventory =="
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget list --accept-source-agreements
    } else {
        Write-Host 'winget is not available.'
    }
}

Write-Host "`nRead-only audit complete. All commands default to review; only explicit KeepOnWindows or RemoveFromWindows input changes the policy label. Verify each path and backup before uninstalling or deleting anything."
