# Changelog

All notable user-facing changes are recorded here. This project follows Semantic Versioning for immutable Git tags and GitHub Releases.

## [0.2.0] - 2026-08-10

### Added

- Read-only WSL startup baseline audit with strict failure mode and redacted Git and SSH checks.
- Reversible user-only workspace and shell PATH setup with marker collision protection and backups.
- Explicit `win-open` and `win-clip` wrappers that retain Windows interop without restoring Windows PATH.
- Targeted WSL systemd/default-user configuration that preserves network, interop, and unrelated `wsl.conf` settings.
- Explicit Phase 1 foundation and Phase 2 LAN SSH server-extension ownership contract.
- Startup, systemd, and interoperability regression tests in the Linux CI job.
- Optional adapter for the independently released `setup-starship-catppuccin` `v0.1.0` Skill, including WSL-only and explicitly approved Windows-host modes.

### Changed

- Defined the delivered product as a repository-native Agent Skill combining Codex-controlled decisions with deterministic Bash and PowerShell operations.
- Consolidated startup, rollback, server handoff, support, and validation guidance under their authoritative documents.
- Expanded CI to run every Bash test automatically while retaining Windows PowerShell 5.1 registry tests.

### Fixed

- Allowed the read-only systemd foundation check to run without administrator privileges.
- Rejected missing or empty systemd configuration arguments with the documented usage status.

### Safety

- Kept user startup, distro configuration, Windows interoperability, Explorer integration, Docker, and LAN server exposure as independent opt-in layers.
- Preserved unrelated user files, Windows registry entries, and `wsl.conf` sections with ownership, collision, backup, idempotence, and rollback checks.

## [0.1.0] - 2026-07-31

### Added

- Audit-first Codex Skill workflow for native WSL Ubuntu AI development environments.
- Targeted `[interop] appendWindowsPath=false` configuration with idempotence tests.
- WSL and Windows inventory, migration verification, network diagnosis, Docker Engine installation, and Docker proxy scripts.
- Optional per-user Windows Explorer entries for direct WSL and Windows Terminal profile launches.
- Explicit Windows 11 classic-context-menu opt-in with guarded Explorer restart and safe rollback.
- Installation through `npx skills`, Codex `$skill-installer`, or Git.
- Linux and Windows GitHub Actions coverage, including disposable registry tests on Windows PowerShell 5.1.
- MIT licensing for use, modification, and distribution.

### Safety

- Preserved explicit Windows interoperability without importing Windows executables into the WSL `PATH`.
- Added registry ownership, collision detection, injection-resistant command rendering, and conservative removal checks.
- Kept administrator elevation, global classic-menu behavior, network changes, and unrestricted AI CLI permissions as explicit user decisions.

### Documentation

- Defined the supported product shape, requirements, isolation boundary, and documentation authority in the README.
- Consolidated reusable migration and cleanup guidance into focused references.
- Removed personal workstation snapshots and duplicated migration field notes from the distributable skill.
