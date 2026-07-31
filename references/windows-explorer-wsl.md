# Windows Explorer launchers for WSL

## Contents

1. Scope and choices
2. Prerequisites
3. Inspect and install
4. Windows 11 context-menu behavior
5. Verify and remove
6. Implementation model

## 1. Scope and choices

This optional feature adds two distinct per-user Explorer commands without requiring administrator elevation:

| Entry | Terminal host | Starting directory |
| --- | --- | --- |
| Open WSL directly | `wsl.exe` | The background directory or selected folder |
| Open with Windows Terminal | The named Windows Terminal profile | The background directory or selected folder |

The commands enter the same WSL distribution, but their appearance can differ. Direct `wsl.exe` does not explicitly select a Windows Terminal profile. The Windows Terminal entry applies that profile's icon, terminal settings, and window behavior.

Keep the classic Windows 11 context menu independent from launcher installation. Classic mode affects all Explorer context menus for the current Windows user, not only these entries.

The classic-menu switch uses an undocumented Windows 11 compatibility override rather than a supported shell-extension API. It is reversible, but a Windows update may stop honoring it. Keep the default compact menu when long-term platform compatibility matters more than direct visibility.

## 2. Prerequisites

Run these checks in Windows PowerShell:

```powershell
wsl.exe --list --quiet
Get-Command wsl.exe, wt.exe
```

Confirm the exact Windows Terminal profile name in Terminal settings. The defaults are the `Ubuntu` distribution and `Ubuntu` profile; do not assume those names on another machine. Installation validates both names exactly before writing registry entries. Localized and customized names are supported; quotes and control characters are rejected because they cannot be represented safely in the registered command.

By default, the script discovers `wsl.exe` and `wt.exe` through Windows command resolution, then checks their standard system locations. It discovers Terminal's stable and preview `settings.json` locations under `%LOCALAPPDATA%\Packages`. For an unpackaged or otherwise nonstandard Terminal installation, pass the resolved paths explicitly:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Install `
  -WslExecutable 'C:\Windows\System32\wsl.exe' `
  -WindowsTerminalExecutable '<path-to-wt.exe>' `
  -WindowsTerminalSettingsPath '<path-to-settings.json>'
```

The script writes only below `HKCU:\Software\Classes`, so installation does not need UAC. It refuses to overwrite a colliding registry key that it does not own unless the user deliberately passes `-Force` after inspection. Even with `-Force`, it adopts only a standard shell-verb shape and rejects keys containing unrelated values or subkeys.

## 3. Inspect and install

From Windows PowerShell in the repository root, inspect the current state first:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 -Action Status
```

Install both launchers while leaving the Windows 11 context-menu style unchanged:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Install `
  -Distribution Ubuntu `
  -TerminalProfile Ubuntu
```

The install action is idempotent. It installs both launcher types for both a directory background and a selected folder; selecting only one launcher type is not a `v0.1.0` feature. It does not change the WSL default user, request elevation, or modify Windows Terminal settings. Before writing, it snapshots each affected registry subtree. If a write fails, it restores the pre-run state before returning the error. If Windows itself cannot import a rollback snapshot, the error reports the retained `.reg` backup path for manual recovery while continuing to restore the other subtrees.

Use `-WhatIf` before applying a change when reviewing a different workstation:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 -Action Install -WhatIf
```

## 4. Windows 11 context-menu behavior

Registry shell verbs normally appear under **Show more options** in the compact Windows 11 menu. A single custom verb cannot be promoted into the compact menu with another simple registry value; that requires a packaged `IExplorerCommand` shell extension and is outside this bootstrap feature.

After explicit approval, enable the full classic context menu for the current user:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Status `
  -ClassicContextMenu Enable `
  -RestartExplorer
```

`-RestartExplorer` is always explicit because Explorer windows and the taskbar briefly disappear. Omit it when the user prefers to sign out or restart Explorer later.

Restore the Windows 11 compact menu without removing the WSL launchers:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Status `
  -ClassicContextMenu Disable `
  -RestartExplorer
```

## 5. Verify and remove

Test both locations after installation:

1. Right-click the background of a directory containing spaces in its path.
2. Right-click a selected folder.
3. Confirm the direct entry and Windows Terminal entry both open the requested directory.
4. Confirm the Windows Terminal entry uses the named profile and creates a new window.
5. Run the status action again and inspect its ownership and classic-menu report.

Remove only the launcher keys owned by this feature:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 -Action Remove
```

Removal leaves the classic-menu choice unchanged. To remove launchers and restore the compact menu together, add `-ClassicContextMenu Disable -RestartExplorer`.

## 6. Implementation model

Explorer supplies `%V` for a directory-background command and `%1` for a selected-folder command. The script registers both targets under the current user's `Directory\Background\shell` and `Directory\shell` branches.

The direct command follows this shape:

```text
wsl.exe -d DISTRIBUTION --cd "%V_OR_%1"
```

The Windows Terminal command forces a new window and selects the named profile:

```text
wt.exe -w new nt -p "PROFILE" -d "%V_OR_%1"
```

The classic-menu switch manages the per-user `InprocServer32` override for CLSID `{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}`. Disable removes it only when its state matches the known empty-value override, so unrelated registry content is not silently deleted.
