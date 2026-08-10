#!/usr/bin/env bash
set -uo pipefail

workspace="$PWD"
home_dir="${HOME:-}"
wsl_conf='/etc/wsl.conf'
strict=0
passes=0
warnings=0
failures=0

usage() {
  printf '%s\n' \
    'Usage: audit-wsl-startup.sh [--workspace PATH] [--home PATH] [--wsl-conf PATH] [--strict]' \
    'Read-only audit for a practical WSL startup baseline.' \
    '' \
    '  --workspace PATH  workspace to inspect (default: current directory)' \
    '  --home PATH       home directory to inspect (default: HOME)' \
    '  --wsl-conf PATH   WSL configuration to inspect (default: /etc/wsl.conf)' \
    '  --strict          return non-zero only when a FAIL is found'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace|--home|--wsl-conf)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$1" in
        --workspace) workspace="$2" ;;
        --home) home_dir="$2" ;;
        --wsl-conf) wsl_conf="$2" ;;
      esac
      shift 2
      ;;
    --strict)
      strict=1
      shift
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

if [ -z "$home_dir" ] || [ ! -d "$home_dir" ]; then
  printf 'Home directory must be non-empty and exist: %s\n' "${home_dir:-<empty>}" >&2
  exit 2
fi
home_dir="$(cd "$home_dir" && pwd -P)"
workspace="$(realpath -m "$workspace")"

wsl_values() {
  local section="$1" key="$2" file="$3"
  [ -r "$file" ] || return
  awk -v wanted_section="$section" -v wanted_key="$key" '
    function normalized(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return tolower(value)
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      section = $0
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\][[:space:]]*$/, "", section)
      active = (tolower(section) == tolower(wanted_section))
      next
    }
    active {
      line = $0
      sub(/[[:space:]]*[#;].*$/, "", line)
      split(line, pair, "=")
      if (length(pair) >= 2 && normalized(pair[1]) == tolower(wanted_key)) {
        value = line
        sub(/^[^=]*=/, "", value)
        print normalized(value)
      }
    }
  ' "$file"
}

automount_root='/mnt'
automount_values="$(wsl_values automount root "$wsl_conf")"
if [ "$(printf '%s\n' "$automount_values" | sed '/^$/d' | wc -l)" -eq 1 ]; then
  automount_root="${automount_values%/}"
  [ -n "$automount_root" ] || automount_root='/'
fi

ok() { passes=$((passes + 1)); printf '[OK]   %s\n' "$*"; }
warn() { warnings=$((warnings + 1)); printf '[WARN] %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '[FAIL] %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$1"; }

is_windows_path() {
  local path="$1" mount_info filesystem options
  mount_info="$(findmnt -n -o FSTYPE,OPTIONS --target "$path" 2>/dev/null || true)"
  filesystem="${mount_info%% *}"
  options="${mount_info#* }"
  case "$filesystem" in
    drvfs) return 0 ;;
    9p)
      case ",$options," in
        *,aname=drvfs,*|*,aname=drvfs\;*) return 0 ;;
      esac
      ;;
  esac
  if [ "$automount_root" = '/' ]; then
    case "$path" in
      /[a-zA-Z]|/[a-zA-Z]/*) return 0 ;;
    esac
  else
    case "$path" in
      "$automount_root"/[a-zA-Z]|"$automount_root"/[a-zA-Z]/*) return 0 ;;
    esac
  fi
  return 1
}

section 'Workspace'
if is_windows_path "$workspace"; then
  fail "workspace is on a Windows mount: $workspace"
elif [ ! -d "$workspace" ]; then
  fail "workspace does not exist: $workspace"
elif [ ! -w "$workspace" ]; then
  fail "workspace is not writable: $workspace"
else
  owner="$(stat -c '%u' "$workspace" 2>/dev/null || true)"
  if [ -n "$owner" ] && [ "$owner" != "$(id -u)" ]; then
    warn "workspace is writable but owned by uid $owner: $workspace"
  else
    ok "workspace is Linux filesystem, writable, and owned by the current user: $workspace"
  fi
fi

section 'Shell startup files'
for rc_file in "$home_dir/.profile" "$home_dir/.bashrc"; do
  if [ ! -e "$rc_file" ]; then
    warn "missing: $rc_file"
  elif [ ! -r "$rc_file" ]; then
    fail "not readable: $rc_file"
  elif bash -n "$rc_file" 2>/dev/null; then
    ok "readable and syntactically valid: $rc_file"
  else
    fail "bash syntax check failed: $rc_file"
  fi
  if [ -r "$rc_file" ] && grep -Eq '/mnt/[[:alpha:]](/|$)' "$rc_file"; then
    warn "Windows mount reference found without executing: $rc_file"
  fi
done

section 'Current PATH'
windows_entries=0
duplicate_entries=0
seen_path=':'
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  if is_windows_path "$entry"; then
    windows_entries=$((windows_entries + 1))
    warn "Windows PATH entry is visible: $entry"
  fi
  case "$seen_path" in
    *":$entry:") duplicate_entries=$((duplicate_entries + 1)); warn "duplicate PATH entry: $entry" ;;
    *) seen_path="${seen_path}${entry}:" ;;
  esac
done < <(printf '%s' "${PATH:-}" | tr ':' '\n')
[ "$windows_entries" -eq 0 ] && ok 'no Windows mount entries are visible in PATH'
[ "$duplicate_entries" -eq 0 ] && ok 'no duplicate non-empty PATH entries are visible'

section 'Locale and time'
charmap="$(locale charmap 2>/dev/null || true)"
case "$charmap" in
  UTF-8|utf8|UTF8) ok "locale charmap is UTF-8: $charmap" ;;
  '') warn 'locale charmap could not be determined' ;;
  *) warn "locale charmap is not UTF-8: $charmap" ;;
esac
if [ -n "${LANG:-}" ]; then
  ok "LANG is set: $LANG"
else
  warn 'LANG is unset'
fi
timezone="$(date +%Z 2>/dev/null || true)"
if [ -n "$timezone" ]; then
  ok "timezone is available: $timezone"
else
  warn 'timezone could not be determined'
fi

section 'Git and SSH'
git_with_home() {
  env -u GIT_CONFIG_GLOBAL HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" git "$@"
}
workspace_is_git=0
if git_with_home -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  workspace_is_git=1
fi
git_identity_configured() {
  local setting="$1"
  if [ "$workspace_is_git" -eq 1 ]; then
    git_with_home -C "$workspace" config --get "$setting" >/dev/null 2>&1
  else
    git_with_home config --global --get "$setting" >/dev/null 2>&1
  fi
}
for setting in user.name user.email; do
  if git_identity_configured "$setting"; then
    ok "Git $setting is configured"
  else
    warn "Git $setting is unset"
  fi
done
for setting in init.defaultBranch core.autocrlf; do
  if git_with_home config --global --get "$setting" >/dev/null 2>&1; then
    ok "Git $setting is configured"
  else
    warn "Git $setting is unset"
  fi
done
if [ "$workspace_is_git" -eq 1 ]; then
  if git_with_home -C "$workspace" config --get core.filemode >/dev/null 2>&1; then
    ok 'Git core.filemode is configured for the workspace'
  else
    warn 'Git core.filemode is unset for the workspace'
  fi
else
  ok 'Git core.filemode is not checked because the workspace is not a Git repository'
fi
if git_with_home config --global --get-all credential.helper >/dev/null 2>&1; then
  ok 'Git credential helper is configured'
else
  warn 'Git credential helper is unset'
fi
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
  if ssh-add -l >/dev/null 2>&1; then
    ok 'SSH agent socket is available and has an identity'
  else
    warn 'SSH agent socket is available but has no usable identity'
  fi
else
  warn 'SSH agent socket is unavailable'
fi

section 'Resources and WSL configuration'
cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
case "$cpu_count" in
  ''|*[!0-9]*) warn 'CPU count could not be determined' ;;
  0|1) warn "CPU count is low: $cpu_count" ;;
  *) ok "CPU count: $cpu_count" ;;
esac
memory_kib="$(awk '/MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || true)"
if [ -n "$memory_kib" ]; then
  if [ "$memory_kib" -lt 4194304 ]; then warn "memory is below 4 GiB: ${memory_kib} KiB"; else ok "memory: ${memory_kib} KiB"; fi
else
  warn 'memory could not be determined'
fi
swap_kib="$(awk '/SwapTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || true)"
if [ -n "$swap_kib" ] && [ "$swap_kib" -gt 0 ]; then ok "swap: ${swap_kib} KiB"; else warn 'swap is disabled or could not be determined'; fi
disk_kib="$(df -Pk "$workspace" 2>/dev/null | awk 'NR == 2 { print $4 }')"
if [ -n "$disk_kib" ]; then
  if [ "$disk_kib" -lt 10485760 ]; then warn "free workspace disk is below 10 GiB: ${disk_kib} KiB"; else ok "free workspace disk: ${disk_kib} KiB"; fi
else
  warn 'free workspace disk could not be determined'
fi
if [ -r "$wsl_conf" ]; then
  interop_values="$(wsl_values interop appendWindowsPath "$wsl_conf")"
  interop_count="$(printf '%s\n' "$interop_values" | sed '/^$/d' | wc -l)"
  if [ "$interop_count" -eq 1 ] && [ "$interop_values" = 'false' ]; then
    ok "$wsl_conf disables automatic Windows PATH import"
  else
    warn "$wsl_conf does not have exactly one [interop] appendWindowsPath=false setting"
  fi
else
  warn "$wsl_conf is absent or unreadable"
fi

section 'Baseline commands'
for command_name in bash git ssh curl wget jq make gcc; do
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "available: $command_name"
  else
    warn "missing baseline command: $command_name"
  fi
done

printf '\nResult: %s ok | %s warn | %s fail\n' "$passes" "$warnings" "$failures"
if [ "$strict" -eq 1 ] && [ "$failures" -gt 0 ]; then
  exit 1
fi
