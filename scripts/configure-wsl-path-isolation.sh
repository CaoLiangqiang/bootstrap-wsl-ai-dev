#!/usr/bin/env bash
set -Eeuo pipefail

config_file="/etc/wsl.conf"
check_only=0

usage() {
  printf '%s\n' \
    'Usage: configure-wsl-path-isolation.sh [--check] [--file PATH]' \
    'Sets [interop] appendWindowsPath=false without changing WSL networking.' \
    '' \
    '  --check      report whether the file already has the target state' \
    '  --file PATH  operate on another file (useful for review and testing)'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      check_only=1
      shift
      ;;
    --file)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      config_file="$2"
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

render_config() {
  awk '
    function section_name(line, name) {
      name = line
      sub(/^[[:space:]]*\[/, "", name)
      sub(/\][[:space:]]*$/, "", name)
      return tolower(name)
    }

    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      if (in_interop && !setting_written) {
        print "appendWindowsPath=false"
      }

      in_interop = (section_name($0) == "interop")
      if (in_interop) {
        seen_interop = 1
        setting_written = 0
      }
      print
      next
    }

    in_interop && /^[[:space:]]*appendWindowsPath[[:space:]]*=/ {
      if (!setting_written) {
        print "appendWindowsPath=false"
        setting_written = 1
      }
      next
    }

    { print }

    END {
      if (in_interop && !setting_written) {
        print "appendWindowsPath=false"
      }
      if (!seen_interop) {
        if (NR > 0) {
          print ""
        }
        print "[interop]"
        print "appendWindowsPath=false"
      }
    }
  ' "$1"
}

source_file="$config_file"
if [ ! -e "$source_file" ]; then
  source_file="/dev/null"
fi

config_dir="$(dirname "$config_file")"
if [ ! -d "$config_dir" ]; then
  printf 'Parent directory does not exist: %s\n' "$config_dir" >&2
  exit 1
fi

tmp_file="$(mktemp "${TMPDIR:-/tmp}/wsl.conf.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT
render_config "$source_file" > "$tmp_file"

if [ -e "$config_file" ] && cmp -s "$config_file" "$tmp_file"; then
  printf 'OK: %s already sets [interop] appendWindowsPath=false\n' "$config_file"
  exit 0
fi

if [ "$check_only" -eq 1 ]; then
  printf 'CHANGE NEEDED: %s does not have the canonical isolation setting\n' "$config_file"
  printf 'No files were modified.\n'
  exit 1
fi

if [ "$config_file" = "/etc/wsl.conf" ] && [ "$(id -u)" -ne 0 ]; then
  printf 'Run with sudo to update /etc/wsl.conf. Do not provide the password to an agent.\n' >&2
  exit 1
fi

if [ -e "$config_file" ]; then
  backup_file="$config_file.backup.$(date +%Y%m%d%H%M%S)"
  cp --preserve=all "$config_file" "$backup_file"
  cat "$tmp_file" > "$config_file"
  printf 'Backup: %s\n' "$backup_file"
else
  install -m 0644 "$tmp_file" "$config_file"
fi

printf 'Updated: %s\n' "$config_file"
printf 'Only appendWindowsPath was changed; networking settings were preserved.\n'
printf 'From Windows PowerShell, run: wsl --shutdown\n'
