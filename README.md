# Bootstrap WSL AI Dev

A Codex skill for auditing, isolating, migrating, and validating a native AI development environment in WSL Ubuntu. It keeps Windows and WSL toolchains separate while preserving deliberate Windows interoperability.

The skill also provides optional Windows-side integration for opening an Explorer directory in WSL directly or through a named Windows Terminal profile.

## Product shape

The release is delivered as a repository-native Codex skill rather than an npm or binary package:

- `SKILL.md` defines the audit-first workflow, safety gates, and resource routing.
- `scripts/` contains deterministic WSL Bash and Windows PowerShell operations for audits, PATH isolation, network diagnosis, Docker setup, migration verification, and optional Explorer integration.
- `references/` contains focused migration, Windows cleanup, Explorer integration, and official-source guidance.
- `tests/` and GitHub Actions validate targeted/idempotent WSL configuration and disposable Windows registry behavior.

The WSL boundary is implemented by setting only `[interop] appendWindowsPath=false` while preserving explicit interoperability. The Explorer feature is implemented as owned per-user registry verbs under `HKCU:\Software\Classes`; it does not import Windows commands into WSL.

## Requirements

- Windows 11 with WSL 2 and an Ubuntu distribution for the complete workflow.
- Bash and standard Ubuntu command-line tools for WSL scripts.
- Codex with Agent Skills support.
- Git for manual installation, or Node.js/npm for `npx skills` installation.
- Windows PowerShell 5.1 or later for Windows inventory and Explorer integration.
- Windows Terminal only when the optional Windows Terminal launcher is selected.

Run the skill from the Linux filesystem inside WSL. Other Linux distributions, Windows versions, terminal hosts, and AI CLI versions may work but are not claimed as supported by `v0.1.0`; verify current vendor documentation before changing version-sensitive behavior.

## Install

### Install with `npx skills`

Run the command inside WSL to install the skill globally for Codex:

```bash
npx skills add CaoLiangqiang/bootstrap-wsl-ai-dev \
  --skill bootstrap-wsl-ai-dev \
  --agent codex \
  --global \
  --yes
```

Preview what the repository exposes without installing it:

```bash
npx skills add CaoLiangqiang/bootstrap-wsl-ai-dev --list
```

Update the installed global skill later with:

```bash
npx skills update bootstrap-wsl-ai-dev --global --yes
```

`npx skills` installs the shared Codex target under `~/.agents/skills/bootstrap-wsl-ai-dev`. Start a new Codex turn after installation or update so the current skill state is discovered.

### Install with Codex

Ask Codex to use the built-in skill installer:

```text
Use $skill-installer to install bootstrap-wsl-ai-dev from
https://github.com/CaoLiangqiang/bootstrap-wsl-ai-dev,
using the repository root as the skill path.
```

The installer should use `.` as the repository path and `bootstrap-wsl-ai-dev` as the destination name. Start a new Codex turn after installation so the skill becomes available.

### Install with Git

Run this inside WSL so the skill remains on the Linux filesystem:

```bash
skill_root="${CODEX_HOME:-$HOME/.codex}/skills"
mkdir -p "$skill_root"
git clone https://github.com/CaoLiangqiang/bootstrap-wsl-ai-dev.git \
  "$skill_root/bootstrap-wsl-ai-dev"
```

For an existing installation, update it from its installed directory:

```bash
git -C "${CODEX_HOME:-$HOME/.codex}/skills/bootstrap-wsl-ai-dev" pull --ff-only
```

Do not overwrite an existing destination that contains local changes. Inspect it with `git status` first.

## Use

Invoke the skill explicitly in a new Codex turn:

```text
Use $bootstrap-wsl-ai-dev to audit my Windows and WSL AI development environment.
```

The workflow starts read-only. It asks for explicit decisions before changing PATH isolation, Windows registry state, packages, credentials, Docker, or networking.

Documentation authority is intentionally split to avoid duplication:

- [SKILL.md](SKILL.md): workflow, safety decisions, and resource routing.
- [AI CLI migration](references/ai-cli-migration.md): WSL boundary and tool migration details.
- [Windows cleanup](references/windows-ai-cleanup.md): inventory and targeted removal.
- [Explorer integration](references/windows-explorer-wsl.md): install, status, rollback, and Windows 11 behavior.
- [Official sources](references/sources.md): version-sensitive primary documentation.
- [CHANGELOG.md](CHANGELOG.md): released user-facing changes.

## Isolation boundary

The native WSL isolation setting is:

```ini
[interop]
appendWindowsPath=false
```

This prevents Windows directories and command shims from being imported into the WSL `PATH`. It does not disable WSL interoperability, so an explicitly addressed Windows executable under `/mnt/c/...` can still be used for a deliberate Windows-side operation.

The optional Explorer integration preserves this boundary:

- It writes per-user shell verbs only under `HKCU:\Software\Classes`.
- Explorer launches `wsl.exe` or `wt.exe` from Windows; neither executable is added to the WSL `PATH`.
- It does not edit `/etc/wsl.conf`, WSL networking, DNS, proxy, Docker, or the WSL default user.
- The Windows 11 classic context menu is a separate, explicit opt-in that changes only Explorer UI behavior.
- It does not require administrator elevation or UAC.

The classic-menu override is undocumented Windows behavior and may stop working after an operating-system update. Launcher installation and removal remain independent from that global UI choice.

See [references/windows-explorer-wsl.md](references/windows-explorer-wsl.md) for installation, status, rollback, and Windows 11 menu behavior.

## Validate the repository

```bash
bash -n scripts/*.sh tests/*.sh
shellcheck -x scripts/*.sh tests/*.sh
bash tests/test-configure-wsl-path-isolation.sh
npx --yes skills@1.5.21 add . --list
python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" .
```

The GitHub Actions workflow also parses the PowerShell scripts and runs the Explorer integration tests on Windows PowerShell.

## License

Released under the [MIT License](LICENSE).
