#!/usr/bin/env bash
set -uo pipefail

usage() {
  printf '%s\n' \
    'Usage: configure-user-skill.sh --check|--install' \
    'Checks or installs a user-scoped bootstrap-wsl-ai-dev link from this repository.'
}

case "${1:-}" in
  --check|--install)
    action="$1"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd "$script_dir/.." && pwd -P)"
user_root="${AI_BUILD_UP_HOME:-${HOME:?HOME is not set}}"
codex_root="${CODEX_HOME:-$user_root/.codex}"
user_target="$user_root/.agents/skills/bootstrap-wsl-ai-dev"
legacy_target="$codex_root/skills/bootstrap-wsl-ai-dev"
state_root="${XDG_STATE_HOME:-$user_root/.local/state}/ai-build-up"
backup_dir=''

is_current_link() {
  [ -L "$user_target" ] && [ "$(readlink "$user_target")" = "$repo_dir" ]
}

ensure_backup_dir() {
  if [ -z "$backup_dir" ]; then
    backup_dir="$state_root/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$-bootstrap-wsl-ai-dev"
    mkdir -p "$backup_dir"
  fi
}

backup_target() {
  local label="$1"
  local target="$2"
  ensure_backup_dir
  mv "$target" "$backup_dir/$label"
  printf '[BACKUP] %s -> %s\n' "$target" "$backup_dir/$label"
}

check_link() {
  local failures=0

  if is_current_link; then
    printf '[OK]      %s -> %s\n' "$user_target" "$repo_dir"
  elif [ -e "$user_target" ] || [ -L "$user_target" ]; then
    printf '[DRIFT]   %s is not linked to %s\n' "$user_target" "$repo_dir"
    failures=$((failures + 1))
  else
    printf '[MISSING] %s\n' "$user_target"
    failures=$((failures + 1))
  fi

  if [ -e "$legacy_target" ] || [ -L "$legacy_target" ]; then
    printf '[DUPLICATE] legacy installation remains at %s\n' "$legacy_target"
    failures=$((failures + 1))
  fi

  [ "$failures" -eq 0 ]
}

install_link() {
  if [ ! -f "$repo_dir/SKILL.md" ]; then
    printf 'SKILL.md is missing from source repository: %s\n' "$repo_dir" >&2
    return 1
  fi
  if [ "$repo_dir" = "$user_target" ] || [ "$repo_dir" = "$legacy_target" ]; then
    printf 'Clone the source repository outside a Skill discovery directory before linking it.\n' >&2
    return 1
  fi

  mkdir -p "$(dirname "$user_target")"
  if ! is_current_link && { [ -e "$user_target" ] || [ -L "$user_target" ]; }; then
    backup_target user-skill "$user_target"
  fi
  if [ -e "$legacy_target" ] || [ -L "$legacy_target" ]; then
    backup_target legacy-codex-skill "$legacy_target"
  fi
  if ! is_current_link; then
    ln -s "$repo_dir" "$user_target"
    printf '[LINKED]  %s -> %s\n' "$user_target" "$repo_dir"
  fi

  if [ -n "$backup_dir" ]; then
    printf 'Previous installations were preserved in %s\n' "$backup_dir"
  fi
}

if [ "$action" = '--check' ]; then
  check_link
else
  install_link && check_link
fi
