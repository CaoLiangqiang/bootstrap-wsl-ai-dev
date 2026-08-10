#!/usr/bin/env bash
set -Eeuo pipefail

mode='check'
action_count=0
bin_dir=''
bin_dir_explicit=0
canonical_home=''
windows_root=''
owner_marker='# bootstrap-wsl-ai-dev: windows-interop-wrapper v1'

usage() {
  printf '%s\n' \
    'Usage: install-windows-interop-wrappers.sh [--check|--install|--remove] [--bin-dir PATH] [--windows-root PATH]' \
    'Installs owned win-open and win-clip wrappers without importing Windows PATH.' \
    '' \
    '  --check              report whether the owned wrappers are present (default)' \
    '  --install            create or update owned wrappers' \
    '  --remove             remove only owned wrappers' \
    '  --bin-dir PATH       target directory (default: ~/.local/bin)' \
    '  --windows-root PATH  mounted Windows directory, such as /mnt/c/Windows'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check|--install|--remove)
      mode="${1#--}"
      action_count=$((action_count + 1))
      shift
      ;;
    --bin-dir|--windows-root)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$1" in
        --bin-dir) bin_dir="$2"; bin_dir_explicit=1 ;;
        --windows-root) windows_root="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ "$action_count" -gt 1 ]; then
  printf 'Specify at most one action: --check, --install, or --remove.\n' >&2
  exit 2
fi
if [ "$bin_dir_explicit" -eq 0 ]; then
  if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
    printf 'HOME must be set unless --bin-dir is provided.\n' >&2
    exit 2
  fi
  canonical_home="$(cd "$HOME" && pwd -P)"
  bin_dir="$HOME/.local/bin"
fi
if [ -z "$bin_dir" ] || [ "$bin_dir" = '/' ]; then
  printf 'Refusing unsafe --bin-dir: %s\n' "${bin_dir:-<empty>}" >&2
  exit 2
fi
bin_dir="$(realpath -m "$bin_dir")"
current_uid="$(id -u)"
if [ "$bin_dir_explicit" -eq 0 ]; then
  case "$bin_dir" in
    "$canonical_home"|"$canonical_home"/*) ;;
    *)
      printf 'Default wrapper bin resolves outside HOME; refusing a user-directory symlink: %s\n' "$bin_dir" >&2
      exit 2
      ;;
  esac
fi

discover_windows_root() {
  local candidate candidates=''
  for candidate in /mnt/[a-zA-Z]/Windows; do
    if [ ! -x "$candidate/explorer.exe" ] || [ ! -x "$candidate/System32/clip.exe" ]; then
      continue
    fi
    candidates="${candidates}${candidate}"$'\n'
  done
  candidates="${candidates%$'\n'}"
  [ -n "$candidates" ] || return 1
  [ "$(printf '%s\n' "$candidates" | wc -l)" -eq 1 ] || return 2
  printf '%s\n' "$candidates"
}

if [ "$mode" != 'remove' ]; then
  if [ -z "$windows_root" ]; then
    if windows_root="$(discover_windows_root)"; then
      :
    else
      status="$?"
      if [ "$status" -eq 2 ]; then
        printf 'Multiple Windows roots were discovered; pass --windows-root explicitly.\n' >&2
      else
        printf 'No usable Windows root was discovered; pass --windows-root explicitly.\n' >&2
      fi
      exit 1
    fi
  fi
  windows_root="$(realpath -m "$windows_root")"
  explorer_path="$windows_root/explorer.exe"
  clip_path="$windows_root/System32/clip.exe"
  if ! command -v wslpath >/dev/null 2>&1; then
    printf 'wslpath is required to create Windows paths for win-open.\n' >&2
    exit 1
  fi
  if [ ! -x "$explorer_path" ] || [ ! -x "$clip_path" ]; then
    printf 'Windows root must contain executable explorer.exe and System32/clip.exe: %s\n' "$windows_root" >&2
    exit 1
  fi
fi

render_win_open() {
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "$owner_marker" \
    'set -Eeuo pipefail'
  cat <<'EOF'
if [ "${1:-}" = "--help" ]; then
  printf '%s\n' 'Usage: win-open [PATH] - open a Linux path in Windows Explorer.'
  exit 0
fi
target="${1:-.}"
windows_path="$(wslpath -w "$target")"
EOF
  printf "exec %q \"\$windows_path\"\n" "$explorer_path"
}

render_win_clip() {
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "$owner_marker" \
    'set -Eeuo pipefail'
  cat <<'EOF'
if [ "${1:-}" = "--help" ]; then
  printf '%s\n' 'Usage: win-clip - copy standard input to the Windows clipboard.'
  exit 0
fi
EOF
  printf 'exec %q\n' "$clip_path"
}

wrapper_state() {
  local file="$1"
  [ -e "$file" ] || [ -L "$file" ] || { printf 'missing\n'; return; }
  [ -f "$file" ] && sed -n '2p' "$file" | grep -Fqx "$owner_marker" \
    && printf 'owned\n' || printf 'collision\n'
}

preflight_wrappers() {
  local name file state
  for name in win-open win-clip; do
    file="$bin_dir/$name"
    state="$(wrapper_state "$file")"
    if [ "$state" = 'collision' ]; then
      printf 'Refusing unowned wrapper collision: %s\n' "$file" >&2
      return 1
    fi
  done
}

require_current_owner() {
  local path="$1" owner
  owner="$(stat -c '%u' -- "$path" 2>/dev/null || true)"
  if [ "$owner" != "$current_uid" ]; then
    printf 'Wrapper path must be owned by the current user: %s\n' "$path" >&2
    return 1
  fi
}

nearest_existing_ancestor() {
  local path="$1" parent
  while [ ! -e "$path" ] && [ ! -L "$path" ]; do
    parent="$(dirname "$path")"
    [ "$parent" != "$path" ] || break
    path="$parent"
  done
  printf '%s\n' "$path"
}

preflight_bin_owner() {
  local ancestor
  ancestor="$(nearest_existing_ancestor "$bin_dir")"
  require_current_owner "$ancestor"
  [ -e "$bin_dir" ] || [ -L "$bin_dir" ] || return 0
  if [ -L "$bin_dir" ] || [ ! -d "$bin_dir" ]; then
    printf 'Wrapper bin directory is not a regular directory: %s\n' "$bin_dir" >&2
    return 1
  fi
  require_current_owner "$bin_dir"
}

preflight_wrapper_owners() {
  local name file state
  for name in win-open win-clip; do
    file="$bin_dir/$name"
    state="$(wrapper_state "$file")"
    [ "$state" != 'owned' ] || require_current_owner "$file"
  done
}

write_wrapper() {
  local name="$1" renderer="$2" file state temp_file
  file="$bin_dir/$name"
  state="$(wrapper_state "$file")"
  [ "$state" != 'collision' ] || { printf 'Refusing unowned wrapper collision: %s\n' "$file" >&2; return 1; }
  mkdir -p "$bin_dir"
  temp_file="$(mktemp "$bin_dir/.${name}.XXXXXX")"
  "$renderer" > "$temp_file"
  chmod 0755 "$temp_file"
  if [ -e "$file" ] && cmp -s "$temp_file" "$file"; then
    rm -f "$temp_file"
    printf 'Already installed: %s\n' "$file"
  else
    mv "$temp_file" "$file"
    printf 'Installed: %s\n' "$file"
  fi
}

remove_wrapper() {
  local name="$1" file state
  file="$bin_dir/$name"
  state="$(wrapper_state "$file")"
  case "$state" in
    missing) printf 'No wrapper: %s\n' "$file" ;;
    owned) rm -f "$file"; printf 'Removed: %s\n' "$file" ;;
    collision) printf 'Refusing unowned wrapper collision: %s\n' "$file" >&2; return 1 ;;
  esac
}

case "$mode" in
  check)
    preflight_wrappers
    current_open="$(mktemp)"
    current_clip="$(mktemp)"
    trap 'rm -f "$current_open" "$current_clip"' EXIT
    render_win_open > "$current_open"
    render_win_clip > "$current_clip"
    if [ -f "$bin_dir/win-open" ] && [ -f "$bin_dir/win-clip" ] \
        && cmp -s "$current_open" "$bin_dir/win-open" && cmp -s "$current_clip" "$bin_dir/win-clip"; then
      printf 'OK: owned Windows interop wrappers are present.\n'
      exit 0
    fi
    printf 'CHANGE NEEDED: owned Windows interop wrappers are absent or stale. No files were modified.\n'
    exit 1
    ;;
  install)
    preflight_wrappers
    preflight_bin_owner
    preflight_wrapper_owners
    write_wrapper win-open render_win_open
    write_wrapper win-clip render_win_clip
    ;;
  remove)
    preflight_wrappers
    preflight_bin_owner
    preflight_wrapper_owners
    remove_wrapper win-open
    remove_wrapper win-clip
    ;;
esac
