#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Install', 'Remove', 'Status')]
    [string]$Action = 'Status',

    [string]$Distribution = 'Ubuntu',

    [string]$TerminalProfile = 'Ubuntu',

    [ValidateSet('Keep', 'Enable', 'Disable')]
    [string]$ClassicContextMenu = 'Keep',

    [switch]$RestartExplorer,

    [string]$RegistryClassesRoot = 'HKCU:\Software\Classes',

    [string]$WslExecutable,

    [string]$WindowsTerminalExecutable,

    [string]$WindowsTerminalSettingsPath,

    [switch]$SkipPrerequisiteCheck,

    [ValidateRange(0, 2147483647)]
    [int]$FailAfterVerbCount = 0,

    [ValidateRange(0, 2147483647)]
    [int]$FailAfterRegistryWriteCount = 0,

    [ValidateRange(0, 2147483647)]
    [int]$FailAfterRegistryImportCount = 0,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ownerValueName = 'CodexBootstrapWslOwner'
$ownerValue = 'bootstrap-wsl-ai-dev/windows-explorer-wsl/v1'
$classicClsid = '{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$liveRegistryClassesRoot = 'HKCU:\Software\Classes'
$isTestRegistryRoot = $RegistryClassesRoot -match '^HKCU:\\Software\\bootstrap-wsl-ai-dev-test-[A-Fa-f0-9]+$'

if ($RegistryClassesRoot -ne $liveRegistryClassesRoot -and -not $isTestRegistryRoot) {
    throw "RegistryClassesRoot must be '$liveRegistryClassesRoot' or an isolated bootstrap-wsl-ai-dev test root."
}
if ($SkipPrerequisiteCheck -and -not $isTestRegistryRoot) {
    throw '-SkipPrerequisiteCheck is available only with an isolated bootstrap-wsl-ai-dev test root.'
}
if ($FailAfterVerbCount -gt 0 -and -not $isTestRegistryRoot) {
    throw '-FailAfterVerbCount is available only with an isolated bootstrap-wsl-ai-dev test root.'
}
if ($FailAfterRegistryWriteCount -gt 0 -and -not $isTestRegistryRoot) {
    throw '-FailAfterRegistryWriteCount is available only with an isolated bootstrap-wsl-ai-dev test root.'
}
if ($FailAfterRegistryImportCount -gt 0 -and -not $isTestRegistryRoot) {
    throw '-FailAfterRegistryImportCount is available only with an isolated bootstrap-wsl-ai-dev test root.'
}

function Get-CommandExecutablePath {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }

    foreach ($propertyName in @('Path', 'Source', 'Definition')) {
        $property = $command.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }

    return $null
}

function Get-DefaultWslExecutable {
    $fromCommand = Get-CommandExecutablePath -Name 'wsl.exe'
    if ($null -ne $fromCommand) {
        return $fromCommand
    }

    return Join-Path $env:SystemRoot 'System32\wsl.exe'
}

function Get-DefaultWindowsTerminalExecutable {
    $fromCommand = Get-CommandExecutablePath -Name 'wt.exe'
    if ($null -ne $fromCommand) {
        return $fromCommand
    }

    return Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
}

function Get-DefaultWindowsTerminalSettingsPath {
    $packageNames = @(
        'Microsoft.WindowsTerminal_8wekyb3d8bbwe',
        'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe'
    )
    foreach ($packageName in $packageNames) {
        $candidate = Join-Path $env:LOCALAPPDATA ('Packages\' + $packageName + '\LocalState\settings.json')
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

if ([string]::IsNullOrWhiteSpace($WslExecutable)) {
    $WslExecutable = Get-DefaultWslExecutable
}
if ([string]::IsNullOrWhiteSpace($WindowsTerminalExecutable)) {
    $WindowsTerminalExecutable = Get-DefaultWindowsTerminalExecutable
}
if ([string]::IsNullOrWhiteSpace($WindowsTerminalSettingsPath)) {
    $WindowsTerminalSettingsPath = Get-DefaultWindowsTerminalSettingsPath
}

function Join-RegistryKey {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Child
    )

    return $Root.TrimEnd('\') + '\' + $Child
}

function Assert-SafeCommandArgument {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )

    if ($Value.IndexOf('"') -ge 0 -or $Value -match '[\x00-\x1F\x7F]') {
        throw "$ParameterName must not contain quotes or control characters."
    }
}

function ConvertTo-QuotedCommandArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    Assert-SafeCommandArgument -Value $Value -ParameterName 'Command argument'

    $trailingBackslashCount = ([regex]::Match($Value, '\\+$')).Length
    $escapedTrailingBackslashes = if ($trailingBackslashCount -gt 0) {
        (('\' * $trailingBackslashCount) -join '')
    } else {
        ''
    }
    return '"' + $Value + $escapedTrailingBackslashes + '"'
}

function Get-WslDistributions {
    if (-not (Test-Path -LiteralPath $WslExecutable -PathType Leaf)) {
        throw "WSL executable was not found at '$WslExecutable'. Install WSL or pass -WslExecutable with an existing wsl.exe path."
    }

    $output = @(& $WslExecutable --list --quiet 2>&1)
    $exitCode = $LASTEXITCODE
    $normalizedOutput = @($output | ForEach-Object {
        ([string]$_).Replace(([char]0).ToString(), '').Trim()
    } | Where-Object { $_.Length -gt 0 })
    if ($exitCode -ne 0) {
        $details = if ($normalizedOutput.Count -gt 0) { ': ' + ($normalizedOutput -join ' ') } else { '' }
        throw "Unable to list WSL distributions using '$WslExecutable' (exit code $exitCode)$details. Run '$WslExecutable --list --quiet' and resolve the error before installing."
    }

    return $normalizedOutput
}

function Get-WindowsTerminalProfileNames {
    if ([string]::IsNullOrWhiteSpace($WindowsTerminalSettingsPath) -or
        -not (Test-Path -LiteralPath $WindowsTerminalSettingsPath -PathType Leaf)) {
        throw "Windows Terminal settings.json was not found. Install Windows Terminal or pass -WindowsTerminalSettingsPath to its existing settings.json file."
    }

    try {
        $settings = Get-Content -LiteralPath $WindowsTerminalSettingsPath -Raw | ConvertFrom-Json
    } catch {
        throw "Windows Terminal settings file '$WindowsTerminalSettingsPath' is not valid JSON: $($_.Exception.Message)"
    }

    $profiles = @()
    if ($null -ne $settings.profiles) {
        $profileListProperty = $settings.profiles.PSObject.Properties['list']
        if ($null -ne $profileListProperty) {
            $profiles = @($profileListProperty.Value)
        } elseif ($settings.profiles -is [System.Collections.IEnumerable] -and
                  $settings.profiles -isnot [string]) {
            $profiles = @($settings.profiles)
        }
    }

    return @($profiles | ForEach-Object {
        if ($null -ne $_.name) { [string]$_.name }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Assert-InstallPrerequisites {
    if ($SkipPrerequisiteCheck) {
        return
    }

    if (-not (Test-Path -LiteralPath $WindowsTerminalExecutable -PathType Leaf)) {
        throw "Windows Terminal executable was not found at '$WindowsTerminalExecutable'. Install Windows Terminal or pass -WindowsTerminalExecutable with an existing wt.exe path."
    }

    $distributions = @(Get-WslDistributions)
    $distributionFound = $false
    foreach ($candidate in $distributions) {
        if ([string]$candidate -ceq $Distribution) {
            $distributionFound = $true
            break
        }
    }
    if (-not $distributionFound) {
        $available = if ($distributions.Count -gt 0) { $distributions -join ', ' } else { '(none)' }
        throw "WSL distribution '$Distribution' was not found. Available distributions: $available. Pass -Distribution with one of these exact names."
    }

    $profiles = @(Get-WindowsTerminalProfileNames)
    $profileFound = $false
    foreach ($candidate in $profiles) {
        if ([string]$candidate -ceq $TerminalProfile) {
            $profileFound = $true
            break
        }
    }
    if (-not $profileFound) {
        $available = if ($profiles.Count -gt 0) { $profiles -join ', ' } else { '(none)' }
        throw "Windows Terminal profile '$TerminalProfile' was not found in '$WindowsTerminalSettingsPath'. Available profiles: $available. Pass -TerminalProfile with one of these exact names."
    }
}

function Get-VerbDefinitions {
    Assert-SafeCommandArgument -Value $Distribution -ParameterName 'Distribution'
    Assert-SafeCommandArgument -Value $TerminalProfile -ParameterName 'TerminalProfile'

    $wslCommand = (ConvertTo-QuotedCommandArgument $WslExecutable) +
        ' -d ' + (ConvertTo-QuotedCommandArgument $Distribution) + ' --cd "{0}"'
    $terminalCommand = (ConvertTo-QuotedCommandArgument $WindowsTerminalExecutable) +
        ' -w new nt -p ' + (ConvertTo-QuotedCommandArgument $TerminalProfile) + ' -d "{0}"'

    $locations = @(
        @{ Path = 'Directory\Background\shell'; Target = '%V' },
        @{ Path = 'Directory\shell'; Target = '%1' }
    )
    $verbs = @(
        @{ Name = 'WSLUbuntu'; Label = "Open $Distribution in WSL"; Command = $wslCommand; Icon = $WslExecutable },
        @{ Name = 'WSLUbuntuWindowsTerminal'; Label = "Open $Distribution in Windows Terminal"; Command = $terminalCommand; Icon = $WindowsTerminalExecutable }
    )

    $definitions = @()
    foreach ($location in $locations) {
        foreach ($verb in $verbs) {
            $definitions += [PSCustomObject]@{
                Path = Join-RegistryKey $RegistryClassesRoot ($location.Path + '\' + $verb.Name)
                Label = $verb.Label
                Command = ($verb.Command -f $location.Target)
                Icon = $verb.Icon
            }
        }
    }

    return $definitions
}

function Test-OwnedKey {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    return $item.GetValue($ownerValueName, $null) -eq $ownerValue
}

function Test-VerbKeyContainsOnlyVerbData {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    $allowedValueNames = @('', 'MUIVerb', 'Icon', 'Position', $ownerValueName)
    if (@($item.GetValueNames() | Where-Object { $allowedValueNames -notcontains $_ }).Count -gt 0) {
        return $false
    }

    $children = @($item.GetSubKeyNames())
    if ($children.Count -ne 1 -or $children[0] -ne 'command') {
        return $false
    }

    $command = Get-Item -LiteralPath (Join-RegistryKey $Path 'command')
    return @($command.GetValueNames()).Count -eq 1 -and $command.GetValueNames()[0] -eq '' -and
        $command.GetValueKind('') -eq [Microsoft.Win32.RegistryValueKind]::String -and
        @($command.GetSubKeyNames()).Count -eq 0
}

function ConvertTo-NativeRegistryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -notmatch '^HKCU:\\') {
        throw "Only HKCU registry paths can be snapshotted: '$Path'."
    }

    return 'HKCU\' + $Path.Substring(6)
}

function Invoke-RegistryUtility {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & reg.exe @Arguments 2>$null | Out-Null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Save-RegistrySubtreeSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $snapshot = [PSCustomObject]@{
        Path = $Path
        Exists = Test-Path -LiteralPath $Path
        BackupPath = $null
        KeepBackup = $false
    }
    if (-not $snapshot.Exists) {
        return $snapshot
    }

    $snapshot.BackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ('bootstrap-wsl-ai-dev-registry-' + [Guid]::NewGuid().ToString('N') + '.reg')
    try {
        $exitCode = Invoke-RegistryUtility -Arguments @('export', (ConvertTo-NativeRegistryPath -Path $Path), $snapshot.BackupPath, '/y')
        if ($exitCode -ne 0) {
            throw "Unable to snapshot registry subtree '$Path'."
        }
    } catch {
        if (Test-Path -LiteralPath $snapshot.BackupPath) {
            Remove-Item -LiteralPath $snapshot.BackupPath -Force
        }
        throw
    }

    return $snapshot
}

function Restore-RegistrySubtreeSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    if (Test-Path -LiteralPath $Snapshot.Path) {
        Remove-Item -LiteralPath $Snapshot.Path -Recurse -Force
    }
    if ($Snapshot.Exists) {
        $script:registryImportCount++
        if ($FailAfterRegistryImportCount -gt 0 -and $script:registryImportCount -eq $FailAfterRegistryImportCount) {
            throw "Injected failure before registry snapshot import $script:registryImportCount for '$($Snapshot.Path)'."
        }
        $exitCode = Invoke-RegistryUtility -Arguments @('import', $Snapshot.BackupPath)
        if ($exitCode -ne 0) {
            throw "Unable to restore registry subtree '$($Snapshot.Path)'."
        }
    }
}

function Get-MissingRegistryAncestors {
    param([Parameter(Mandatory = $true)][string]$Path)

    $missingPaths = @()
    $candidate = $Path
    while ($candidate.StartsWith($RegistryClassesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            $missingPaths += $candidate
        }
        if ($candidate.Length -eq $RegistryClassesRoot.Length) {
            break
        }
        $candidate = Split-Path -Path $candidate -Parent
    }

    return $missingPaths
}

function Remove-EmptyRegistryKeys {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    foreach ($path in @($Paths | Sort-Object { $_.Length } -Descending -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        $item = Get-Item -LiteralPath $path
        if (@($item.GetValueNames()).Count -eq 0 -and @($item.GetSubKeyNames()).Count -eq 0) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Invoke-RegistryWrite {
    param([Parameter(Mandatory = $true)][scriptblock]$Operation)

    & $Operation
    $script:registryWriteCount++
    if ($FailAfterRegistryWriteCount -gt 0 -and $script:registryWriteCount -eq $FailAfterRegistryWriteCount) {
        throw "Injected failure after $script:registryWriteCount registry writes."
    }
}

function Invoke-RegistryTransaction {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)][scriptblock]$Operation
    )

    $snapshots = @()
    $missingAncestorPaths = @()
    $script:registryImportCount = 0
    foreach ($path in @($Paths | Select-Object -Unique)) {
        $missingAncestorPaths += @(Get-MissingRegistryAncestors -Path $path)
        $snapshots += Save-RegistrySubtreeSnapshot -Path $path
    }

    try {
        & $Operation
    } catch {
        $operationFailure = $_
        $restoreFailures = @()
        foreach ($snapshot in $snapshots) {
            try {
                Restore-RegistrySubtreeSnapshot -Snapshot $snapshot
            } catch {
                $snapshot.KeepBackup = $true
                $restoreFailures += "Registry path '$($snapshot.Path)' could not be restored; backup retained at '$($snapshot.BackupPath)': $($_.Exception.Message)"
            }
        }
        if ($missingAncestorPaths.Count -gt 0) {
            Remove-EmptyRegistryKeys -Paths $missingAncestorPaths
        }
        if ($restoreFailures.Count -gt 0) {
            throw ("Operation failed: $($operationFailure.Exception.Message) Rollback failures: " + ($restoreFailures -join ' '))
        }
        throw $operationFailure
    } finally {
        foreach ($snapshot in $snapshots) {
            if (-not $snapshot.KeepBackup -and $null -ne $snapshot.BackupPath -and (Test-Path -LiteralPath $snapshot.BackupPath)) {
                Remove-Item -LiteralPath $snapshot.BackupPath -Force
            }
        }
    }
}

function Install-Verbs {
    Assert-InstallPrerequisites

    $definitions = @(Get-VerbDefinitions)
    foreach ($definition in $definitions) {
        if ((Test-Path -LiteralPath $definition.Path) -and -not (Test-OwnedKey $definition.Path)) {
            if (-not $Force) {
                throw "Refusing to overwrite unowned Explorer verb '$($definition.Path)'. Re-run with -Force only after reviewing it."
            }
            if (-not (Test-VerbKeyContainsOnlyVerbData $definition.Path)) {
                throw "Refusing to adopt Explorer verb '$($definition.Path)' because it contains values or subkeys outside a standard shell verb."
            }
        }
    }

    $completedVerbCount = 0
    $script:registryWriteCount = 0
    Invoke-RegistryTransaction -Paths @($definitions | ForEach-Object { $_.Path }) -Operation {
        foreach ($definition in $definitions) {
            $wasPresent = Test-Path -LiteralPath $definition.Path
            if ($PSCmdlet.ShouldProcess($definition.Path, 'Install Explorer verb')) {
                if (-not $wasPresent) {
                    Invoke-RegistryWrite { New-Item -Path $definition.Path -Force | Out-Null }
                }
                Invoke-RegistryWrite { Set-ItemProperty -LiteralPath $definition.Path -Name $ownerValueName -Value $ownerValue -Type String }
                Invoke-RegistryWrite { Set-ItemProperty -LiteralPath $definition.Path -Name 'MUIVerb' -Value $definition.Label -Type String }
                Invoke-RegistryWrite { Set-ItemProperty -LiteralPath $definition.Path -Name 'Icon' -Value $definition.Icon -Type String }
                Invoke-RegistryWrite { Set-ItemProperty -LiteralPath $definition.Path -Name 'Position' -Value 'Top' -Type String }
                $commandPath = Join-RegistryKey $definition.Path 'command'
                if (-not (Test-Path -LiteralPath $commandPath)) {
                    Invoke-RegistryWrite { New-Item -Path $commandPath -Force | Out-Null }
                }
                Invoke-RegistryWrite { Set-Item -LiteralPath $commandPath -Value $definition.Command }
                $completedVerbCount++
                if ($FailAfterVerbCount -gt 0 -and $completedVerbCount -eq $FailAfterVerbCount) {
                    throw "Injected failure after $completedVerbCount Explorer verb writes."
                }
            }
        }
    }
}

function Remove-Verbs {
    foreach ($definition in @(Get-VerbDefinitions)) {
        if ((Test-Path -LiteralPath $definition.Path) -and (Test-OwnedKey $definition.Path)) {
            if (-not (Test-VerbKeyContainsOnlyVerbData $definition.Path)) {
                Write-Warning "Owned Explorer verb '$($definition.Path)' contains unexpected values or subkeys; leaving it unchanged."
                continue
            }
            if ($PSCmdlet.ShouldProcess($definition.Path, 'Remove owned Explorer verb')) {
                Remove-Item -LiteralPath $definition.Path -Recurse -Force
            }
        }
    }
}

function Get-ClassicContextMenuPath {
    return Join-RegistryKey $RegistryClassesRoot ('CLSID\' + $classicClsid)
}

function Test-ExpectedClassicContextMenuKey {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $parent = Get-Item -LiteralPath $Path
    $allowedParentValueNames = @($ownerValueName)
    $unexpectedParentValues = @($parent.GetValueNames() | Where-Object { $allowedParentValueNames -notcontains $_ })
    $children = @($parent.GetSubKeyNames())
    if ($unexpectedParentValues.Count -gt 0 -or $children.Count -ne 1 -or $children[0] -ne 'InprocServer32') {
        return $false
    }

    $inprocPath = Join-RegistryKey $Path 'InprocServer32'
    $inproc = Get-Item -LiteralPath $inprocPath
    $valueNames = @($inproc.GetValueNames())
    return $valueNames.Count -eq 1 -and $valueNames[0] -eq '' -and
        $inproc.GetValueKind('') -eq [Microsoft.Win32.RegistryValueKind]::String -and
        $inproc.GetValue('') -ceq '' -and @($inproc.GetSubKeyNames()).Count -eq 0
}

function Test-SafeUnownedClassicContextMenuKey {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-ExpectedClassicContextMenuKey $Path)) {
        return $false
    }

    $parent = Get-Item -LiteralPath $Path
    return -not (Test-OwnedKey $Path) -and @($parent.GetValueNames()).Count -eq 0
}

function Enable-ClassicContextMenu {
    $classicPath = Get-ClassicContextMenuPath
    if (Test-Path -LiteralPath $classicPath) {
        if (Test-OwnedKey $classicPath) {
            if (-not (Test-ExpectedClassicContextMenuKey $classicPath)) {
                throw "Refusing to rewrite owned classic context menu key '$classicPath' because it is not the expected safe shape."
            }
            return
        }
        if (-not $Force) {
            throw "Refusing to overwrite unowned classic context menu key '$classicPath'. Re-run with -Force only after reviewing it."
        }
        if (-not (Test-SafeUnownedClassicContextMenuKey $classicPath)) {
            throw "Refusing to adopt unowned classic context menu key '$classicPath' because it is not the exact safe classic context-menu shape."
        }

        if ($PSCmdlet.ShouldProcess($classicPath, 'Adopt safe classic Explorer context menu key')) {
            $script:registryWriteCount = 0
            Invoke-RegistryTransaction -Paths @($classicPath) -Operation {
                Invoke-RegistryWrite { Set-ItemProperty -LiteralPath $classicPath -Name $ownerValueName -Value $ownerValue -Type String }
            }
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($classicPath, 'Enable classic Explorer context menu')) {
        $script:registryWriteCount = 0
        Invoke-RegistryTransaction -Paths @($classicPath) -Operation {
            Invoke-RegistryWrite { New-Item -Path $classicPath -Force | Out-Null }
            Invoke-RegistryWrite { Set-ItemProperty -LiteralPath $classicPath -Name $ownerValueName -Value $ownerValue -Type String }
            $inprocPath = Join-RegistryKey $classicPath 'InprocServer32'
            Invoke-RegistryWrite { New-Item -Path $inprocPath -Force | Out-Null }
            Invoke-RegistryWrite { Set-Item -LiteralPath $inprocPath -Value '' }
        }
    }
}

function Disable-ClassicContextMenu {
    $classicPath = Get-ClassicContextMenuPath
    if (-not (Test-Path -LiteralPath $classicPath)) {
        return
    }

    if (-not (Test-OwnedKey $classicPath) -or -not (Test-ExpectedClassicContextMenuKey $classicPath)) {
        Write-Warning "Classic context menu key '$classicPath' is not exclusively owned or has unexpected values; leaving it unchanged."
        return
    }

    if ($PSCmdlet.ShouldProcess($classicPath, 'Disable classic Explorer context menu')) {
        Remove-Item -LiteralPath $classicPath -Recurse -Force
    }
}

function Get-Status {
    $rows = foreach ($definition in @(Get-VerbDefinitions)) {
        [PSCustomObject]@{
            Type = 'ExplorerVerb'
            Path = $definition.Path
            Owned = Test-OwnedKey $definition.Path
            Present = Test-Path -LiteralPath $definition.Path
            Command = if (Test-Path -LiteralPath (Join-RegistryKey $definition.Path 'command')) {
                (Get-Item -LiteralPath (Join-RegistryKey $definition.Path 'command')).GetValue('')
            } else {
                $null
            }
        }
    }

    $classicPath = Get-ClassicContextMenuPath
    $rows += [PSCustomObject]@{
        Type = 'ClassicContextMenu'
        Path = $classicPath
        Owned = Test-OwnedKey $classicPath
        Present = Test-Path -LiteralPath $classicPath
        Command = $null
    }
    return $rows
}

function Restart-ExplorerIfRequested {
    if (-not $RestartExplorer) {
        return
    }

    if ($RegistryClassesRoot -ne $liveRegistryClassesRoot) {
        Write-Warning 'Explorer was not restarted because RegistryClassesRoot is not the live HKCU classes root.'
        return
    }

    if ($PSCmdlet.ShouldProcess('explorer.exe', 'Restart Explorer')) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    }
}

if ($Action -eq 'Status' -and $ClassicContextMenu -eq 'Keep') {
    Get-Status
    return
}

if ($Action -eq 'Install') {
    Install-Verbs
} elseif ($Action -eq 'Remove') {
    Remove-Verbs
}

switch ($ClassicContextMenu) {
    'Enable' { Enable-ClassicContextMenu }
    'Disable' { Disable-ClassicContextMenu }
}

Restart-ExplorerIfRequested

if ($Action -eq 'Status') {
    Get-Status
}
