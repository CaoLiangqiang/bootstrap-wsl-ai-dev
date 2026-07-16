#!/usr/bin/env bash
set -uo pipefail

strict=0
run_doctors=1
passes=0
warnings=0
failures=0

usage() {
  printf '%s\n' \
    'Usage: verify-ai-cli-migration.sh [--strict] [--skip-doctors]' \
    'Verifies that WSL resolves native AI CLIs and does not inherit Windows PATH.' \
    '' \
    '  --strict        require the full reference profile, including Codex, Kiro, Feishu, uv, and Docker' \
    '  --skip-doctors  skip Codex and interactive Kiro diagnostics'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict)
      strict=1
      shift
      ;;
    --skip-doctors)
      run_doctors=0
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

pass() {
  passes=$((passes + 1))
  printf '[OK]   %s\n' "$*"
}

warn() {
  warnings=$((warnings + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  failures=$((failures + 1))
  printf '[FAIL] %s\n' "$*"
}

section() {
  printf '\n== %s ==\n' "$1"
}

missing_expected() {
  if [ "$strict" -eq 1 ]; then
    fail "$1 is not installed"
  else
    warn "$1 is not installed"
  fi
}

is_windows_path() {
  case "$1" in
    /mnt/[a-zA-Z]/*) return 0 ;;
    *) return 1 ;;
  esac
}

section "WSL boundary"
if [ -n "${WSL_DISTRO_NAME:-}" ] || uname -r | grep -qi microsoft; then
  pass "running inside WSL"
else
  fail "this verifier is intended for WSL"
fi

if bash "$(dirname "$0")/configure-wsl-path-isolation.sh" --check >/dev/null 2>&1; then
  pass "/etc/wsl.conf disables automatic Windows PATH import"
else
  fail "/etc/wsl.conf needs [interop] appendWindowsPath=false"
fi

windows_path_count=0
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  if is_windows_path "$entry"; then
    windows_path_count=$((windows_path_count + 1))
    fail "Windows PATH entry is visible: $entry"
  fi
done < <(printf '%s' "$PATH" | tr ':' '\n')
if [ "$windows_path_count" -eq 0 ]; then
  pass "current PATH contains no /mnt/<drive> entries"
fi

if [ -x /mnt/c/Windows/System32/cmd.exe ]; then
  if (cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /d /c "exit 0") >/dev/null 2>&1; then
    pass "explicit Windows interop still works by absolute path"
  else
    warn "cmd.exe exists but explicit WSL interop failed"
  fi
else
  warn "cmd.exe was not found at the standard Windows path"
fi

section "Native command origins"
native_commands=(
  codex kiro-cli claude opencode
  node npm pnpm bun
  feishu feishu-mcp-pro lark-cli
  git gh rg uv docker
)
for cmd in "${native_commands[@]}"; do
  path="$(command -v "$cmd" 2>/dev/null || true)"
  if [ -z "$path" ]; then
    missing_expected "$cmd"
  elif is_windows_path "$path"; then
    fail "$cmd resolves to Windows: $path"
  else
    pass "$cmd -> $path"
  fi
done

section "Commands expected to be absent from WSL PATH"
isolated_commands=(
  kiro powershell.exe cmd.exe explorer.exe
  gemini micode crush paseo happy happy-coder uipro uipro-cli
  agentic-hackathon figma-mcp gerrit-mcp playwright-cli defuddle
)
for cmd in "${isolated_commands[@]}"; do
  path="$(command -v "$cmd" 2>/dev/null || true)"
  if [ -z "$path" ]; then
    pass "$cmd is absent"
  else
    fail "$cmd unexpectedly resolves to $path"
  fi
done

section "Configuration safety"
config_files=(
  "$HOME/.claude/settings.json"
  "$HOME/.config/opencode/opencode.json"
  "$HOME/.config/opencode/oh-my-openagent.json"
  "$HOME/.codex/config.toml"
  "$HOME/.kiro/settings/cli.json"
  "$HOME/.kiro/settings/mcp.json"
  "$HOME/.kiro/settings/permissions.yaml"
)
for file in "${config_files[@]}"; do
  [ -e "$file" ] || continue
  mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
  case "$mode" in
    600|400)
      pass "$file has private mode $mode"
      ;;
    *)
      warn "$file has mode ${mode:-unknown}; use 600 when it may contain credentials"
      ;;
  esac

  if grep -Eiq '(/mnt/[a-z]/|[a-z]:\\+)' "$file" 2>/dev/null; then
    fail "$file contains a Windows path; review it without printing secrets"
  fi
done

while IFS= read -r link; do
  target="$(readlink "$link" 2>/dev/null || true)"
  if is_windows_path "$target"; then
    fail "$link points into Windows: $target"
  fi
done < <(find "$HOME/.agents/skills" "$HOME/.kiro" -type l -print 2>/dev/null)

section "Authentication and diagnostics"
if command -v gh >/dev/null 2>&1; then
  if timeout 15 gh auth status >/dev/null 2>&1; then
    pass "GitHub CLI authentication is configured"
  else
    warn "GitHub CLI authentication is unavailable or unreachable"
  fi
fi

if command -v claude >/dev/null 2>&1; then
  if timeout 15 claude auth status >/dev/null 2>&1; then
    pass "Claude Code authentication is configured"
  else
    warn "Claude Code authentication is unavailable"
  fi
fi

if [ "$run_doctors" -eq 1 ] && command -v codex >/dev/null 2>&1; then
  doctor_output="$(mktemp "${TMPDIR:-/tmp}/codex-doctor.XXXXXX")"
  if timeout 60 codex doctor --summary --ascii --no-color > "$doctor_output" 2>&1 \
      && grep -Eq '0 fail([[:space:]]|$)' "$doctor_output"; then
    pass "Codex Doctor reports zero failures"
  else
    warn "Codex Doctor did not report a clean summary; run it directly for details"
  fi
  rm -f "$doctor_output"
fi

if [ "$run_doctors" -eq 1 ] && command -v kiro-cli >/dev/null 2>&1; then
  if [ -t 0 ] && [ -t 1 ]; then
    warn "run 'kiro-cli doctor --all' after leaving full-screen AI CLIs to test Qterm"
  elif pgrep -f 'kiro-cli-term' >/dev/null 2>&1; then
    pass "Kiro terminal integration process is running"
  else
    warn "Kiro Doctor needs a real interactive terminal for its Qterm check"
  fi
fi

printf '\nResult: %s ok | %s warn | %s fail\n' "$passes" "$warnings" "$failures"
if [ "$failures" -gt 0 ]; then
  exit 1
fi
