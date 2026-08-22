# Windows Explorer launchers for WSL

## Contents

1. Scope and choices
2. Prerequisites
3. Inspect and install
4. Ubuntu-native Windows Terminal theme
5. Windows 11 context-menu behavior
6. Verify and remove
7. Implementation model

## 1. Scope and choices

This optional feature adds per-user Explorer commands without administrator elevation. Choose the launch surface explicitly:

| `LauncherMode` | Installed entry | Terminal host |
| --- | --- | --- |
| `Both` (default) | Direct WSL and Windows Terminal | `wsl.exe` and the named Terminal profile |
| `Direct` | Direct WSL only | `wsl.exe` |
| `WindowsTerminal` | Windows Terminal only | The named Terminal profile |

Every selected entry is installed for both a directory background and a selected folder. Switching modes removes only unselected verbs already owned by this project. Unowned or modified registry keys are preserved.

The optional Ubuntu-native theme is independent from launcher selection. It gives one named Windows Terminal profile a solid Ubuntu aubergine background (`#300A24`), light foreground, Tango-style ANSI colors, and an Ubuntu orange tab (`#E95420`). It does not change PowerShell, Command Prompt, other WSL profiles, or Windows Terminal's global theme.

Keep the classic Windows 11 context menu independent from both features. Classic mode affects all Explorer context menus for the current Windows user, not only these entries.

## 2. Prerequisites

Run these checks in Windows PowerShell:

```powershell
wsl.exe --list --quiet
Get-Command wsl.exe, wt.exe
```

Confirm the exact Windows Terminal profile name in Terminal settings. The defaults are the `Ubuntu` distribution and `Ubuntu` profile; do not assume those names on another machine. Installation validates the WSL distribution and, when selected, the Terminal executable and profile before writing.

The scripts discover the stable and preview Terminal `settings.json` locations under `%LOCALAPPDATA%\Packages`. For an unpackaged or otherwise nonstandard Terminal installation, pass the paths explicitly:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Install `
  -LauncherMode WindowsTerminal `
  -WslExecutable 'C:\Windows\System32\wsl.exe' `
  -WindowsTerminalExecutable '<path-to-wt.exe>' `
  -WindowsTerminalSettingsPath '<path-to-settings.json>'

.\scripts\configure-windows-terminal-ubuntu-theme.ps1 `
  -Action Install `
  -WindowsTerminalSettingsPath '<path-to-settings.json>'
```

The Explorer script writes only below `HKCU:\Software\Classes`. It refuses to overwrite a selected colliding registry key that it does not own unless `-Force` is deliberately passed after inspection. Even with `-Force`, it adopts only a standard shell-verb shape and rejects unrelated values or subkeys.

## 3. Inspect and install

Start with both read-only status actions:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Status `
  -LauncherMode WindowsTerminal

.\scripts\configure-windows-terminal-ubuntu-theme.ps1 -Action Status
```

For a single Explorer entry that opens the current directory in the Ubuntu Windows Terminal profile, install only that launcher:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Install `
  -Distribution Ubuntu `
  -TerminalProfile Ubuntu `
  -LauncherMode WindowsTerminal
```

Omit `-LauncherMode` to retain the backward-compatible `Both` behavior. Use `Direct` when Windows Terminal is intentionally not part of the workflow.

The install action is idempotent and does not change the WSL default user, request elevation, modify Windows Terminal settings, or change the context-menu style. Before registry writes it snapshots every affected subtree. A failed operation restores the pre-run state; an unrecoverable import error reports the retained `.reg` backup path.

Use `-WhatIf` before applying a change on another workstation:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Install `
  -LauncherMode WindowsTerminal `
  -WhatIf
```

## 4. Ubuntu-native Windows Terminal theme

Install the optional theme after confirming the exact profile:

```powershell
.\scripts\configure-windows-terminal-ubuntu-theme.ps1 `
  -Action Install `
  -TerminalProfile Ubuntu
```

The script reads the profile GUID from `settings.json`, then writes one UTF-8 JSON Fragment at:

```text
%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\bootstrap-wsl-ai-dev\ubuntu-native.json
```

This follows Windows Terminal's supported per-user Fragment extension model. It avoids reformatting or replacing the user's complete `settings.json`. The script validates the generated fragment before installation, refuses a foreign or modified file at its owned path, and reports the profile GUID in status output.

Explicit appearance properties already stored for the same profile in the user's `settings.json` can take precedence over Fragment defaults. The script preserves those user settings rather than deleting them silently.

## 5. Windows 11 context-menu behavior

Registry shell verbs normally appear under **Show more options** in the compact Windows 11 menu. Promoting one custom verb into the compact menu requires a packaged `IExplorerCommand` shell extension and is outside this feature.

After explicit approval, enable the full classic context menu for the current user:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Status `
  -ClassicContextMenu Enable `
  -RestartExplorer
```

This switch uses an undocumented Windows 11 compatibility override. It is reversible, but an operating-system update may stop honoring it. `-RestartExplorer` remains explicit because Explorer windows and the taskbar briefly disappear.

Restore the compact menu without removing launchers or the Terminal theme:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 `
  -Action Status `
  -ClassicContextMenu Disable `
  -RestartExplorer
```

## 6. Verify and remove

Test both Explorer targets after installation:

1. Right-click the background of a directory containing spaces in its path.
2. Right-click a selected folder.
3. Confirm the selected launcher opens the requested directory.
4. For Windows Terminal, confirm a new `Ubuntu` profile window uses the aubergine background and orange tab when the theme is installed.
5. Run both status actions again and inspect ownership, selected launcher mode, profile GUID, and classic-menu state.

Remove all project-owned Explorer launchers while leaving the theme and classic-menu choice unchanged:

```powershell
.\scripts\configure-windows-explorer-wsl.ps1 -Action Remove
```

Remove only the project-owned Terminal Fragment:

```powershell
.\scripts\configure-windows-terminal-ubuntu-theme.ps1 -Action Remove
```

Removal leaves a foreign or modified fragment untouched and emits a warning. It deletes the project Fragment directory only when that directory is empty.

## 7. Implementation model

Explorer supplies `%V` for a directory-background command and `%1` for a selected-folder command. The script registers selected targets under the current user's `Directory\Background\shell` and `Directory\shell` branches.

The direct command follows this shape:

```text
wsl.exe -d DISTRIBUTION --cd "%V_OR_%1"
```

The Windows Terminal command forces a new window and selects the named profile:

```text
wt.exe -w new nt -p "PROFILE" -d "%V_OR_%1"
```

The theme Fragment updates the discovered profile by GUID and defines the complete `Ubuntu Native` color table. Removing the fragment reverts Terminal to the remaining built-in and user settings.

The classic-menu switch manages the per-user `InprocServer32` override for CLSID `{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}`. Disable removes it only when its state matches the known empty-value override, so unrelated registry content is not silently deleted.
