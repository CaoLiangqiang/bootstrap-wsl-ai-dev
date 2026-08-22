# Changelog

All notable user-facing changes are recorded here. This project follows Semantic Versioning for immutable Git tags and GitHub Releases.

## [0.4.0] - 2026-08-22

### Added

- Optional `Ubuntu Native` Windows Terminal color scheme with an aubergine background, Ubuntu orange tab, and complete Tango-style ANSI palette.
- Per-user Windows Terminal JSON Fragment installer with status, idempotent install, guarded removal, UTF-8 validation, and exact profile-GUID targeting.
- Windows PowerShell 5.1 regression coverage for Terminal Fragment ownership, collision handling, settings preservation, encoding, and cleanup.

### Changed

- Added `Both`, `Direct`, and `WindowsTerminal` Explorer launcher modes while retaining `Both` as the backward-compatible default.
- Made launcher-mode switches remove only unselected project-owned verbs and preserve unowned or modified registry entries.
- Expanded Explorer documentation and CI to cover the recommended single Windows Terminal entry with optional Ubuntu-native theming.

### Safety

- Keep the Terminal theme, launcher selection, and global Windows 11 classic-menu override as independent opt-ins.
- Apply the theme through a removable per-user Fragment instead of rewriting the user's complete Windows Terminal `settings.json`.
- Refuse to overwrite or delete a foreign or modified Fragment and preserve unrelated files in the Fragment directory.

## [0.3.0] - 2026-08-22

### Added

- Source-linked user Skill installation that migrates legacy Codex Skill copies into the shared `~/.agents/skills` scope with backups and idempotent checks.
- Windows user and machine PATH registration auditing, including missing targets and secondary Windows executable candidates hidden behind native WSL commands.
- Configuration-path validation that permits shared projects and data under `/mnt/<drive>` while rejecting Windows command settings, executable paths, and npm shims.
- Regression coverage for network exit status, configuration-path classification, and transactional Docker daemon proxy changes.

### Changed

- Made network diagnostics return a nonzero status when any endpoint fails and distinguish sandbox-like socket restrictions from host-network evidence.
- Made Docker daemon proxy management transactional: it can set or clear a fixed proxy, preflight the requested endpoint, verify the effective daemon state, exercise a real pull and run, and restore the previous drop-in after failure or interruption.
- Expanded WSL audits and migration verification with credential-redacted proxy reporting, effective Docker proxy inspection, fallback command discovery, and conservative multi-signal agent-sandbox detection.
- Updated the Skill workflow and README to document direct versus proxied checks, stale Docker proxy recovery, sandbox limitations, and the `v0.3.0` support statement.

### Safety

- Preserve unrelated configuration and project/data paths while rejecting only cross-environment command execution paths.
- Restore the prior Docker proxy drop-in and test-image state whenever validation fails.
- Treat sandbox detection as advisory evidence and require host-only verification before changing workstation networking, interop, permissions, or ownership.

## [0.2.1] - 2026-08-10

### Fixed

- Isolated the Starship adapter fixture from real sibling Skill installations so release tests behave consistently in source checkouts and installed consumer layouts.
- Made the documented and CI Bash test loops stop immediately when any individual test fails.

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
