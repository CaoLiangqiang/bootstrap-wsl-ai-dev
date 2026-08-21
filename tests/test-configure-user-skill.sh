#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
workstation_root="$test_root/workstation"
legacy_target="$workstation_root/.codex/skills/bootstrap-wsl-ai-dev"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

mkdir -p "$legacy_target"
printf 'old installed skill\n' > "$legacy_target/SKILL.md"

run_manager() {
  env -u CODEX_HOME -u XDG_STATE_HOME \
    AI_BUILD_UP_HOME="$workstation_root" \
    bash "$repo_dir/scripts/configure-user-skill.sh" "$@"
}

run_manager --install
run_manager --check

user_target="$workstation_root/.agents/skills/bootstrap-wsl-ai-dev"
[ -L "$user_target" ]
[ "$(readlink "$user_target")" = "$repo_dir" ]
[ ! -e "$legacy_target" ]
[ ! -L "$legacy_target" ]

backup_file="$(find "$workstation_root/.local/state/ai-build-up/backups" -type f -path '*/legacy-codex-skill/SKILL.md' -print -quit)"
[ -n "$backup_file" ]
grep -F 'old installed skill' "$backup_file" >/dev/null

backup_count_before="$(find "$workstation_root/.local/state/ai-build-up/backups" -type f | wc -l)"
run_manager --install
backup_count_after="$(find "$workstation_root/.local/state/ai-build-up/backups" -type f | wc -l)"
[ "$backup_count_before" -eq "$backup_count_after" ]

printf 'PASS: bootstrap user Skill link migrates legacy installs and remains idempotent\n'
