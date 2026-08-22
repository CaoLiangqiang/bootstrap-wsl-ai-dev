#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Install', 'Remove', 'Status')]
    [string]$Action = 'Status',

    [string]$TerminalProfile = 'Ubuntu',

    [string]$WindowsTerminalSettingsPath,

    [string]$FragmentDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$schemeName = 'Ubuntu Native'
$fragmentFileName = 'ubuntu-native.json'

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

if ([string]::IsNullOrWhiteSpace($WindowsTerminalSettingsPath)) {
    $WindowsTerminalSettingsPath = Get-DefaultWindowsTerminalSettingsPath
}
if ([string]::IsNullOrWhiteSpace($FragmentDirectory)) {
    $FragmentDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\bootstrap-wsl-ai-dev'
}
$fragmentPath = Join-Path $FragmentDirectory $fragmentFileName

function Get-UbuntuNativeSchemeValues {
    return [ordered]@{
        name = $schemeName
        background = '#300A24'
        foreground = '#EEEEEC'
        cursorColor = '#FFFFFF'
        selectionBackground = '#5E2750'
        black = '#2E3436'
        red = '#CC0000'
        green = '#4E9A06'
        yellow = '#C4A000'
        blue = '#3465A4'
        purple = '#75507B'
        cyan = '#06989A'
        white = '#D3D7CF'
        brightBlack = '#555753'
        brightRed = '#EF2929'
        brightGreen = '#8AE234'
        brightYellow = '#FCE94F'
        brightBlue = '#729FCF'
        brightPurple = '#AD7FA8'
        brightCyan = '#34E2E2'
        brightWhite = '#EEEEEC'
    }
}

function Get-TerminalProfiles {
    if ([string]::IsNullOrWhiteSpace($WindowsTerminalSettingsPath) -or
        -not (Test-Path -LiteralPath $WindowsTerminalSettingsPath -PathType Leaf)) {
        throw "Windows Terminal settings.json was not found. Install Windows Terminal or pass -WindowsTerminalSettingsPath to its existing settings.json file."
    }

    try {
        $settings = Get-Content -LiteralPath $WindowsTerminalSettingsPath -Raw | ConvertFrom-Json
    } catch {
        throw "Windows Terminal settings file '$WindowsTerminalSettingsPath' is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $settings.profiles) {
        return @()
    }
    $profileListProperty = $settings.profiles.PSObject.Properties['list']
    if ($null -ne $profileListProperty) {
        return @($profileListProperty.Value)
    }
    if ($settings.profiles -is [System.Collections.IEnumerable] -and $settings.profiles -isnot [string]) {
        return @($settings.profiles)
    }
    return @()
}

function Get-TargetProfileGuid {
    $profiles = @(Get-TerminalProfiles)
    $matches = @($profiles | Where-Object { $null -ne $_.name -and [string]$_.name -ceq $TerminalProfile })
    if ($matches.Count -ne 1) {
        $available = @($profiles | ForEach-Object {
            if ($null -ne $_.name) { [string]$_.name }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $availableText = if ($available.Count -gt 0) { $available -join ', ' } else { '(none)' }
        throw "Expected exactly one Windows Terminal profile named '$TerminalProfile' in '$WindowsTerminalSettingsPath'; found $($matches.Count). Available profiles: $availableText."
    }

    $guidProperty = $matches[0].PSObject.Properties['guid']
    if ($null -eq $guidProperty -or [string]::IsNullOrWhiteSpace([string]$guidProperty.Value)) {
        throw "Windows Terminal profile '$TerminalProfile' does not expose a GUID in '$WindowsTerminalSettingsPath'."
    }
    $parsedGuid = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$guidProperty.Value, [ref]$parsedGuid)) {
        throw "Windows Terminal profile '$TerminalProfile' has an invalid GUID '$($guidProperty.Value)'."
    }
    return '{' + $parsedGuid.ToString() + '}'
}

function New-FragmentObject {
    param([Parameter(Mandatory = $true)][string]$ProfileGuid)

    return [pscustomobject][ordered]@{
        profiles = @(
            [pscustomobject][ordered]@{
                updates = $ProfileGuid
                colorScheme = $schemeName
                tabColor = '#E95420'
            }
        )
        schemes = @([pscustomobject](Get-UbuntuNativeSchemeValues))
    }
}

function Test-ExpectedFragment {
    param([Parameter(Mandatory = $true)]$Fragment)

    $rootProperties = @($Fragment.PSObject.Properties.Name | Sort-Object)
    if (($rootProperties -join ',') -cne 'profiles,schemes') {
        return $false
    }

    $profiles = @($Fragment.profiles)
    $schemes = @($Fragment.schemes)
    if ($profiles.Count -ne 1 -or $schemes.Count -ne 1) {
        return $false
    }

    $profileProperties = @($profiles[0].PSObject.Properties.Name | Sort-Object)
    if (($profileProperties -join ',') -cne 'colorScheme,tabColor,updates' -or
        [string]$profiles[0].colorScheme -cne $schemeName -or
        [string]$profiles[0].tabColor -cne '#E95420') {
        return $false
    }
    $parsedGuid = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$profiles[0].updates, [ref]$parsedGuid)) {
        return $false
    }

    $expectedScheme = Get-UbuntuNativeSchemeValues
    $schemeProperties = @($schemes[0].PSObject.Properties.Name | Sort-Object)
    $expectedProperties = @($expectedScheme.Keys | Sort-Object)
    if (($schemeProperties -join ',') -cne ($expectedProperties -join ',')) {
        return $false
    }
    foreach ($entry in $expectedScheme.GetEnumerator()) {
        if ([string]$schemes[0].($entry.Key) -cne [string]$entry.Value) {
            return $false
        }
    }
    return $true
}

function Get-FragmentState {
    if (-not (Test-Path -LiteralPath $fragmentPath -PathType Leaf)) {
        return [pscustomobject]@{
            Type = 'WindowsTerminalFragment'
            Path = $fragmentPath
            Present = $false
            Owned = $false
            ProfileGuid = $null
            ColorScheme = $schemeName
        }
    }

    $fragment = $null
    try {
        $fragment = Get-Content -LiteralPath $fragmentPath -Raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            Type = 'WindowsTerminalFragment'
            Path = $fragmentPath
            Present = $true
            Owned = $false
            ProfileGuid = $null
            ColorScheme = $schemeName
        }
    }
    $owned = Test-ExpectedFragment -Fragment $fragment
    return [pscustomobject]@{
        Type = 'WindowsTerminalFragment'
        Path = $fragmentPath
        Present = $true
        Owned = $owned
        ProfileGuid = if ($owned) { [string]@($fragment.profiles)[0].updates } else { $null }
        ColorScheme = $schemeName
    }
}

function Install-Fragment {
    $profileGuid = Get-TargetProfileGuid
    $state = Get-FragmentState
    if ($state.Present -and -not $state.Owned) {
        throw "Refusing to overwrite unowned or modified Windows Terminal fragment '$fragmentPath'."
    }
    if ($state.Owned -and $state.ProfileGuid -ceq $profileGuid) {
        return
    }
    if (-not $PSCmdlet.ShouldProcess($fragmentPath, "Install Ubuntu Native theme for profile '$TerminalProfile'")) {
        return
    }

    $directoryWasPresent = Test-Path -LiteralPath $FragmentDirectory -PathType Container
    if (-not $directoryWasPresent) {
        New-Item -ItemType Directory -Path $FragmentDirectory -Force | Out-Null
    }
    $temporaryPath = Join-Path $FragmentDirectory ('.' + $fragmentFileName + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = $null
    try {
        $fragment = New-FragmentObject -ProfileGuid $profileGuid
        $json = $fragment | ConvertTo-Json -Depth 8
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, $utf8WithoutBom)
        $validation = Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json
        if (-not (Test-ExpectedFragment -Fragment $validation)) {
            throw 'Generated Windows Terminal fragment did not pass validation.'
        }

        if (Test-Path -LiteralPath $fragmentPath -PathType Leaf) {
            $backupPath = Join-Path $FragmentDirectory ('.' + $fragmentFileName + '.' + [Guid]::NewGuid().ToString('N') + '.bak')
            Copy-Item -LiteralPath $fragmentPath -Destination $backupPath
        }
        Move-Item -LiteralPath $temporaryPath -Destination $fragmentPath -Force
        $writtenState = Get-FragmentState
        if (-not $writtenState.Owned -or $writtenState.ProfileGuid -cne $profileGuid) {
            throw 'Windows Terminal fragment verification failed after writing.'
        }
    } catch {
        $failure = $_
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Move-Item -LiteralPath $backupPath -Destination $fragmentPath -Force
        } elseif (Test-Path -LiteralPath $fragmentPath -PathType Leaf) {
            Remove-Item -LiteralPath $fragmentPath -Force
        }
        throw $failure
    } finally {
        foreach ($temporaryFile in @($temporaryPath, $backupPath)) {
            if ($null -ne $temporaryFile -and (Test-Path -LiteralPath $temporaryFile)) {
                Remove-Item -LiteralPath $temporaryFile -Force
            }
        }
        if (-not $directoryWasPresent -and (Test-Path -LiteralPath $FragmentDirectory -PathType Container) -and
            @(Get-ChildItem -LiteralPath $FragmentDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $FragmentDirectory -Force
        }
    }
}

function Remove-Fragment {
    $state = Get-FragmentState
    if (-not $state.Present) {
        return
    }
    if (-not $state.Owned) {
        Write-Warning "Windows Terminal fragment '$fragmentPath' is not exclusively owned or was modified; leaving it unchanged."
        return
    }
    if ($PSCmdlet.ShouldProcess($fragmentPath, 'Remove owned Ubuntu Native theme fragment')) {
        Remove-Item -LiteralPath $fragmentPath -Force
        if ((Test-Path -LiteralPath $FragmentDirectory -PathType Container) -and
            @(Get-ChildItem -LiteralPath $FragmentDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $FragmentDirectory -Force
        }
    }
}

if ($Action -eq 'Install') {
    Install-Fragment
} elseif ($Action -eq 'Remove') {
    Remove-Fragment
}

Get-FragmentState
