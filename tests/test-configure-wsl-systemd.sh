#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/configure-wsl-systemd.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/wsl-systemd-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_line() { grep -Fqx "$1" "$2" || fail "missing '$1' in $2"; }

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

printf 'PASS: configure-wsl-systemd preserves network and interop settings\n'
