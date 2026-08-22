#!/usr/bin/env bash
set -uo pipefail

usage() {
  printf '%s\n' \
    'Usage: check-config-windows-paths.sh FILE' \
    'Returns nonzero only when FILE contains a Windows command or executable path.' \
    'Shared project and data paths under /mnt/<drive> are allowed.'
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

file="$1"
if [ ! -f "$file" ]; then
  printf 'Configuration file does not exist: %s\n' "$file" >&2
  exit 2
fi

while IFS= read -r line || [ -n "$line" ]; do
  lower="${line,,}"
  has_windows_path=0
  case "$lower" in
    *"/mnt/"[a-z]"/"*|*[a-z]:/*|*[a-z]:\\*)
      has_windows_path=1
      ;;
  esac
  [ "$has_windows_path" -eq 1 ] || continue

  case "$lower" in
    \[projects.*\])
      continue
      ;;
  esac

  case "$lower" in
    *appdata/roaming/npm*|*appdata\\roaming\\npm*|*.exe*|*.com*|*.cmd*|*.bat*|*.ps1*)
      printf 'UNSAFE: %s contains a Windows executable or command shim path\n' "$file"
      exit 1
      ;;
  esac

  if printf '%s\n' "$lower" \
      | grep -Eq '(^|[{"[:space:]])(cmd|command|executable|binary|program|shell)(["[:space:]]*)[=:]'; then
    printf 'UNSAFE: %s contains a Windows path in a command setting\n' "$file"
    exit 1
  fi
done < "$file"

printf 'SAFE: %s contains no Windows command or executable path\n' "$file"
