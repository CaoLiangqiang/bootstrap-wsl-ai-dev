#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/configure-wsl-systemd.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/wsl-systemd-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_line() { grep -Fqx "$1" "$2" || fail "missing '$1' in $2"; }
expect_status() {
  local expected="$1"
  shift
  local actual=0
  "$@" >/dev/null 2>&1 || actual="$?"
  [ "$actual" -eq "$expected" ] || fail "expected status $expected, got $actual: $*"
}

expect_status 2 bash "$script" --user
expect_status 2 bash "$script" --file
expect_status 2 bash "$script" --file '' --user tester

fixture="$test_dir/wsl.conf"
cat > "$fixture" <<'EOF'
[boot]
systemd=false

[wsl2]
networkingMode=nat
dnsTunneling=true

[interop]
appendWindowsPath=false
EOF

bash "$script" --file "$fixture" --user tester >/dev/null
assert_line 'systemd=true' "$fixture"
assert_line 'default=tester' "$fixture"
assert_line 'networkingMode=nat' "$fixture"
assert_line 'dnsTunneling=true' "$fixture"
assert_line 'appendWindowsPath=false' "$fixture"

before_hash="$(sha256sum "$fixture")"
bash "$script" --check --file "$fixture" --user tester >/dev/null
bash "$script" --file "$fixture" --user tester >/dev/null
after_hash="$(sha256sum "$fixture")"
[ "$before_hash" = "$after_hash" ] || fail 'second application was not idempotent'

if [ "$(id -u)" -ne 0 ]; then
  check_output=''
  check_status=0
  check_output="$(bash "$script" --check --user "$(id -un)" 2>&1)" || check_status="$?"
  [ "$check_status" -eq 0 ] || [ "$check_status" -eq 1 ] \
    || fail "read-only /etc/wsl.conf check returned unexpected status $check_status"
  printf '%s\n' "$check_output" | grep -F 'Run with sudo' >/dev/null \
    && fail 'read-only /etc/wsl.conf check required sudo'
fi

printf 'PASS: configure-wsl-systemd validates input and preserves network and interop settings\n'
