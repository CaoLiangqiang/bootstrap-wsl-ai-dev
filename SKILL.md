---
name: bootstrap-wsl-ai-dev
description: Audit, clean, migrate, isolate, and bootstrap an AI development environment on WSL Ubuntu without accidental dependence on Windows-installed tools. Use when Codex needs to classify Windows versus WSL command origins, disable automatic Windows PATH import while preserving explicit interop, inventory or remove Windows AI tools, migrate Claude Code, OpenCode/oh-my-openagent, Codex, Kiro, Feishu/Lark, Node/Bun, or uv into WSL, validate configuration and authentication without exposing secrets, diagnose network or Docker issues, or clean installation artifacts without deleting useful caches or credentials.
---

# Bootstrap WSL AI Development

Build a native WSL Ubuntu toolchain with an audit-first workflow. Treat Windows, WSL, system services, and the current shell as separate state layers.

## Safety rules

- Start read-only. Run scripts/audit-wsl-ai-env.sh before changing packages, PATH, registries, credentials, or files.
- Never ask for sudo passwords, API keys, access tokens, or private-key contents. Let the user enter passwords and complete browser authorization locally.
- Distinguish an installed Windows program from a Windows PATH entry and from a stale PATH snapshot inherited by an already-running WSL session.
- Confirm every deletion candidate by path, size, owner, command resolution, and replacement readiness. Preserve projects, SSH keys, auth files, active tool state, and caches that are valuable on a slow network.
- Use official repositories and documentation for system packages and security-sensitive configuration.
- Keep Windows writes targeted. Read registry values before editing them, preserve their value type, and never broadly rewrite PATH without showing the effect.
- Treat PATH isolation and network configuration as independent decisions. Do not modify Clash, proxy, DNS, NAT, mirrored networking, or other network settings unless the user explicitly asks for network work.
- Never copy personal settings, auth files, steering content, or session history into this repository. Record schemas, redacted examples, permission requirements, and validation commands instead.
- Use apply_patch for files inside the working repository. For root-owned files, generate a small auditable script and ask the user to run it with sudo.

## Workflow

### 1. Establish the target state

Record:

- WSL distribution and version.
- AI tools to keep on Windows.
- AI tools to keep or install in WSL.
- Whether Windows executables should be imported into WSL PATH or remain callable only by explicit absolute path.
- Current proxy product, scheme, host, and port without exposing credentials.
- Preferred GitHub authentication method.

Default to native WSL binaries for development commands. Do not remove unrelated Windows developer tools merely because WSL can see them.

### 2. Audit command origins and residuals

Run:

    bash scripts/audit-wsl-ai-env.sh

For the Windows side, run from Windows PowerShell:

    .\scripts\audit-windows-ai-tools.ps1

Use command -v and type -a to classify each command:

- /usr, /bin, /home, or a WSL-managed version directory: WSL-native.
- /mnt/c, /mnt/d, or another DrvFs mount: Windows executable.
- Missing target with a PATH entry that no longer exists: stale Windows residue.

If command output and the Windows registry disagree, treat the current WSL PATH as an old process snapshot. Recheck after wsl --shutdown from Windows PowerShell.

Read references/lessons.md when the audit produces contradictory results or when evaluating cleanup candidates.

### 3. Establish the WSL command boundary

When the target is a fully native WSL command-line environment, review and run:

    bash scripts/configure-wsl-path-isolation.sh --check
    sudo bash scripts/configure-wsl-path-isolation.sh

This sets only `[interop] appendWindowsPath=false`. It preserves WSL interop and all networking sections. Afterward, have the user run `wsl --shutdown` from Windows PowerShell and re-open WSL.

Do not simulate completion with a sanitized child environment. Verify the real restarted shell with:

    bash scripts/verify-ai-cli-migration.sh

Read references/ai-cli-migration.md for the boundary model and references/windows-ai-cleanup.md before removing Windows tools.

### 4. Diagnose the network before installing

Test both the current environment and an explicit proxy:

    bash scripts/check-network.sh
    bash scripts/check-network.sh --proxy http://127.0.0.1:7897

Compare GitHub, Docker Registry, Docker packages, npm, and Astral endpoints. A Docker Registry HTTP 401 response proves reachability; it is not a failure.

Do not assume that a working curl or apt proxy also configures Docker. The Docker daemon is a systemd service and needs its own proxy configuration.

Skip this section when the current network is already healthy and the user did not request proxy changes.

### 5. Prepare the native WSL toolchain

Prefer this baseline:

- Git, OpenSSH client, curl, wget, jq, build-essential, cmake, and pkg-config from Ubuntu.
- Python from Ubuntu for system use; uv for project environments, managed Python versions, and Python tools.
- Node through one WSL-native version manager; Corepack for pnpm or Yarn.
- Bun installed under the Linux home directory when tools require it.
- Codex, Kiro CLI, Claude Code, OpenCode, and Feishu/Lark commands installed under WSL directories, not resolved through `/mnt`.

After enabling Corepack, verify command -v pnpm points to the WSL Node directory. Do not accept a Windows pnpm shim as the final state.

### 6. Configure GitHub access

Verify SSH key and directory permissions without printing private keys. Test port 22 with a finite timeout.

If port 22 hangs, test GitHub SSH over port 443:

    ssh -T -p 443 git@ssh.github.com

Only after successful authentication, configure the github.com host to use ssh.github.com and port 443. Verify the host fingerprint against GitHub documentation before accepting it.

Run gh auth login in the user's terminal. If a headless WSL environment stores credentials in ~/.config/gh/hosts.yml, verify the file mode is 600 and never print its contents.

### 7. Migrate AI CLI configuration

Read references/ai-cli-migration.md and migrate one tool at a time. For each tool:

1. Install and resolve the native WSL command.
2. Copy only reviewed portable settings.
3. Rewrite Windows command and MCP paths to Linux paths.
4. Migrate authentication into private local state with mode `600`; never print or commit it.
5. Run the tool's own status or Doctor command.
6. Only then remove the unwanted Windows executable.

Important tool-specific boundaries:

- Claude user-wide settings belong in `~/.claude/settings.json`; project-local overrides belong in `<project>/.claude/settings.local.json`.
- OpenCode Responses routes use `@ai-sdk/openai`; keep provider-specific beta headers scoped to that provider.
- Windows and WSL Codex state must remain separate. Full-auto permissions are an explicit opt-in.
- Kiro skills, steering, shell integration, and MCP commands must use Linux-owned paths. Run Qterm diagnostics in a real terminal, not a nested agent PTY.
- Do not install plugins merely because they existed on Windows; install only those the user approves.

### 8. Install Docker Engine

Require systemd. If it is unavailable, enable it in /etc/wsl.conf and have the user restart WSL before proceeding.

Review and run:

    sudo bash scripts/install-docker-engine.sh

The script installs Docker from Docker's official Ubuntu repository, enables the service, and adds the invoking user to the docker group. Do not test non-root Docker access in an agent process that started before the group change. Use a new login shell or a new WSL terminal.

If image pulls time out while curl through the proxy works, review and run:

    sudo bash scripts/configure-docker-proxy.sh --proxy http://127.0.0.1:7897 --test

Keep the daemon proxy address synchronized with the Windows proxy port.

### 9. Clean only verified artifacts

Typical safe candidates include:

- Downloaded installer archives after the installed binary and update path are verified.
- One-time installation scripts.
- Old standalone Codex release directories after codex doctor confirms the current release and current symlink.
- APT package archives after installation succeeds.
- The hello-world test image after Docker validation.
- Empty npm scope directories left by uninstalled tools.
- Windows PATH entries whose target directory is confirmed absent.
- Windows command shims whose owning AI package is confirmed removed.

Do not automatically delete:

- ~/.ssh, ~/.config/gh, ~/.codex state databases, or provider auth files.
- npm, uv, or package-manager caches on a slow network unless corrupt or explicitly unwanted.
- Active /tmp directories belonging to Codex, Node, tmux, or sandbox processes.
- Model directories, project repositories, Docker volumes, or container images not created by the workflow.
- Windows Claude/OpenCode configuration or history retained intentionally as a private backup.

Run npm cache verify before considering npm cache deletion. Prefer apt-get clean over autoremove unless package dependency impact has been reviewed.

### 10. Validate the finished environment

Confirm:

- All intended commands resolve to WSL paths.
- No `/mnt/<drive>` directory appears in the restarted WSL PATH when full isolation was selected.
- Windows-only and removed commands are absent from WSL command discovery.
- Explicit absolute-path Windows interop still works when it is intended to remain enabled.
- Codex doctor reports no failures.
- Kiro Doctor passes configuration checks; interpret Qterm only from a real parent terminal.
- Claude and GitHub authentication status checks succeed without printing credentials.
- OpenCode and oh-my-openagent provider, LSP, and Team Mode checks succeed when selected.
- GitHub SSH and gh API authentication work.
- Docker and Compose report versions; Docker is active and enabled.
- A non-root user can pull and run hello-world.
- Docker daemon proxy environment is active when required.
- Kimi, Trae, and other removed tools have no executable, registered install, live process, or surviving data directory.
- Temporary scripts and staged configuration files are removed.

Summarize retained caches and configuration intentionally. Finish with wsl --shutdown when PATH, group, systemd, or Windows registry state must be refreshed.

## Resource routing

- Read references/lessons.md for the chronological field notes, failure signatures, cleanup decisions, and security guidance distilled from a real migration.
- Read references/ai-cli-migration.md for the complete Windows/WSL boundary and per-tool Claude, OpenCode, Codex, Kiro, and Feishu migration procedure.
- Read references/windows-ai-cleanup.md before inventorying or removing Windows AI applications, shims, packages, and residual state.
- Read references/validated-state-2026-07-16.md for the evidence snapshot and versions from the completed migration; do not treat it as a version lock.
- Read references/sources.md before changing WSL, Docker, GitHub SSH, Corepack, or uv behavior; verify current official guidance if versions have changed.
- Run scripts/audit-wsl-ai-env.sh for the first and final inventory.
- Run scripts/audit-windows-ai-tools.ps1 from Windows PowerShell for a read-only Windows inventory.
- Run scripts/configure-wsl-path-isolation.sh only after the user chooses native WSL command isolation.
- Run scripts/verify-ai-cli-migration.sh after a full WSL restart.
- Run scripts/check-network.sh before blaming Git, apt, npm, uv, or Docker.
- Use scripts/install-docker-engine.sh only after reviewing conflicts and obtaining local sudo authentication.
- Use scripts/configure-docker-proxy.sh only when the daemon needs an explicit proxy or its current proxy is stale.
