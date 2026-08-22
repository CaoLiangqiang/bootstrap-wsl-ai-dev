#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\configure-windows-terminal-ubuntu-theme.ps1'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('bootstrap-wsl-ai-dev-terminal-theme-test-' + [Guid]::NewGuid().ToString('N'))
$settingsPath = Join-Path $fixtureRoot 'settings.json'
$missingProfileSettingsPath = Join-Path $fixtureRoot 'missing-profile-settings.json'
$missingGuidSettingsPath = Join-Path $fixtureRoot 'missing-guid-settings.json'
$fragmentDirectory = Join-Path $fixtureRoot 'Fragments\bootstrap-wsl-ai-dev'
$fragmentPath = Join-Path $fragmentDirectory 'ubuntu-native.json'
$ubuntuGuid = '{2ebf61ae-6754-56c4-bea9-7b20dae8b785}'

function Fail {
    param([string]$Message)
    throw "FAIL: $Message"
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        Fail $Message
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) {
        Fail "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-Throws {
    param(
        [scriptblock]$ScriptBlock,
        [string]$ExpectedMessage,
        [string]$Message
    )

    $actualMessage = ''
    $matched = $false
    try {
        & $ScriptBlock
    } catch {
        $actualMessage = $_.Exception.Message
        $matched = $actualMessage -match $ExpectedMessage
    }
    Assert-True $matched "$Message. Actual error: $actualMessage"
}

function Invoke-ThemeScript {
    param(
        [string]$Action = 'Status',
        [string]$TerminalProfile = 'Ubuntu',
        [string]$TerminalSettingsPath = $settingsPath,
        [switch]$WhatIf
    )

    & $scriptPath -Action $Action -TerminalProfile $TerminalProfile `
        -WindowsTerminalSettingsPath $TerminalSettingsPath `
        -FragmentDirectory $fragmentDirectory -WhatIf:$WhatIf -Confirm:$false
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    @'
{
  "profiles": {
    "list": [
      {
        "guid": "{2ebf61ae-6754-56c4-bea9-7b20dae8b785}",
        "name": "Ubuntu",
        "source": "Microsoft.WSL",
        "startingDirectory": "~/codebase"
      },
      {
        "guid": "{58ad8d34-b1bd-5b91-8a85-5e19f302c76f}",
        "name": "Debian",
        "source": "Microsoft.WSL"
      }
    ]
  },
  "schemes": []
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    @'
{
  "profiles": {
    "list": [
      {
        "guid": "{58ad8d34-b1bd-5b91-8a85-5e19f302c76f}",
        "name": "Debian"
      }
    ]
  }
}
'@ | Set-Content -LiteralPath $missingProfileSettingsPath -Encoding UTF8
    @'
{
  "profiles": {
    "list": [
      {
        "name": "Ubuntu"
      }
    ]
  }
}
'@ | Set-Content -LiteralPath $missingGuidSettingsPath -Encoding UTF8

    $status = Invoke-ThemeScript -Action Status -TerminalSettingsPath (Join-Path $fixtureRoot 'missing-settings.json')
    Assert-True (-not $status.Present) 'status required Windows Terminal settings'
    Assert-True (-not $status.Owned) 'absent fragment was reported as owned'

    Assert-Throws -ExpectedMessage 'settings.json was not found' -Message 'install accepted missing Terminal settings' -ScriptBlock {
        Invoke-ThemeScript -Action Install -TerminalSettingsPath (Join-Path $fixtureRoot 'missing-settings.json') | Out-Null
    }
    Assert-Throws -ExpectedMessage 'Available profiles: Debian' -Message 'install accepted a missing Terminal profile' -ScriptBlock {
        Invoke-ThemeScript -Action Install -TerminalSettingsPath $missingProfileSettingsPath | Out-Null
    }
    Assert-Throws -ExpectedMessage 'does not expose a GUID' -Message 'install accepted a profile without a GUID' -ScriptBlock {
        Invoke-ThemeScript -Action Install -TerminalSettingsPath $missingGuidSettingsPath | Out-Null
    }

    Invoke-ThemeScript -Action Install -WhatIf | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $fragmentPath)) 'WhatIf created a Terminal fragment'

    $settingsHashBefore = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
    $installed = Invoke-ThemeScript -Action Install
    Assert-True $installed.Present 'install did not create a Terminal fragment'
    Assert-True $installed.Owned 'installed Terminal fragment was not recognized as owned'
    Assert-Equal $ubuntuGuid $installed.ProfileGuid 'installed fragment profile GUID'
    Assert-Equal $settingsHashBefore (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash 'install rewrote settings.json'

    $fragment = Get-Content -LiteralPath $fragmentPath -Raw | ConvertFrom-Json
    Assert-Equal 'Ubuntu Native' @($fragment.profiles)[0].colorScheme 'profile color scheme'
    Assert-Equal '#E95420' @($fragment.profiles)[0].tabColor 'profile tab color'
    Assert-Equal '#300A24' @($fragment.schemes)[0].background 'Ubuntu background color'
    Assert-Equal '#EEEEEC' @($fragment.schemes)[0].foreground 'Ubuntu foreground color'
    Assert-Equal '#EF2929' @($fragment.schemes)[0].brightRed 'Ubuntu bright red color'
    $fragmentBytes = [System.IO.File]::ReadAllBytes($fragmentPath)
    $hasUtf8Bom = $fragmentBytes.Length -ge 3 -and $fragmentBytes[0] -eq 0xEF -and
        $fragmentBytes[1] -eq 0xBB -and $fragmentBytes[2] -eq 0xBF
    Assert-True (-not $hasUtf8Bom) 'fragment was not written as BOM-less UTF-8'

    $fragmentHash = (Get-FileHash -LiteralPath $fragmentPath -Algorithm SHA256).Hash
    $secondInstall = Invoke-ThemeScript -Action Install
    Assert-True $secondInstall.Owned 'second install lost fragment ownership'
    Assert-Equal $fragmentHash (Get-FileHash -LiteralPath $fragmentPath -Algorithm SHA256).Hash 'second install changed an identical fragment'

    Set-Content -LiteralPath $fragmentPath -Value '{ "foreign": true }' -Encoding UTF8
    Assert-Throws -ExpectedMessage 'Refusing to overwrite unowned or modified' -Message 'install overwrote a foreign fragment' -ScriptBlock {
        Invoke-ThemeScript -Action Install | Out-Null
    }
    $removeWarnings = @()
    & $scriptPath -Action Remove -TerminalProfile Ubuntu `
        -WindowsTerminalSettingsPath $settingsPath -FragmentDirectory $fragmentDirectory `
        -WarningVariable removeWarnings -Confirm:$false | Out-Null
    Assert-True (Test-Path -LiteralPath $fragmentPath) 'remove deleted a foreign fragment'
    Assert-True (($removeWarnings -join "`n") -match 'leaving it unchanged') 'remove did not warn about a foreign fragment'

    Remove-Item -LiteralPath $fragmentPath -Force
    Invoke-ThemeScript -Action Install | Out-Null
    $siblingPath = Join-Path $fragmentDirectory 'keep.txt'
    Set-Content -LiteralPath $siblingPath -Value 'keep' -Encoding Ascii
    $removed = Invoke-ThemeScript -Action Remove
    Assert-True (-not $removed.Present) 'remove retained the owned fragment'
    Assert-True (Test-Path -LiteralPath $siblingPath -PathType Leaf) 'remove deleted an unrelated sibling file'
    Assert-True (Test-Path -LiteralPath $fragmentDirectory -PathType Container) 'remove deleted a non-empty fragment directory'

    Write-Host 'PASS: configure-windows-terminal-ubuntu-theme safely manages an isolated UTF-8 JSON fragment'
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
