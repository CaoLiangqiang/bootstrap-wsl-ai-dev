# WSL Startup Baseline

Use this baseline when initializing a new WSL Ubuntu environment or making an existing shell predictable before migrating AI tools. It owns only the user layer and creates no host or system configuration. Systemd/default-user setup and Windows Explorer registry integration remain separate operations.

## Check first

Run the read-only audit from a Linux-filesystem workspace:

```bash
bash scripts/audit-wsl-startup.sh --workspace "$PWD"
```

It reports workspace placement and ownership, shell startup syntax, Windows PATH visibility, locale and timezone visibility, Git and SSH-agent configuration without printing values, resources, section-aware `wsl.conf` state, and baseline commands. Use `--wsl-conf PATH` only to inspect an explicit configuration file. Warnings do not fail the default audit. Use `--strict` only when a detected `FAIL` should return non-zero.

## User startup choice

The user-only setup creates `~/src`, `~/.local/bin`, and an owned idempotent PATH block in `~/.profile` and `~/.bashrc`:

```bash
bash scripts/configure-wsl-startup.sh --check
bash scripts/configure-wsl-startup.sh --install
```

An absent marker is normal installation input. Before installing or removing an owned block, it creates a uniquely named, permission-preserving backup of each existing rc file it changes, then replaces the file atomically. It refuses duplicated, truncated, conflicting marker blocks, symlinks, or non-regular rc files instead of guessing. Remove only the owned blocks with `--remove` and leave the workspace and `~/.local/bin` in place.

## Explicit Windows actions

Keep normal WSL command lookup Linux-native. For deliberate Windows Explorer and clipboard actions, install local wrappers that call absolute executables rather than restoring Windows PATH:

```bash
bash scripts/install-windows-interop-wrappers.sh --check
bash scripts/install-windows-interop-wrappers.sh --install
win-open .
printf 'text' | win-clip
```

The installer discovers one usable mounted Windows directory or requires `--windows-root`; it rejects ambiguity, missing dependencies, and unowned filename collisions. `--remove` deletes only marked wrappers and preserves the bin directory.

## Deferred host configuration

Do not write `.wslconfig` automatically. It is a Windows-user-level WSL 2 configuration file, not a distro file. Current official documentation labels `autoMemoryReclaim` and `sparseVhd` experimental, and the current page does not confirm a minimum WSL version for either setting.

`/etc/wsl.conf` is distro-specific. Changes normally take effect after WSL restarts. `wsl --shutdown`, run from Windows, terminates every running distribution, so use it only after warning the user about that scope. PATH isolation remains a separate explicit choice through `configure-wsl-path-isolation.sh`; it does not alter networking, locale, timezone, Git, SSH, packages, or host settings.
