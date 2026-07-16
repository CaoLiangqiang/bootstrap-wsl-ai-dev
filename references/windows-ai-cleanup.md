# Windows AI Tool Inventory and Cleanup

This workflow decides each Windows AI tool individually before changing it. It intentionally does not provide a bulk-delete script.

## Contents

1. Decision rule
2. Read-only inventory
3. Validated policy from the completed migration
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

The same script can be launched explicitly from WSL after PATH isolation:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -NoProfile -File "$(wslpath -w "$PWD/scripts/audit-windows-ai-tools.ps1")"
```

Also inspect tool-specific IDE extensions and running processes. Do not infer ownership from a directory name alone.

## 3. Validated policy from the completed migration

### Retained on Windows

- Kiro IDE and Kiro CLI.
- Codex App and Codex CLI.
- ChatGPT Desktop.
- Feishu/Lark CLI and MCP commands needed by Windows Kiro.
- General Windows development tools such as npm, pnpm, nrm, and port-whisperer.
- Private Claude Code and OpenCode configuration/history as offline backups, without an active Windows executable.

### Removed from Windows

- Gemini.
- MiCode.
- Crush.
- Claude Code executable, package, and editor extension.
- OpenCode package and launch script.
- Paseo.
- Happy and happy-coder.
- uipro and uipro-cli.
- Broken `agentic-hackathon` residue.
- `claudeway.cmd`.
- `figma-mcp`.
- `gerrit-mcp`.
- `playwright-cli`.
- `defuddle`.

These names describe one workstation's approved policy. Reconfirm before applying it elsewhere.

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

Removing an executable while retaining private configuration is valid. For Claude Code and OpenCode, the completed migration kept Windows configuration/history only as backup while removing command shims and packages.

Do not leave a backup directory on WSL PATH. Do not symlink WSL configuration to the backup. Copy only reviewed portable settings, rewrite Windows paths, set Linux file mode `600`, and migrate authentication separately.

Session histories can contain prompts, source fragments, URLs, and secrets. Never commit them to this repository.

## 6. Post-cleanup verification

From Windows PowerShell, confirm retained tools still work and removed tools do not resolve:

```powershell
codex --version
kiro-cli --version
Get-Command claude, opencode, gemini, micode, crush -All -ErrorAction SilentlyContinue
```

From a new WSL process after `wsl --shutdown`, run:

```bash
bash scripts/verify-ai-cli-migration.sh --strict
```

The Windows Codex and Kiro commands should remain usable in Windows while their paths remain invisible to normal WSL command lookup. That is isolation, not duplication pollution.
