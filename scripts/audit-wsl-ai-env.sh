#!/usr/bin/env bash
set -uo pipefail

section() {
  printf '\n== %s ==\n' "$1"
}

first_line() {
  output="$(timeout 5 "$@" 2>&1)"
  status="$?"
  if [ "$status" -eq 124 ]; then
    printf 'version probe timed out'
  else
    printf '%s\n' "$output" | head -n 1
  fi
}

section "Platform"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  printf 'OS: %s\n' "$PRETTY_NAME"
fi
printf 'Kernel: %s\n' "$(uname -r)"
printf 'WSL distro: %s\n' "$(printenv WSL_DISTRO_NAME 2>/dev/null || printf 'not detected')"
printf 'PID 1: %s\n' "$(ps -p 1 -o comm= 2>/dev/null | xargs)"
if [ -r /etc/wsl.conf ]; then
  printf '%s\n' '/etc/wsl.conf:'
  sed -n '1,120p' /etc/wsl.conf
fi

section "Command origins"
for cmd in git gh ssh python python3 pip pip3 uv uvx node npm npx corepack pnpm yarn codex claude kimi trae aider opencode docker; do
  path="$(command -v "$cmd" 2>/dev/null || true)"
  [ -n "$path" ] || continue
  case "$cmd" in
    ssh)
      version="$(first_line ssh -V)"
      ;;
    docker)
      version="$(first_line docker --version)"
      ;;
    pnpm|yarn)
      version="package-manager shim; version probe skipped"
      ;;
    *)
      version="$(first_line "$cmd" --version)"
      ;;
  esac
  printf '%-12s %-65s %s\n' "$cmd" "$path" "$version"
done

section "Windows PATH entries visible in this shell"
windows_count=0
stale_count=0
while IFS= read -r entry; do
  case "$entry" in
    /mnt/*)
      windows_count=$((windows_count + 1))
      if [ -e "$entry" ]; then
        printf 'exists  %s\n' "$entry"
      else
        stale_count=$((stale_count + 1))
        printf 'stale? %s\n' "$entry"
      fi
      ;;
  esac
done < <(printf '%s' "$PATH" | tr ':' '\n')
printf 'Visible Windows entries: %s; missing targets in this shell: %s\n' "$windows_count" "$stale_count"

section "Proxy variables"
for name in HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy; do
  if printenv "$name" >/dev/null 2>&1; then
    printf '%-12s set\n' "$name"
  else
    printf '%-12s unset\n' "$name"
  fi
done

section "Git and GitHub"
printf 'Git name: %s\n' "$(git config --global --get user.name 2>/dev/null || printf 'unset')"
printf 'Git email: %s\n' "$(git config --global --get user.email 2>/dev/null || printf 'unset')"
if command -v gh >/dev/null 2>&1; then
  if timeout 10 gh auth status >/dev/null 2>&1; then
    printf 'GitHub CLI auth: configured\n'
  else
    printf 'GitHub CLI auth: not configured or not reachable\n'
  fi
fi

section "AI CLI authentication"
if command -v codex >/dev/null 2>&1; then
  printf 'Codex: installed; use codex doctor for a redacted full check\n'
fi
if command -v claude >/dev/null 2>&1; then
  if timeout 10 claude auth status >/dev/null 2>&1; then
    printf 'Claude Code auth: configured\n'
  else
    printf 'Claude Code auth: not configured\n'
  fi
fi

section "Docker"
if command -v docker >/dev/null 2>&1; then
  docker --version 2>&1 || true
  docker compose version 2>&1 || true
  printf 'Service active: %s\n' "$(systemctl is-active docker 2>/dev/null || printf 'unknown')"
  printf 'Service enabled: %s\n' "$(systemctl is-enabled docker 2>/dev/null || printf 'unknown')"
  if timeout 10 docker info >/dev/null 2>&1; then
    printf 'Non-root daemon access: yes\n'
  else
    printf 'Non-root daemon access: no or unavailable in this process\n'
  fi
else
  printf 'Docker: not installed\n'
fi

section "Known one-time artifacts"
found=0
for path in "$HOME/codex-linux-x64.tgz" "$HOME/get-docker.sh" "$HOME/.nvm/install.sh"; do
  if [ -e "$path" ]; then
    found=1
    du -sh "$path" 2>/dev/null || printf '%s\n' "$path"
  fi
done
[ "$found" -eq 1 ] || printf 'No known installer artifacts found\n'

section "Codex standalone releases"
release_root="$HOME/.codex/packages/standalone/releases"
if [ -d "$release_root" ]; then
  for release in "$release_root"/*; do
    [ -d "$release" ] || continue
    du -sh "$release" 2>/dev/null
  done
else
  printf 'No standalone release directory\n'
fi

section "Name-based residue candidates"
find "$HOME" -maxdepth 4 \( -iname '*kimi*' -o -iname '*trae*' -o -iname '*moonshot*' \) -print 2>/dev/null | sed -n '1,120p'
printf '\nAudit complete. Treat name matches as candidates, not automatic deletion targets.\n'
