#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$IncludeWinget
)

$ErrorActionPreference = 'SilentlyContinue'

$keepOnWindows = @(
    'codex',
    'kiro',
    'kiro-cli',
    'feishu',
    'feishu-mcp-pro',
    'lark-cli'
)

$removeFromWindows = @(
    'claude',
    'opencode',
    'gemini',
    'micode',
    'crush',
    'paseo',
    'happy',
    'happy-coder',
    'uipro',
    'uipro-cli',
    'agentic-hackathon',
    'figma-mcp',
    'gerrit-mcp',
    'playwright-cli',
    'defuddle'
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
$allCommandNames = @($keepOnWindows + $removeFromWindows) | Sort-Object -Unique
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
    $allNames = $keepOnWindows + $removeFromWindows
    $npmRows = @(Get-ChildItem -LiteralPath $npmBin -File | Where-Object {
        $allNames -contains $_.BaseName
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

Write-Host "`nRead-only audit complete. Verify each path and backup before uninstalling or deleting anything."
