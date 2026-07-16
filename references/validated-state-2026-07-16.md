# Validated Workstation State: 2026-07-16

This is an evidence snapshot from the migration that produced the current workflow. It is not a version lock file.

## WSL Ubuntu toolchain

| Tool | Validated version | Origin |
| --- | --- | --- |
| Codex CLI | 0.144.5 | WSL NVM global package |
| Kiro CLI | 2.12.3 | `~/.local/bin` |
| Claude Code | 2.1.211 | WSL NVM global package |
| OpenCode | 1.18.2 | WSL NVM global package |
| Node | 24.18.0 | WSL NVM |
| npm | 11.16.0 | WSL NVM |
| pnpm | 10.29.3 | WSL NVM/Corepack |
| Bun | 1.3.14 | `~/.bun/bin` |
| ast-grep | 0.44.1 | WSL NVM global package |
| Feishu CLI | 1.3.0 | WSL NVM global package |
| Feishu MCP Pro | 0.23.0 | WSL NVM global package |
| Lark CLI | 1.0.45 | WSL NVM global package |
| uv | 0.11.28 | `~/.local/bin` |

All intended commands resolved to Linux paths after a full WSL restart.

## WSL boundary

`/etc/wsl.conf` retained systemd and the default user while adding only:

```ini
[interop]
appendWindowsPath=false
```

The restarted shell had zero `/mnt/<drive>` PATH entries. `cmd.exe`, `powershell.exe`, and Windows npm shims were absent from normal command discovery. Calling `/mnt/c/Windows/System32/cmd.exe` explicitly still worked.

No Clash, proxy, DNS, NAT, mirrored-networking, or other network configuration was changed as part of PATH isolation.

## Codex

- Model provider used the Responses API.
- Approval policy was `never`.
- Sandbox mode was `danger-full-access` with network enabled.
- `config.toml` and `auth.json` used mode `600`.
- Doctor result after restart: `17 ok`, `1 idle`, `1 note`, `0 warn`, `0 fail`.
- The unrestricted-filesystem note was expected for the chosen policy.

## Claude Code

- Authentication worked in WSL.
- Automatic updates were enabled.
- `API_TIMEOUT_MS` was set to `600000`.
- In-process agent teams were enabled.
- `skipDangerousModePermissionPrompt=true` was retained by explicit user decision.
- No plugins were installed during migration.
- User settings and `CLAUDE.md` were local private files; authentication was not committed.

## OpenCode

- A Responses provider used `@ai-sdk/openai`.
- The required header was `x-codex-beta-features: memories,remote_compaction_v2`.
- Luna, Sol, and Terra route tests passed.
- oh-my-openagent 4.18.1 was installed.
- LSP and Team Mode were enabled.
- Plugin Doctor passed all seven checks.
- Windows executable/package state was removed while private configuration/history was retained as backup.

## Kiro

- Default model was `claude-opus-4.8` with `xhigh` effort.
- Sonnet 5 retained `max` effort.
- Three steering files were migrated.
- The explicit permission rule allowed all capabilities.
- Thirty-two active skills were copied into Linux-owned storage.
- Skill links and MCP commands referenced only Linux paths.
- Feishu MCP used the native WSL executable.
- Shell integration was installed in `.bashrc` and `.profile`.
- Auth, settings, and compatibility checks passed.

Kiro's Qterm socket test must run in a real terminal. During final inspection, the actual Windows Terminal WSL session was wrapped by `kiro-cli-term` and its Unix socket was listening; a nested Codex-created PTY timed out because it was not the parent terminal session.

## Windows retained state

- OpenAI Codex App package and Codex CLI 0.139.0.
- Kiro IDE 1.0.138 and Kiro CLI 2.12.1.
- ChatGPT Desktop.
- Windows Feishu/Lark tools required by Windows Kiro.

Windows and WSL versions do not need to match exactly. They must be independently updateable and must not resolve across the WSL PATH boundary.

## Removed command residue

After restart, none of these commands resolved in WSL:

```text
gemini micode crush paseo happy happy-coder uipro uipro-cli
agentic-hackathon figma-mcp gerrit-mcp playwright-cli defuddle
claude-on-Windows opencode-on-Windows
```

Linux-native `claude` and `opencode` remained available. The labels above distinguish the removed Windows executables from the WSL commands with the same names.
