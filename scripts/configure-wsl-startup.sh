#!/usr/bin/env bash
set -Eeuo pipefail

mode='check'
action_count=0
home_dir="${HOME:-}"
workspace=''
marker_start='# >>> bootstrap-wsl-ai-dev startup PATH >>>'
marker_end='# <<< bootstrap-wsl-ai-dev startup PATH <<<'
current_uid="$(id -u)"

usage() {
  printf '%s\n' \
    'Usage: configure-wsl-startup.sh [--check|--install|--remove] [--home PATH] [--workspace PATH]' \
    'Manages only a user workspace, ~/.local/bin, and an owned startup PATH block.' \
    '' \
    '  --check           report whether the user startup baseline is present (default)' \
    '  --install         create missing directories and add the owned PATH block' \
    '  --remove          remove only the owned PATH block; preserve directories'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check|--install|--remove)
      mode="${1#--}"
      action_count=$((action_count + 1))
      shift
      ;;
    --home|--workspace)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$1" in
        --home) home_dir="$2" ;;
        --workspace) workspace="$2" ;;
      esac
      shift 2
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
done

if [ "$action_count" -gt 1 ]; then
  printf 'Specify at most one action: --check, --install, or --remove.\n' >&2
  exit 2
fi

if [ -z "$home_dir" ] || [ "$home_dir" = '/' ] || [ ! -d "$home_dir" ]; then
  printf 'Refusing invalid home directory: %s\n' "${home_dir:-<empty>}" >&2
  exit 2
fi
home_dir="$(cd "$home_dir" && pwd -P)"
if [ -z "$workspace" ]; then workspace="$home_dir/src"; fi
workspace="$(realpath -m "$workspace")"
local_bin="$(realpath -m "$home_dir/.local/bin")"

require_inside_home() {
  local path="$1" label="$2"
  case "$path" in
    "$home_dir"|"$home_dir"/*) ;;
    *)
      printf '%s resolves outside canonical --home; refusing a user-directory symlink: %s\n' "$label" "$path" >&2
      exit 2
      ;;
  esac
}

if [ "$mode" != 'remove' ]; then
  require_inside_home "$workspace" 'Workspace'
  require_inside_home "$local_bin" 'Local bin directory'
fi

nearest_existing_ancestor() {
  local path="$1" parent
  while [ ! -e "$path" ] && [ ! -L "$path" ]; do
    parent="$(dirname "$path")"
    [ "$parent" != "$path" ] || break
    path="$parent"
  done
  printf '%s\n' "$path"
}

require_nearest_owner() {
  local path="$1" ancestor
  ancestor="$(nearest_existing_ancestor "$path")"
  require_current_owner "$ancestor"
}

path_block() {
  printf '%s\n' "$marker_start"
  cat <<'EOF'
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
EOF
  printf '%s\n' "$marker_end"
}

block_state() {
  local file="$1" starts ends extracted expected
  [ -L "$file" ] && { printf 'symlink\n'; return; }
  [ -e "$file" ] || { printf 'missing\n'; return; }
  starts="$(grep -Fxc "$marker_start" "$file" || true)"
  ends="$(grep -Fxc "$marker_end" "$file" || true)"
  if [ "$starts" -eq 0 ] && [ "$ends" -eq 0 ]; then printf 'absent\n'; return; fi
  if [ "$starts" -ne 1 ] || [ "$ends" -ne 1 ]; then printf 'malformed\n'; return; fi
  extracted="$(awk -v start="$marker_start" -v end="$marker_end" '
    $0 == start { active = 1 }
    active { print }
    $0 == end { exit }
  ' "$file")"
  expected="$(path_block)"
  if [ "$extracted" = "$expected" ]; then printf 'owned\n'; else printf 'collision\n'; fi
}

preflight_readable() {
  local file state
  for file in "$home_dir/.profile" "$home_dir/.bashrc"; do
    if [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; then
      printf 'Startup file is not a regular file: %s\n' "$file" >&2
      return 1
    fi
    if [ -e "$file" ] && [ ! -r "$file" ]; then
      printf 'Startup file must be readable: %s\n' "$file" >&2
      return 1
    fi
    state="$(block_state "$file")"
    case "$state" in
      missing|absent|owned) ;;
      malformed|collision)
        printf 'Refusing %s marker state in %s\n' "$state" "$file" >&2
        return 1
        ;;
    esac
  done
}

require_current_owner() {
  local path="$1" owner
  owner="$(stat -c '%u' -- "$path" 2>/dev/null || true)"
  if [ "$owner" != "$current_uid" ]; then
    printf 'Path must be owned by the current user: %s\n' "$path" >&2
    return 1
  fi
}

preflight_write() {
  local file
  preflight_readable
  if [ ! -w "$home_dir" ]; then
    printf 'Home directory is not writable: %s\n' "$home_dir" >&2
    return 1
  fi
  require_current_owner "$home_dir"
  for file in "$home_dir/.profile" "$home_dir/.bashrc"; do
    if [ -e "$file" ] && [ ! -w "$file" ]; then
      printf 'Startup file must be writable: %s\n' "$file" >&2
      return 1
    fi
    [ ! -e "$file" ] || require_current_owner "$file"
  done
}

preflight_install_targets() {
  local file
  for file in "$workspace" "$local_bin"; do
    if [ -L "$file" ] || { [ -e "$file" ] && [ ! -d "$file" ]; }; then
      printf 'Expected directory but found another file type: %s\n' "$file" >&2
      return 1
    fi
    [ ! -e "$file" ] || require_current_owner "$file"
    require_nearest_owner "$file"
  done
}

backup_file() {
  local file="$1" backup
  backup="$(mktemp "${file}.bootstrap-wsl-ai-dev.startup.backup.XXXXXX")"
  cp --preserve=mode,timestamps -- "$file" "$backup"
  printf 'Backup: %s\n' "$backup"
}

replace_atomically() {
  local file="$1" renderer="$2" dir base temp_file
  dir="$(dirname "$file")"
  base="$(basename "$file")"
  temp_file="$(mktemp "$dir/.${base}.bootstrap-wsl-ai-dev.tmp.XXXXXX")"
  if [ -e "$file" ]; then
    chmod --reference="$file" "$temp_file"
  fi
  "$renderer" "$file" > "$temp_file"
  if ! mv -f -- "$temp_file" "$file"; then
    rm -f -- "$temp_file"
    return 1
  fi
}

render_install() {
  local file="$1"
  if [ -e "$file" ]; then
    cat -- "$file"
    printf '\n'
  fi
  path_block
}

append_block() {
  local file="$1" state
  state="$(block_state "$file")"
  [ "$state" = 'owned' ] && return
  if [ -e "$file" ]; then
    backup_file "$file"
  fi
  replace_atomically "$file" render_install
  printf 'Installed owned PATH block: %s\n' "$file"
}

render_remove() {
  local file="$1"
  awk -v start="$marker_start" -v end="$marker_end" '
    $0 == start { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$file"
}

remove_block() {
  local file="$1" state
  state="$(block_state "$file")"
  if [ "$state" = 'absent' ] || [ "$state" = 'missing' ]; then
    printf 'No owned PATH block: %s\n' "$file"
    return
  fi
  [ "$state" = 'owned' ] || { printf 'Refusing %s marker state in %s\n' "$state" "$file" >&2; return 1; }
  backup_file "$file"
  replace_atomically "$file" render_remove
  printf 'Removed owned PATH block: %s\n' "$file"
}

case "$mode" in
  check)
    preflight_readable
    ready=1
    [ -d "$workspace" ] && [ -d "$local_bin" ] || ready=0
    for rc_file in "$home_dir/.profile" "$home_dir/.bashrc"; do
      [ "$(block_state "$rc_file")" = 'owned' ] || ready=0
    done
    if [ "$ready" -eq 1 ]; then
      printf 'OK: workspace, ~/.local/bin, and owned startup PATH blocks are present.\n'
      exit 0
    fi
    printf 'CHANGE NEEDED: user startup baseline is incomplete. No files were modified.\n'
    exit 1
    ;;
  install)
    preflight_write
    preflight_install_targets
    mkdir -p "$workspace" "$local_bin"
    append_block "$home_dir/.profile"
    append_block "$home_dir/.bashrc"
    printf 'Installed user startup baseline for %s\n' "$home_dir"
    ;;
  remove)
    preflight_write
    remove_block "$home_dir/.profile"
    remove_block "$home_dir/.bashrc"
    printf 'Removed owned startup PATH blocks; directories were preserved.\n'
    ;;
esac
