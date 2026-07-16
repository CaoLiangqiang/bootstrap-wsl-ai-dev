# Native WSL AI CLI Migration

This guide captures a completed migration in which Windows keeps selected desktop tools while command-line AI development runs natively in WSL Ubuntu.

## Contents

1. Target architecture
2. Isolate command resolution
3. Build a stable Linux shell toolchain
4. Claude Code
5. OpenCode and oh-my-openagent
6. Codex
7. Kiro CLI
8. Feishu and Lark tools
9. Final verification

## 1. Target architecture

Use separate installations and separate state directories on each operating system.

| Tool or state | Windows | WSL Ubuntu |
| --- | --- | --- |
| Codex App and CLI | Keep | Install native CLI |
| Kiro IDE and CLI | Keep | Install native CLI |
| ChatGPT Desktop | Keep | Not required |
| Claude Code | Remove executable; retain backup only if useful | Install, authenticate, and configure |
| OpenCode | Remove executable; retain backup only if useful | Install and configure |
| Node, npm, pnpm, Bun, uv | May remain for Windows work | Install native copies |
| Feishu/Lark commands | Keep when Windows Kiro needs them | Install native copies for WSL tools |
| Credentials and history | Keep private Windows state only where needed | Migrate deliberately; never symlink across `/mnt` |

Shared project files under `/mnt/c` are not automatically pollution. Cross-environment command resolution is the problem: a WSL shell must not silently run a Windows `.exe`, `.cmd`, or npm shim because Windows PATH was appended.

## 2. Isolate command resolution

Keep WSL interop enabled but disable automatic Windows PATH import:

```ini
[boot]
systemd=true

[interop]
appendWindowsPath=false
```

Use the repository script to preserve unrelated sections, including any network settings:

```bash
bash scripts/configure-wsl-path-isolation.sh --check
sudo bash scripts/configure-wsl-path-isolation.sh
```

Then run `wsl --shutdown` from Windows PowerShell and open a new WSL terminal.

Expected behavior:

```bash
command -v codex kiro-cli claude opencode
command -v cmd.exe powershell.exe explorer.exe
/mnt/c/Windows/System32/cmd.exe /d /c "exit 0"
```

The first group must resolve to Linux paths, the second group must be absent, and the explicit absolute Windows command must still work.

`/usr/lib/wsl/lib` is a normal WSL runtime path. It is not the same as importing Windows executable directories from `/mnt/c`.

## 3. Build a stable Linux shell toolchain

Use one native Node version manager. With NVM, set a default and load it from both interactive and login shells:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v nvm >/dev/null 2>&1 && nvm use --silent default >/dev/null
```

Install Bun under the Linux home directory and ensure `$HOME/.local/bin` is present. Make PATH additions idempotent when editing shell startup files:

```bash
path_prepend() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

path_prepend "$HOME/.local/bin"
[ -d "$HOME/.bun/bin" ] && path_prepend "$HOME/.bun/bin"
export PATH
```

Do not point WSL package-manager shims at `%APPDATA%\npm`.

## 4. Claude Code

### File scopes

- `~/.claude/settings.json` is the user-wide settings file.
- `<project>/.claude/settings.json` is the project-shared settings file.
- `<project>/.claude/settings.local.json` is a project-local override and should normally be gitignored.
- `~/.claude/settings.local.json` is not a second universal user settings layer. It only acts as a local project file when the home directory itself is the project context.
- `~/.claude/CLAUDE.md` contains user-wide instructions. Project `CLAUDE.md` files remain project-specific.

For a WSL-only Claude installation, migrate intentional user settings into `~/.claude/settings.json` and remove obsolete Windows paths. Do not install Windows plugins automatically.

### Validated settings pattern

The completed migration used a ten-minute API timeout and enabled in-process agent teams:

```json
{
  "skipDangerousModePermissionPrompt": true,
  "teammateMode": "in-process",
  "env": {
    "API_TIMEOUT_MS": "600000",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_TEAMMATE_MODE": "in-process"
  }
}
```

`skipDangerousModePermissionPrompt=true` is an explicit high-trust choice, not a safe default for other users. Document it and do not silently enable it.

To restore automatic updates, remove stale `DISABLE_AUTOUPDATER` settings rather than pinning an old executable. Validate with:

```bash
command -v claude
claude --version
claude auth status
stat -c '%a %n' ~/.claude/settings.json
```

If a compatible endpoint uses `ANTHROPIC_AUTH_TOKEN`, keep it only in a private local file or secret environment source. Set sensitive configuration mode to `600`; never put the token or a complete personal `CLAUDE.md` in this repository.

## 5. OpenCode and oh-my-openagent

Use the WSL Node installation for OpenCode. The primary configuration belongs in `~/.config/opencode/opencode.json`, and oh-my-openagent configuration belongs in `~/.config/opencode/oh-my-openagent.json`.

For an OpenAI Responses-compatible router, use the Responses provider rather than the generic compatibility provider:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": true,
  "plugin": ["oh-my-openagent@latest"],
  "provider": {
    "api-router-codex": {
      "npm": "@ai-sdk/openai",
      "options": {
        "baseURL": "{env:AI_ROUTER_BASE_URL}",
        "apiKey": "{env:AI_ROUTER_API_KEY}",
        "headers": {
          "x-codex-beta-features": "memories,remote_compaction_v2"
        }
      },
      "models": {}
    }
  }
}
```

The `x-codex-beta-features` header is required by the validated Responses route. Other providers should not receive it automatically.

LSP support is available unless it is explicitly disabled. Keep LSP out of disabled-tool lists and verify the language server binaries resolve inside WSL. A minimal team-mode block is:

```json
{
  "experimental": {
    "task_system": true
  },
  "team_mode": {
    "enabled": true,
    "max_parallel_members": 4,
    "max_members": 8
  }
}
```

Keep provider keys private and run the plugin doctor after changes. Do not copy OpenCode history or cache into the repository.

## 6. Codex

Keep Windows Codex and WSL Codex as separate installations. Do not symlink `%USERPROFILE%\.codex` to `~/.codex`.

The completed WSL environment intentionally grants Codex full automation:

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
network_access = "enabled"
```

This is an explicit workstation policy with unrestricted filesystem and network impact. A bootstrap workflow must show the consequence and obtain the user's decision before applying it.

Provider configuration may include a base URL and model metadata, but secrets belong in private authentication state or environment variables. Protect both files:

```bash
chmod 600 ~/.codex/config.toml ~/.codex/auth.json
codex doctor --summary --ascii --no-color
```

The unrestricted-access note in Doctor is expected when this policy is selected; actual warnings or failures still require investigation.

## 7. Kiro CLI

Windows Kiro can remain available while WSL Kiro uses its own state under `~/.kiro`.

Migrate only portable settings:

- Default model and model effort from Windows `cli.json`.
- Steering files into `~/.kiro/steering`.
- Skills into a Linux-owned directory such as `~/.agents/skills`.
- Permission rules after explicit review.
- MCP definitions after every command path has been replaced with a Linux path.

Do not symlink WSL skills, steering, sessions, or executables to a Windows directory. Validate every symlink target with `readlink`.

Example CLI settings:

```json
{
  "chat.defaultModel": "claude-opus-4.8",
  "chat.modelDefaults": {
    "claude-sonnet-5": {
      "output_config": { "effort": "max" }
    },
    "claude-opus-4.8": {
      "output_config": { "effort": "xhigh" }
    }
  }
}
```

The validated permissive rule is:

```yaml
rules:
  - capability: all
    effect: allow
```

This rule is equivalent to broad local autonomy and must not be enabled silently.

For a native Feishu MCP, record the result of `command -v feishu-mcp-pro` in `~/.kiro/settings/mcp.json`. The path must begin with a Linux directory such as `/home`, never `/mnt/c`.

Kiro installs pre/post shell blocks in `~/.bashrc` and `~/.profile`. Keep the pre block at the top and the post block at the bottom. Run:

```bash
kiro-cli doctor --all
```

Run the Qterm test directly in a normal Windows Terminal WSL shell. A nested pseudo-terminal created inside Codex, Claude, or OpenCode can produce a raw-mode or socket timeout even when the real parent terminal wrapper and socket are healthy.

## 8. Feishu and Lark tools

Install the WSL copies through the native Node toolchain and verify:

```bash
command -v feishu feishu-mcp-pro lark-cli
feishu --version
lark-cli --version
```

Migrate credentials only into the tool's Linux configuration directory, preserve mode `600`, and validate authentication without printing tokens. Keep separate Windows credentials only when Windows Kiro still consumes those commands.

## 9. Final verification

Run both audits after restarting WSL:

```bash
bash scripts/audit-wsl-ai-env.sh
bash scripts/verify-ai-cli-migration.sh --strict
```

`--strict` enforces the complete validated workstation profile, including Codex, Kiro, Feishu/Lark, uv, and Docker. Omit it for a partial migration and review missing-tool warnings against the user's chosen target matrix.

The desired result is:

- No `/mnt/<drive>` entry in WSL PATH.
- All intended CLIs resolve to Linux paths.
- Removed and Windows-only commands are absent from WSL command resolution.
- Explicit absolute-path Windows interop still works.
- Configuration files are private and contain no Windows executable paths.
- Codex Doctor reports zero failures.
- Kiro configuration checks pass in a real terminal.

Do not change Clash, mirrored networking, NAT, DNS, or proxy settings merely to achieve command isolation. `appendWindowsPath=false` solves a different boundary and can be applied without touching networking.
