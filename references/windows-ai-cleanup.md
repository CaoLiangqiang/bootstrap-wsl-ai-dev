# Windows AI Tool Inventory and Cleanup

This workflow decides each Windows AI tool individually before changing it. It intentionally does not provide a bulk-delete script.

## Contents

1. Decision rule
2. Read-only inventory
3. Target matrix
4. Removal sequence
5. Configuration versus executable cleanup
6. Post-cleanup verification

## 1. Decision rule

For every tool, record one of three outcomes:

1. **Keep on Windows**: retain the Windows executable and its Windows configuration. WSL must still use a separate Linux installation.
2. **Move to WSL**: install and validate the Linux replacement, then remove the Windows executable. Retain a private Windows configuration backup only when it has recovery value.
3. **Remove entirely**: uninstall the executable, then review shims, extensions, state directories, scheduled tasks, and PATH entries individually.

An application registration, an npm shim, a configuration directory, and a live PATH entry are separate state. Removing one does not prove the others are gone.

## 2. Read-only inventory

Run from Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\audit-windows-ai-tools.ps1
```

Add `-IncludeWinget` for the complete winget inventory. The script reads command resolution, Appx packages, uninstall registrations, and npm shims. It does not uninstall or delete anything.

After reviewing the machine, pass only the decisions made for that workstation:

```powershell
.\scripts\audit-windows-ai-tools.ps1 `
  -KeepOnWindows codex,kiro-cli `
  -RemoveFromWindows claude,opencode
```

Commands not named in either list remain labeled `review`. The lists only annotate the read-only report; they do not uninstall software. A command cannot appear in both lists.

The same script can be launched explicitly from WSL after PATH isolation:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -NoProfile -File "$(wslpath -w "$PWD/scripts/audit-windows-ai-tools.ps1")"
```

Also inspect tool-specific IDE extensions and running processes. Do not infer ownership from a directory name alone.

## 3. Target matrix

Create a workstation-specific target matrix before removing anything:

| Tool | Current owner and path | Target state | Replacement verified | Private state decision |
| --- | --- | --- | --- | --- |
| `<tool>` | `<installer and path>` | Keep on Windows / Move to WSL / Remove | Yes / No | Keep / Migrate / Delete |

Do not ship or reuse another workstation's approved tool list. General Windows developer tools, desktop applications, AI CLIs, editor extensions, command shims, and private configuration are separate decisions. A tool may remain on Windows while WSL uses an isolated Linux installation.

## 4. Removal sequence

For each approved removal:

1. Record `Get-Command <name> -All` output and the owning installer.
2. Stop active processes belonging to that tool.
3. Use its original package manager or registered uninstaller.
4. Re-run command discovery.
5. Remove only orphaned shims whose package or target is confirmed absent.
6. Review state and cache directories separately from executables.
7. Preserve credentials or history only when the user explicitly wants a backup.
8. Recheck Windows user and system PATH entries.

Typical uninstall mechanisms include:

```powershell
winget uninstall --id '<exact-package-id>'
npm uninstall --global '<exact-package-name>'
Get-AppxPackage -Name '<exact-package-name>' | Remove-AppxPackage
```

Do not run these examples with guessed identifiers. Display the exact match first and verify it belongs to the intended application.

## 5. Configuration versus executable cleanup

Removing an executable while retaining private configuration is valid when the user explicitly chooses that target state.

Do not leave a backup directory on WSL PATH. Do not symlink WSL configuration to the backup. Copy only reviewed portable settings, rewrite Windows paths, set Linux file mode `600`, and migrate authentication separately.

Session histories can contain prompts, source fragments, URLs, and secrets. Never commit them to this repository.

## 6. Post-cleanup verification

From Windows PowerShell, confirm retained tools still work and each tool approved for removal no longer resolves:

```powershell
Get-Command <retained-command> -All
Get-Command <removed-command> -All -ErrorAction SilentlyContinue
```

From a new WSL process after `wsl --shutdown`, run:

```bash
bash scripts/verify-ai-cli-migration.sh \
  --require-native '<WSL-command>' \
  --expect-absent '<Windows-only-or-removed-command>'
```

Windows commands intentionally retained in the target matrix should remain usable in Windows while their paths remain invisible to normal WSL command lookup. That is isolation, not duplication pollution.
