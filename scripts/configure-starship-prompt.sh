#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill_dir=''
forward_args=()

usage() {
  printf '%s\n' \
    'Usage: configure-starship-prompt.sh [--skill-dir PATH] [setup options]' \
    '' \
    'Delegates to the optional setup-starship-catppuccin skill.' \
    'All remaining arguments are passed to scripts/configure-starship.sh.' \
    '' \
    'Examples:' \
    '  configure-starship-prompt.sh --check' \
    '  configure-starship-prompt.sh --install --with-windows' \
    '  configure-starship-prompt.sh --skill-dir /path/to/setup-starship-catppuccin --remove'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill-dir)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        usage >&2
        exit 2
      fi
      skill_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      forward_args+=("$1")
      shift
      ;;
  esac
done

resolve_skill_dir() {
  local candidate
  if [ -n "$skill_dir" ]; then
    printf '%s\n' "$skill_dir"
    return
  fi
  for candidate in \
    "${SETUP_STARSHIP_CATPPUCCIN_DIR:-}" \
    "$repo_root/../setup-starship-catppuccin" \
    "${CODEX_HOME:-$HOME/.codex}/skills/setup-starship-catppuccin" \
    "$HOME/.agents/skills/setup-starship-catppuccin"; do
    if [ -n "$candidate" ] && [ -f "$candidate/scripts/configure-starship.sh" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

resolved_dir="$(resolve_skill_dir)" || {
  printf '%s\n' \
    'setup-starship-catppuccin was not found.' \
    'Install that skill, set SETUP_STARSHIP_CATPPUCCIN_DIR, or pass --skill-dir PATH.' >&2
  exit 1
}
resolved_dir="$(cd "$resolved_dir" && pwd -P)"
delegate="$resolved_dir/scripts/configure-starship.sh"
theme="$resolved_dir/assets/starship/catppuccin-powerline.toml"
font_license="$resolved_dir/assets/fonts/OFL.txt"

for required in "$delegate" "$theme" "$font_license"; do
  [ -f "$required" ] || { printf 'Incomplete setup-starship-catppuccin skill: %s\n' "$required" >&2; exit 1; }
done

exec bash "$delegate" "${forward_args[@]}"
