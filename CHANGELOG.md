# Changelog

All notable user-facing changes are recorded here. This project follows Semantic Versioning for immutable Git tags and GitHub Releases.

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
