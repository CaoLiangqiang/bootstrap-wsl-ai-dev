---
name: bootstrap-wsl-ai-dev
description: Audit, clean, migrate, and bootstrap an AI development environment on WSL Ubuntu while reducing accidental dependence on Windows-installed tools. Use when Codex needs to identify Windows versus WSL command origins, remove Kimi/Trae or other AI-tool remnants, diagnose slow Git or package downloads, configure proxies, prepare Git/GitHub SSH, install Python/uv and Node/Corepack tooling, install Docker Engine in WSL, repair Docker daemon proxy failures, validate Codex or Claude CLI placement, or clean installation artifacts without deleting useful caches or credentials.
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
- Use apply_patch for files inside the working repository. For root-owned files, generate a small auditable script and ask the user to run it with sudo.

## Workflow

### 1. Establish the target state

Record:

- WSL distribution and version.
- AI tools to keep on Windows.
- AI tools to keep or install in WSL.
- Whether Windows executables should remain callable from WSL.
- Current proxy product, scheme, host, and port without exposing credentials.
- Preferred GitHub authentication method.

Default to native WSL binaries for development commands. Do not remove unrelated Windows developer tools merely because WSL can see them.

### 2. Audit command origins and residuals

Run:

    bash scripts/audit-wsl-ai-env.sh

Use command -v and type -a to classify each command:

- /usr, /bin, /home, or a WSL-managed version directory: WSL-native.
- /mnt/c, /mnt/d, or another DrvFs mount: Windows executable.
- Missing target with a PATH entry that no longer exists: stale Windows residue.

If command output and the Windows registry disagree, treat the current WSL PATH as an old process snapshot. Recheck after wsl --shutdown from Windows PowerShell.

Read references/lessons.md when the audit produces contradictory results or when evaluating cleanup candidates.

### 3. Diagnose the network before installing

Test both the current environment and an explicit proxy:

    bash scripts/check-network.sh
    bash scripts/check-network.sh --proxy http://127.0.0.1:7897

Compare GitHub, Docker Registry, Docker packages, npm, and Astral endpoints. A Docker Registry HTTP 401 response proves reachability; it is not a failure.

Do not assume that a working curl or apt proxy also configures Docker. The Docker daemon is a systemd service and needs its own proxy configuration.

### 4. Prepare the native WSL toolchain

Prefer this baseline:

- Git, OpenSSH client, curl, wget, jq, build-essential, cmake, and pkg-config from Ubuntu.
- Python from Ubuntu for system use; uv for project environments, managed Python versions, and Python tools.
- Node through one WSL-native version manager; Corepack for pnpm or Yarn.
- Codex and other AI CLIs installed under WSL home directories, not resolved through /mnt.

After enabling Corepack, verify command -v pnpm points to the WSL Node directory. Do not accept a Windows pnpm shim as the final state.

### 5. Configure GitHub access

Verify SSH key and directory permissions without printing private keys. Test port 22 with a finite timeout.

If port 22 hangs, test GitHub SSH over port 443:

    ssh -T -p 443 git@ssh.github.com

Only after successful authentication, configure the github.com host to use ssh.github.com and port 443. Verify the host fingerprint against GitHub documentation before accepting it.

Run gh auth login in the user's terminal. If a headless WSL environment stores credentials in ~/.config/gh/hosts.yml, verify the file mode is 600 and never print its contents.

### 6. Install Docker Engine

Require systemd. If it is unavailable, enable it in /etc/wsl.conf and have the user restart WSL before proceeding.

Review and run:

    sudo bash scripts/install-docker-engine.sh

The script installs Docker from Docker's official Ubuntu repository, enables the service, and adds the invoking user to the docker group. Do not test non-root Docker access in an agent process that started before the group change. Use a new login shell or a new WSL terminal.

If image pulls time out while curl through the proxy works, review and run:

    sudo bash scripts/configure-docker-proxy.sh --proxy http://127.0.0.1:7897 --test

Keep the daemon proxy address synchronized with the Windows proxy port.

### 7. Clean only verified artifacts

Typical safe candidates include:

- Downloaded installer archives after the installed binary and update path are verified.
- One-time installation scripts.
- Old standalone Codex release directories after codex doctor confirms the current release and current symlink.
- APT package archives after installation succeeds.
- The hello-world test image after Docker validation.
- Empty npm scope directories left by uninstalled tools.
- Windows PATH entries whose target directory is confirmed absent.

Do not automatically delete:

- ~/.ssh, ~/.config/gh, ~/.codex state databases, or provider auth files.
- npm, uv, or package-manager caches on a slow network unless corrupt or explicitly unwanted.
- Active /tmp directories belonging to Codex, Node, tmux, or sandbox processes.
- Model directories, project repositories, Docker volumes, or container images not created by the workflow.

Run npm cache verify before considering npm cache deletion. Prefer apt-get clean over autoremove unless package dependency impact has been reviewed.

### 8. Validate the finished environment

Confirm:

- All intended commands resolve to WSL paths.
- Codex doctor reports no failures.
- GitHub SSH and gh API authentication work.
- Docker and Compose report versions; Docker is active and enabled.
- A non-root user can pull and run hello-world.
- Docker daemon proxy environment is active when required.
- Kimi, Trae, and other removed tools have no executable, registered install, live process, or surviving data directory.
- Temporary scripts and staged configuration files are removed.

Summarize retained caches and configuration intentionally. Finish with wsl --shutdown when PATH, group, systemd, or Windows registry state must be refreshed.

## Resource routing

- Read references/lessons.md for the chronological field notes, failure signatures, cleanup decisions, and security guidance distilled from a real migration.
- Read references/sources.md before changing WSL, Docker, GitHub SSH, Corepack, or uv behavior; verify current official guidance if versions have changed.
- Run scripts/audit-wsl-ai-env.sh for the first and final inventory.
- Run scripts/check-network.sh before blaming Git, apt, npm, uv, or Docker.
- Use scripts/install-docker-engine.sh only after reviewing conflicts and obtaining local sudo authentication.
- Use scripts/configure-docker-proxy.sh only when the daemon needs an explicit proxy or its current proxy is stale.
