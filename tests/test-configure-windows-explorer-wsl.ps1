#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\configure-windows-explorer-wsl.ps1'
$testRoot = 'HKCU:\Software\bootstrap-wsl-ai-dev-test-' + [Guid]::NewGuid().ToString('N')
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('bootstrap-wsl-ai-dev-test-' + [Guid]::NewGuid().ToString('N'))
$wslExecutable = Join-Path $fixtureRoot 'fake-wsl.cmd'
$terminalExecutable = Join-Path $fixtureRoot 'fake-wt.exe'
$settingsPath = Join-Path $fixtureRoot 'settings.json'
$missingProfileSettingsPath = Join-Path $fixtureRoot 'missing-profile-settings.json'
$unicodeWslExecutable = Join-Path $fixtureRoot 'fake-wsl-unicode.ps1'
$unicodeSettingsPath = Join-Path $fixtureRoot 'unicode-settings.json'
$ownerValueName = 'CodexBootstrapWslOwner'
$ownerValue = 'bootstrap-wsl-ai-dev/windows-explorer-wsl/v1'
$classicPath = $testRoot + '\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$preservedSnapshotPaths = @()

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

    $thrown = $false
    $actualMessage = ''
    try {
        & $ScriptBlock
    } catch {
        $actualMessage = $_.Exception.Message
        $thrown = $_.Exception.Message -match $ExpectedMessage
    }
    Assert-True $thrown "$Message. Actual error: $actualMessage"
}

function Invoke-MenuScript {
    param(
        [string]$Action = 'Status',
        [string]$Distribution = 'Ubuntu',
        [string]$TerminalProfile = 'Ubuntu',
        [string]$ClassicContextMenu = 'Keep',
        [string]$WslPath = $wslExecutable,
        [string]$TerminalPath = $terminalExecutable,
        [string]$TerminalSettingsPath = $settingsPath,
        [int]$FailAfterVerbCount = 0,
        [int]$FailAfterRegistryWriteCount = 0,
        [int]$FailAfterRegistryImportCount = 0,
        [switch]$Force,
        [switch]$RestartExplorer,
        [switch]$SkipPrerequisiteCheck
    )

    & $scriptPath -Action $Action -Distribution $Distribution -TerminalProfile $TerminalProfile `
        -ClassicContextMenu $ClassicContextMenu -RegistryClassesRoot $testRoot `
        -WslExecutable $WslPath -WindowsTerminalExecutable $TerminalPath `
        -WindowsTerminalSettingsPath $TerminalSettingsPath -FailAfterVerbCount $FailAfterVerbCount `
        -FailAfterRegistryWriteCount $FailAfterRegistryWriteCount `
        -FailAfterRegistryImportCount $FailAfterRegistryImportCount `
        -Force:$Force -RestartExplorer:$RestartExplorer -SkipPrerequisiteCheck:$SkipPrerequisiteCheck -Confirm:$false
}

function Get-RegistrySubtreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return '<absent>'
    }

    $nativePath = 'HKCU\' + $Path.Substring(6)
    $exportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('bootstrap-wsl-ai-dev-registry-' + [Guid]::NewGuid().ToString('N') + '.reg')
    try {
        & reg.exe export $nativePath $exportPath /y | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail "Unable to export registry path '$Path' for comparison."
        }
        return (Get-FileHash -LiteralPath $exportPath -Algorithm SHA256).Hash
    } finally {
        if (Test-Path -LiteralPath $exportPath) {
            Remove-Item -LiteralPath $exportPath -Force
        }
    }
}

function Clear-TestRegistryRoot {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

function New-StandardUnownedVerb {
    param([Parameter(Mandatory = $true)][string]$Path)

    New-Item -Path ($Path + '\command') -Force | Out-Null
    Set-Item -LiteralPath $Path -Value 'Legacy WSL command'
    Set-ItemProperty -LiteralPath $Path -Name 'Icon' -Value $wslExecutable -Type String
    Set-Item -LiteralPath ($Path + '\command') -Value 'legacy command'
}

try {
    New-Item -Path $fixtureRoot -ItemType Directory -Force | Out-Null
    Push-Location $fixtureRoot
    @(
        '@echo off',
        'echo Ubuntu'
    ) | Set-Content -LiteralPath $wslExecutable -Encoding Ascii
    Set-Content -LiteralPath $terminalExecutable -Value '' -Encoding Ascii
    @'
{
  "profiles": {
    "list": [
      { "name": "Ubuntu" }
    ]
  }
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    @'
{
  "profiles": {
    "list": [
      { "name": "Debian" }
    ]
  }
}
'@ | Set-Content -LiteralPath $missingProfileSettingsPath -Encoding UTF8
    $unicodeDistribution = 'Ubuntu 24.04 (' + [char]0x5f00 + [char]0x53d1 + ') & Tools'
    $unicodeTerminalProfile = [char]0x7ec8 + [char]0x7aef + ' (WSL) & Dev'
    $trailingBackslashTerminalProfile = $unicodeTerminalProfile + '\'
    @(
        'param([Parameter(ValueFromRemainingArguments = $true)]$Arguments)',
        '$global:LASTEXITCODE = 0',
        ("Write-Output '{0}'" -f $unicodeDistribution)
    ) | Set-Content -LiteralPath $unicodeWslExecutable -Encoding UTF8
    ([PSCustomObject]@{
        profiles = [PSCustomObject]@{
            list = @(
                [PSCustomObject]@{ name = $unicodeTerminalProfile },
                [PSCustomObject]@{ name = $trailingBackslashTerminalProfile }
            )
        }
    } | ConvertTo-Json -Depth 3) | Set-Content -LiteralPath $unicodeSettingsPath -Encoding UTF8

    $statusWithoutPrerequisites = @(
        Invoke-MenuScript -Action Status -WslPath (Join-Path $fixtureRoot 'missing-wsl.exe') `
            -TerminalPath (Join-Path $fixtureRoot 'missing-wt.exe') -TerminalSettingsPath (Join-Path $fixtureRoot 'missing-settings.json')
    )
    Assert-True ($statusWithoutPrerequisites.Count -eq 5) 'status required install prerequisites'

    Assert-Throws -ExpectedMessage 'WSL executable was not found' -Message 'install accepted a missing WSL executable' -ScriptBlock {
        Invoke-MenuScript -Action Install -WslPath (Join-Path $fixtureRoot 'missing-wsl.exe')
    }
    Assert-Throws -ExpectedMessage 'Windows Terminal executable was not found' -Message 'install accepted a missing Windows Terminal executable' -ScriptBlock {
        Invoke-MenuScript -Action Install -TerminalPath (Join-Path $fixtureRoot 'missing-wt.exe')
    }
    Assert-Throws -ExpectedMessage 'RegistryClassesRoot must be' -Message 'script accepted an arbitrary registry root' -ScriptBlock {
        & $scriptPath -Action Status -RegistryClassesRoot 'HKCU:\Software\not-an-owned-test-root'
    }
    Assert-Throws -ExpectedMessage 'SkipPrerequisiteCheck is available only' -Message 'live install accepted prerequisite bypass' -ScriptBlock {
        & $scriptPath -Action Install -SkipPrerequisiteCheck -WhatIf -Confirm:$false
    }
    Assert-Throws -ExpectedMessage 'FailAfterRegistryWriteCount is available only' -Message 'live install accepted registry write failure injection' -ScriptBlock {
        & $scriptPath -Action Install -FailAfterRegistryWriteCount 1 -WhatIf -Confirm:$false
    }
    Assert-Throws -ExpectedMessage 'FailAfterRegistryImportCount is available only' -Message 'live install accepted registry import failure injection' -ScriptBlock {
        & $scriptPath -Action Install -FailAfterRegistryImportCount 1 -WhatIf -Confirm:$false
    }
    Assert-Throws -ExpectedMessage 'Available distributions: Ubuntu' -Message 'install accepted a missing distribution' -ScriptBlock {
        Invoke-MenuScript -Action Install -Distribution Debian
    }
    Assert-Throws -ExpectedMessage 'Available profiles: Debian' -Message 'install accepted a missing Terminal profile' -ScriptBlock {
        Invoke-MenuScript -Action Install -TerminalSettingsPath $missingProfileSettingsPath
    }

    $restartWarning = @()
    & $scriptPath -Action Install -Distribution Ubuntu -TerminalProfile Ubuntu `
        -RegistryClassesRoot $testRoot -WslExecutable $wslExecutable `
        -WindowsTerminalExecutable $terminalExecutable -WindowsTerminalSettingsPath $settingsPath -RestartExplorer `
        -WarningVariable restartWarning -Confirm:$false
    Assert-True (($restartWarning -join "`n") -match 'not the live HKCU classes root') 'test root requested an Explorer restart'

    $targets = @(
        @{ Path = $testRoot + '\Directory\Background\shell'; Target = '%V' },
        @{ Path = $testRoot + '\Directory\shell'; Target = '%1' }
    )
    foreach ($target in $targets) {
        $wslKey = $target.Path + '\WSLUbuntu'
        $terminalKey = $target.Path + '\WSLUbuntuWindowsTerminal'
        Assert-True (Test-Path -LiteralPath $wslKey) "missing WSL verb at $wslKey"
        Assert-True (Test-Path -LiteralPath $terminalKey) "missing Windows Terminal verb at $terminalKey"
        Assert-Equal $ownerValue (Get-Item -LiteralPath $wslKey).GetValue($ownerValueName) "WSL verb ownership marker"
        Assert-Equal $ownerValue (Get-Item -LiteralPath $terminalKey).GetValue($ownerValueName) "Windows Terminal verb ownership marker"
        Assert-Equal $wslExecutable (Get-Item -LiteralPath $wslKey).GetValue('Icon') "WSL icon for $($target.Target)"
        Assert-Equal $terminalExecutable (Get-Item -LiteralPath $terminalKey).GetValue('Icon') "Windows Terminal icon for $($target.Target)"
        Assert-Equal 'Top' (Get-Item -LiteralPath $wslKey).GetValue('Position') "WSL position for $($target.Target)"
        Assert-Equal 'Top' (Get-Item -LiteralPath $terminalKey).GetValue('Position') "Windows Terminal position for $($target.Target)"
        Assert-Equal ('"' + $wslExecutable + '" -d "Ubuntu" --cd "' + $target.Target + '"') `
            (Get-Item -LiteralPath ($wslKey + '\command')).GetValue('') "WSL command for $($target.Target)"
        Assert-Equal ('"' + $terminalExecutable + '" -w new nt -p "Ubuntu" -d "' + $target.Target + '"') `
            (Get-Item -LiteralPath ($terminalKey + '\command')).GetValue('') "Windows Terminal command for $($target.Target)"
    }

    $beforeCommands = @($targets | ForEach-Object {
        (Get-Item -LiteralPath ($_.Path + '\WSLUbuntu\command')).GetValue('')
    })
    Invoke-MenuScript -Action Install
    $afterCommands = @($targets | ForEach-Object {
        (Get-Item -LiteralPath ($_.Path + '\WSLUbuntu\command')).GetValue('')
    })
    Assert-Equal ($beforeCommands -join "`n") ($afterCommands -join "`n") 'second install changed command values'

    Invoke-MenuScript -Action Remove
    foreach ($target in $targets) {
        Assert-True (-not (Test-Path -LiteralPath ($target.Path + '\WSLUbuntu'))) 'owned WSL verb was not removed'
        Assert-True (-not (Test-Path -LiteralPath ($target.Path + '\WSLUbuntuWindowsTerminal'))) 'owned Windows Terminal verb was not removed'
    }

    Assert-Throws -ExpectedMessage 'Injected failure after 2 Explorer verb writes' -Message 'injected install failure did not occur' -ScriptBlock {
        Invoke-MenuScript -Action Install -FailAfterVerbCount 2
    }
    foreach ($target in $targets) {
        Assert-True (-not (Test-Path -LiteralPath ($target.Path + '\WSLUbuntu'))) 'rollback retained a newly created WSL verb'
        Assert-True (-not (Test-Path -LiteralPath ($target.Path + '\WSLUbuntuWindowsTerminal'))) 'rollback retained a newly created Windows Terminal verb'
    }

    # Every mutation point must restore the registry tree, including intermediate keys.
    Clear-TestRegistryRoot
    $beforeNewVerbFailure = Get-RegistrySubtreeFingerprint -Path $testRoot
    foreach ($writeCount in 1..7) {
        Assert-Throws -ExpectedMessage ("Injected failure after $writeCount registry writes") -Message "new verb write phase $writeCount did not fail" -ScriptBlock {
            Invoke-MenuScript -Action Install -SkipPrerequisiteCheck -FailAfterRegistryWriteCount $writeCount
        }
        Assert-Equal $beforeNewVerbFailure (Get-RegistrySubtreeFingerprint -Path $testRoot) "new verb rollback changed the pre-run registry tree at write phase $writeCount"
    }

    Invoke-MenuScript -Action Install -SkipPrerequisiteCheck
    Set-ItemProperty -LiteralPath ($testRoot + '\Directory\Background\shell\WSLUbuntu') -Name 'PreservedOwnedValue' -Value 'before' -Type String
    $beforeOwnedVerbFailure = Get-RegistrySubtreeFingerprint -Path $testRoot
    foreach ($writeCount in 1..5) {
        Assert-Throws -ExpectedMessage ("Injected failure after $writeCount registry writes") -Message "owned verb write phase $writeCount did not fail" -ScriptBlock {
            Invoke-MenuScript -Action Install -SkipPrerequisiteCheck -FailAfterRegistryWriteCount $writeCount
        }
        Assert-Equal $beforeOwnedVerbFailure (Get-RegistrySubtreeFingerprint -Path $testRoot) "owned verb rollback changed the pre-run registry tree at write phase $writeCount"
    }

    $rollbackVerbPaths = @(
        ($testRoot + '\Directory\Background\shell\WSLUbuntu'),
        ($testRoot + '\Directory\Background\shell\WSLUbuntuWindowsTerminal'),
        ($testRoot + '\Directory\shell\WSLUbuntu'),
        ($testRoot + '\Directory\shell\WSLUbuntuWindowsTerminal')
    )
    foreach ($importCount in @(1, 3)) {
        Clear-TestRegistryRoot
        Invoke-MenuScript -Action Install -SkipPrerequisiteCheck
        $preRollbackCommands = @{}
        foreach ($path in $rollbackVerbPaths) {
            $preRollbackCommands[$path] = (Get-Item -LiteralPath ($path + '\command')).GetValue('')
        }
        $beforeBackupPaths = @(
            Get-ChildItem -LiteralPath $env:TEMP -Filter 'bootstrap-wsl-ai-dev-registry-*.reg' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName }
        )
        $rollbackError = ''
        try {
            Invoke-MenuScript -Action Install -SkipPrerequisiteCheck -FailAfterRegistryWriteCount 1 -FailAfterRegistryImportCount $importCount
            Fail "registry import failure $importCount did not occur"
        } catch {
            $rollbackError = $_.Exception.Message
        }
        $retainedBackupPaths = @(
            Get-ChildItem -LiteralPath $env:TEMP -Filter 'bootstrap-wsl-ai-dev-registry-*.reg' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName } | Where-Object { $beforeBackupPaths -notcontains $_ }
        )
        Assert-True ($retainedBackupPaths.Count -eq 1) "registry import failure $importCount did not retain exactly one backup"
        $preservedSnapshotPaths += $retainedBackupPaths
        $failedPath = $rollbackVerbPaths[$importCount - 1]
        Assert-True ($rollbackError -match [regex]::Escape($failedPath)) "registry import failure $importCount did not report its registry path"
        Assert-True ($rollbackError -match [regex]::Escape($retainedBackupPaths[0])) "registry import failure $importCount did not report its backup path"
        Assert-True (Test-Path -LiteralPath $retainedBackupPaths[0]) "registry import failure $importCount removed the retained backup"
        Assert-True (-not (Test-Path -LiteralPath $failedPath)) "registry import failure $importCount unexpectedly restored its failed subtree"
        foreach ($path in @($rollbackVerbPaths | Where-Object { $_ -cne $failedPath })) {
            Assert-True (Test-Path -LiteralPath $path) "registry import failure $importCount did not restore '$path'"
            Assert-Equal $preRollbackCommands[$path] (Get-Item -LiteralPath ($path + '\command')).GetValue('') "registry import failure $importCount changed '$path'"
        }
    }
    Clear-TestRegistryRoot

    Clear-TestRegistryRoot
    $forceAdoptionPath = $testRoot + '\Directory\Background\shell\WSLUbuntu'
    New-StandardUnownedVerb -Path $forceAdoptionPath
    $beforeForceAdoptionFailure = Get-RegistrySubtreeFingerprint -Path $testRoot
    foreach ($writeCount in 1..5) {
        Assert-Throws -ExpectedMessage ("Injected failure after $writeCount registry writes") -Message "forced adoption write phase $writeCount did not fail" -ScriptBlock {
            Invoke-MenuScript -Action Install -Force -SkipPrerequisiteCheck -FailAfterRegistryWriteCount $writeCount
        }
        Assert-Equal $beforeForceAdoptionFailure (Get-RegistrySubtreeFingerprint -Path $testRoot) "forced adoption rollback changed the pre-run registry tree at write phase $writeCount"
    }

    Clear-TestRegistryRoot
    $beforeClassicFailure = Get-RegistrySubtreeFingerprint -Path $testRoot
    foreach ($writeCount in 1..4) {
        Assert-Throws -ExpectedMessage ("Injected failure after $writeCount registry writes") -Message "classic context menu write phase $writeCount did not fail" -ScriptBlock {
            Invoke-MenuScript -Action Status -ClassicContextMenu Enable -FailAfterRegistryWriteCount $writeCount
        }
        Assert-Equal $beforeClassicFailure (Get-RegistrySubtreeFingerprint -Path $testRoot) "classic context menu rollback changed the pre-run registry tree at write phase $writeCount"
    }

    New-Item -Path ($classicPath + '\InprocServer32') -Force | Out-Null
    Set-Item -LiteralPath ($classicPath + '\InprocServer32') -Value ''
    $beforeClassicAdoptionFailure = Get-RegistrySubtreeFingerprint -Path $testRoot
    Assert-Throws -ExpectedMessage 'Injected failure after 1 registry writes' -Message 'classic context menu adoption write phase did not fail' -ScriptBlock {
        Invoke-MenuScript -Action Status -ClassicContextMenu Enable -Force -FailAfterRegistryWriteCount 1
    }
    Assert-Equal $beforeClassicAdoptionFailure (Get-RegistrySubtreeFingerprint -Path $testRoot) 'classic context menu adoption rollback changed the pre-run registry tree'
    Clear-TestRegistryRoot

    $collisionPath = $testRoot + '\Directory\shell\WSLUbuntu'
    New-Item -Path $collisionPath -Force | Out-Null
    Set-ItemProperty -LiteralPath $collisionPath -Name 'MUIVerb' -Value 'Unowned command' -Type String
    Assert-Throws -ExpectedMessage 'Refusing to overwrite unowned Explorer verb' -Message 'install did not refuse an unowned collision' -ScriptBlock {
        Invoke-MenuScript -Action Install
    }
    Set-ItemProperty -LiteralPath $collisionPath -Name 'ForeignValue' -Value 'keep' -Type String
    Assert-Throws -ExpectedMessage 'contains values or subkeys outside a standard shell verb' -Message 'forced install adopted a verb containing foreign data' -ScriptBlock {
        Invoke-MenuScript -Action Install -Force
    }
    Remove-Item -LiteralPath $collisionPath -Recurse -Force

    New-Item -Path ($collisionPath + '\command') -Force | Out-Null
    Set-Item -LiteralPath $collisionPath -Value 'Legacy WSL command'
    Set-ItemProperty -LiteralPath $collisionPath -Name 'Icon' -Value $wslExecutable -Type String
    Set-Item -LiteralPath ($collisionPath + '\command') -Value 'legacy command'
    Invoke-MenuScript -Action Install -Force
    Assert-Equal $ownerValue (Get-Item -LiteralPath $collisionPath).GetValue($ownerValueName) 'forced install did not adopt a standard shell verb'
    Invoke-MenuScript -Action Remove
    Assert-True (-not (Test-Path -LiteralPath $collisionPath)) 'remove did not delete the safely adopted verb'

    Invoke-MenuScript -Action Status -ClassicContextMenu Enable | Out-Null
    Assert-True (Test-Path -LiteralPath $classicPath) 'classic context menu key was not created'
    Assert-Equal $ownerValue (Get-Item -LiteralPath $classicPath).GetValue($ownerValueName) 'classic context menu ownership marker'
    Assert-Equal '' (Get-Item -LiteralPath ($classicPath + '\InprocServer32')).GetValue('') 'classic context menu InprocServer32 default value'
    Set-ItemProperty -LiteralPath $classicPath -Name 'UnrelatedValue' -Value 'keep' -Type String
    Assert-Throws -ExpectedMessage 'Refusing to rewrite owned classic context menu key' -Message 'classic Enable rewrote an unsafe owned key' -ScriptBlock {
        Invoke-MenuScript -Action Status -ClassicContextMenu Enable
    }
    Assert-Equal 'keep' (Get-Item -LiteralPath $classicPath).GetValue('UnrelatedValue') 'classic Enable changed unexpected data'
    Invoke-MenuScript -Action Status -ClassicContextMenu Disable | Out-Null
    Assert-True (Test-Path -LiteralPath $classicPath) 'classic context menu disable removed unexpected values'
    Remove-ItemProperty -LiteralPath $classicPath -Name 'UnrelatedValue'
    Invoke-MenuScript -Action Status -ClassicContextMenu Disable | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $classicPath)) 'classic context menu key was not removed'

    New-Item -Path ($classicPath + '\InprocServer32') -Force | Out-Null
    Set-Item -LiteralPath ($classicPath + '\InprocServer32') -Value ''
    Assert-Throws -ExpectedMessage 'Refusing to overwrite unowned classic context menu key' -Message 'classic Enable adopted an unowned key without Force' -ScriptBlock {
        Invoke-MenuScript -Action Status -ClassicContextMenu Enable
    }
    Invoke-MenuScript -Action Status -ClassicContextMenu Enable -Force | Out-Null
    Assert-Equal $ownerValue (Get-Item -LiteralPath $classicPath).GetValue($ownerValueName) 'classic Enable did not adopt an exact safe unowned key'
    Invoke-MenuScript -Action Status -ClassicContextMenu Disable | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $classicPath)) 'classic context menu did not remove adopted safe key'

    New-Item -Path ($classicPath + '\InprocServer32\ForeignChild') -Force | Out-Null
    Assert-Throws -ExpectedMessage 'not the exact safe classic context-menu shape' -Message 'classic Enable adopted an unsafe unowned key with Force' -ScriptBlock {
        Invoke-MenuScript -Action Status -ClassicContextMenu Enable -Force
    }
    Remove-Item -LiteralPath $classicPath -Recurse -Force

    Invoke-MenuScript -Action Install -Distribution $unicodeDistribution -TerminalProfile $unicodeTerminalProfile `
        -WslPath $unicodeWslExecutable -TerminalSettingsPath $unicodeSettingsPath
    $unicodeWslCommand = (Get-Item -LiteralPath ($testRoot + '\Directory\Background\shell\WSLUbuntu\command')).GetValue('')
    $unicodeTerminalCommand = (Get-Item -LiteralPath ($testRoot + '\Directory\Background\shell\WSLUbuntuWindowsTerminal\command')).GetValue('')
    $quote = [string][char]34
    $backslash = [string][char]92
    Assert-Equal ($quote + $unicodeWslExecutable + $quote + ' -d ' + $quote + $unicodeDistribution + $quote + ' --cd ' + $quote + '%V' + $quote) $unicodeWslCommand 'Unicode WSL distribution command was not safely quoted'
    Assert-Equal ($quote + $terminalExecutable + $quote + ' -w new nt -p ' + $quote + $unicodeTerminalProfile + $quote + ' -d ' + $quote + '%V' + $quote) $unicodeTerminalCommand 'Unicode Windows Terminal profile command was not safely quoted'

    Invoke-MenuScript -Action Install -Distribution $unicodeDistribution -TerminalProfile $trailingBackslashTerminalProfile `
        -WslPath $unicodeWslExecutable -TerminalSettingsPath $unicodeSettingsPath
    $trailingBackslashCommand = (Get-Item -LiteralPath ($testRoot + '\Directory\Background\shell\WSLUbuntuWindowsTerminal\command')).GetValue('')
    Assert-Equal ($quote + $terminalExecutable + $quote + ' -w new nt -p ' + $quote + $trailingBackslashTerminalProfile + $backslash + $quote + ' -d ' + $quote + '%V' + $quote) $trailingBackslashCommand 'Windows Terminal profile ending in a backslash was not argv-safe'

    Assert-Throws -ExpectedMessage 'Distribution must not contain quotes or control characters' -Message 'install accepted a quoted distribution name' -ScriptBlock {
        Invoke-MenuScript -Action Install -Distribution 'Ubuntu" -e cmd' -SkipPrerequisiteCheck
    }
    Assert-Throws -ExpectedMessage 'TerminalProfile must not contain quotes or control characters' -Message 'install accepted a control character in a Terminal profile name' -ScriptBlock {
        Invoke-MenuScript -Action Install -TerminalProfile ('Ubuntu' + [char]1) -SkipPrerequisiteCheck
    }

    $status = @(Invoke-MenuScript -Action Status)
    Assert-True ($status.Count -eq 5) 'status did not report all verbs and the classic context menu state'
    Write-Host 'PASS: configure-windows-explorer-wsl validates prerequisites and safely manages only owned test registry keys'
} finally {
    Pop-Location -ErrorAction SilentlyContinue
    foreach ($snapshotPath in $preservedSnapshotPaths) {
        if (Test-Path -LiteralPath $snapshotPath) {
            Remove-Item -LiteralPath $snapshotPath -Force
        }
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
