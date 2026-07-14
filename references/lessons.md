# WSL AI Development Bootstrap: Field Notes

## Contents

1. Outcome and sequence
2. Windows influence and cleanup
3. Network diagnosis
4. Native WSL toolchain
5. Docker installation and proxy repair
6. GitHub SSH and CLI authentication
7. Cleanup decisions
8. Failure signatures
9. Security boundaries

## 1. Outcome and sequence

These notes come from a successful Windows-to-WSL Ubuntu migration with this target state:

- Keep the Windows desktop relatively clean.
- Run development and AI command-line tools natively inside WSL.
- Use native Git, Python, Node, Codex, Claude Code, GitHub CLI, and Docker Engine.
- Preserve a Windows proxy but make each WSL subsystem use it explicitly.
- Remove Kimi, Trae, and related remnants without deleting unrelated developer data.

The reliable sequence was:

1. Inventory every agent and executable and classify its origin.
2. Remove unwanted Windows programs and extensions.
3. Re-scan both Windows registration and WSL command resolution.
4. Repair network and proxy behavior before large downloads.
5. Configure Git identity and SSH.
6. Install native WSL language tooling.
7. Enable systemd and install Docker Engine.
8. Configure the Docker daemon proxy separately.
9. Validate with a real container.
10. Clean installation artifacts, stale PATH entries, and obsolete releases.
11. Authenticate GitHub CLI and verify final tool origins.

## 2. Windows influence and cleanup

### Three states that look similar

Always separate:

1. Installed state: a Windows application is registered or its program directory exists.
2. Resolution state: WSL command -v finds a Windows executable through /mnt.
3. Snapshot state: an already-running WSL process still has an old Windows PATH entry after the registry and program directory were cleaned.

An uninstaller can remove state 1 while state 3 remains until WSL restarts. Do not repeatedly delete files based only on the current PATH.

### Practical inspection

Inspect WSL command origin:

    command -v pnpm
    type -a pnpm node npm codex claude
    printf '%s' "$PATH" | tr ':' '\n'

Inspect the live Windows user and system PATH from WSL:

    reg.exe query 'HKCU\Environment' /v Path
    reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' /v Path

Inspect uninstall registration and known data directories before deletion. A missing target directory with a remaining PATH entry is a safe candidate for targeted PATH cleanup. Preserve the registry value type and all unrelated path elements.

### What happened in the field

- Kimi and Trae were uninstalled first.
- WSL still displayed a Trae program-directory entry in PATH.
- The directory and current Windows registry entries were already absent.
- The remaining entry was only an old WSL process snapshot.
- A separate LM Studio PATH entry remained in the Windows registry even though its directory was absent; that single entry was removed.
- An empty Windows npm scope directory left by an uninstalled tool was removed after confirming it contained no packages.

The final refresh step was wsl --shutdown from Windows PowerShell.

## 3. Network diagnosis

### Diagnose endpoints, not a single speed number

Test GitHub, Docker Registry, Docker package downloads, npm, and Astral independently. A proxy node can be fast for general web traffic but slow for GitHub or package registries.

Use a short connection timeout and a total timeout. Avoid large benchmark downloads before the path is known to work.

### Recognize a healthy Docker Registry probe

The unauthenticated endpoint:

    https://registry-1.docker.io/v2/

normally returns HTTP 401. This proves DNS, TCP, TLS, and HTTP reachability. Treat HTTP 000, a connection timeout, or a name-resolution failure as the network problem.

### Shell proxy versus service proxy

This was the most important network lesson:

- curl, apt, npm, uv, and an interactive shell can inherit HTTP_PROXY and HTTPS_PROXY.
- Docker image pulls are performed by dockerd.
- dockerd is a systemd service and does not inherit the user's interactive shell environment.

Therefore a successful curl through http://127.0.0.1:7897 did not imply that docker pull would work.

The observed failure pattern was:

    failed to resolve reference
    Head "https://registry-1.docker.io/..."
    dial tcp ...:443: i/o timeout

The repair was a systemd drop-in for docker.service with HTTP_PROXY, HTTPS_PROXY, and NO_PROXY, followed by systemctl daemon-reload and a Docker restart.

When the proxy is hosted on Windows at 127.0.0.1, confirm that the current WSL networking mode allows WSL processes to reach it. Do not hardcode the port without testing it.

## 4. Native WSL toolchain

### Python

Keep the Ubuntu Python for operating-system tooling. Use uv for project environments, Python tools, and compatibility versions. Do not replace or modify the system Python with pip.

Useful checks:

    python3 --version
    uv --version
    uv python list --only-installed
    uv tool list

### Node and pnpm

Node was installed natively under a WSL NVM directory, but pnpm initially resolved to:

    /mnt/c/Users/.../AppData/Roaming/npm/pnpm

This mixed Windows and Linux execution contexts. Enabling Corepack and installing a WSL-native pnpm corrected the path:

    corepack enable
    corepack install --global pnpm@VERSION
    command -v pnpm

Verify the installed version from current official documentation before pinning it in a new environment.

### Codex and Claude Code

Confirm the binary path before considering an AI CLI migrated. A WSL-native binary should resolve under the Linux home, /usr, or a WSL version manager.

Run codex doctor after installation. It validates the install layout, state databases, auth, proxy reachability, WebSocket connection, and updates without requiring raw credentials.

Claude Code can remain installed but unauthenticated until the user selects a first-party subscription, Anthropic API billing, or a compatible third-party endpoint. Never ask the user to paste the real API key into chat or a command that will remain in shell history.

## 5. Docker installation and proxy repair

### Enable systemd first

Docker Engine was installed directly inside Ubuntu rather than through Docker Desktop. WSL needed systemd enabled:

    [boot]
    systemd=true

After changing /etc/wsl.conf, restart WSL from Windows:

    wsl --shutdown

### Separate agent work from sudo authentication

An agent cannot safely receive or type the user's sudo password. The effective pattern was:

1. Generate a small, reviewable installation script in the workspace.
2. Syntax-check it.
3. Ask the user to run one sudo bash command locally.
4. Read the resulting output and continue validation.
5. Delete the temporary script when complete.

The initial installer:

- Configured Docker's official Ubuntu repository.
- Installed Docker Engine, CLI, containerd, Buildx, and Compose.
- Enabled and started docker.service.
- Added the WSL user to the docker group.

The generalized successor is scripts/install-docker-engine.sh.

### Group membership is process state

Adding a user to the docker group updates account configuration, not already-running processes. The agent process that performed the installation continued to get:

    permission denied while trying to connect to the docker API

A newly opened WSL terminal showed docker in id -nG and had access. Do not change socket permissions to work around a stale group list.

### Docker daemon proxy

The first hello-world pull timed out even though the proxy worked for curl. A second script created:

    /etc/systemd/system/docker.service.d/http-proxy.conf

After restart, hello-world downloaded and ran successfully. The generalized successor is scripts/configure-docker-proxy.sh.

### Final validation

Verify:

    docker --version
    docker compose version
    systemctl is-active docker
    systemctl is-enabled docker
    docker run --rm hello-world

After validation, the test image can be removed if it is not wanted.

## 6. GitHub SSH and CLI authentication

### SSH port 22 can hang

The SSH key and config were correct, but ssh -T git@github.com did not return because the network blocked or black-holed port 22.

Testing GitHub's documented SSH-over-HTTPS endpoint succeeded:

    ssh -T -p 443 git@ssh.github.com

Only after verifying the published host fingerprint was the github.com SSH config changed to:

    Host github.com
        HostName ssh.github.com
        Port 443
        User git
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes

GitHub returns exit status 1 after the successful message because it does not provide shell access. Judge this test by the message, not only the exit code.

### GitHub CLI in headless WSL

The user completed gh auth login in a browser. A headless WSL distribution may lack a desktop keyring, causing gh to save its token in:

    ~/.config/gh/hosts.yml

Verify mode 600 and never print the file. A masked gh auth status plus a read-only gh api user request is enough for validation.

## 7. Cleanup decisions

### Removed

The successful migration removed:

- A large one-time Codex download archive.
- The NVM installer script after NVM worked.
- An obsolete standalone Codex release after current symlink and doctor checks.
- Docker APT archives with apt-get clean.
- The hello-world test image.
- Temporary staged SSH and Docker configuration scripts.
- An empty Windows npm scope directory.
- A Windows PATH entry whose target no longer existed.

### Intentionally retained

Retain:

- A valid npm content cache when downloads are slow.
- uv-managed Python versions needed for compatibility.
- The active Codex release and state databases.
- SSH keys and known_hosts backups.
- Active Codex, Node, tmux, and sandbox temporary directories.
- Docker configuration and the daemon proxy drop-in.

Use npm cache verify before deleting npm cache. A verified cache is reusable data, not necessarily trash.

## 8. Failure signatures

| Symptom | Likely cause | Correct response |
| --- | --- | --- |
| command -v points to /mnt/c | Windows PATH is winning | Install or enable the native WSL tool, then verify path order |
| PATH shows an uninstalled program | Old WSL process snapshot or stale registry entry | Check registry and directory separately; restart WSL |
| sudo -n reports authentication required | No reusable noninteractive sudo ticket | Generate a reviewed script and let the user run it |
| Docker service is active but user gets permission denied | Current process lacks refreshed docker group | Open a new login shell; do not chmod the socket |
| curl works but docker pull times out | dockerd has no proxy | Configure docker.service proxy and restart |
| Docker Registry probe returns 401 | Endpoint is reachable | Continue; authentication is intentionally absent |
| ssh github.com hangs | Port 22 blocked | Test ssh.github.com on port 443 |
| gh warns about plain-text credentials | No Linux secret service | Verify hosts.yml is mode 600 or configure a keyring |
| uv or pip says cache is read-only during an agent run | Agent filesystem sandbox, not necessarily real ownership | Recheck outside the sandbox before changing ownership |

## 9. Security boundaries

- Never collect sudo passwords, private keys, API keys, or raw GitHub tokens.
- Never print auth.json, hosts.yml, private-key files, or complete environment dumps containing secrets.
- Redact proxy credentials before logs.
- Verify SSH fingerprints from GitHub's current official list.
- Default new GitHub repositories to private when visibility is unspecified.
- Avoid deleting Windows model data or application directories based only on a name match.
- Keep root scripts short, auditable, idempotent where possible, and explicit about every file they write.
