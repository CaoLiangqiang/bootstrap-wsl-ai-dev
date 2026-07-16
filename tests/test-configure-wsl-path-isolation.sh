#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/configure-wsl-path-isolation.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/wsl-isolation-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_line() {
  local expected="$1"
  local file="$2"
  grep -Fqx "$expected" "$file" || fail "missing '$expected' in $file"
}

fixture="$test_dir/wsl.conf"
cat > "$fixture" <<'EOF'
[boot]
systemd=true

[wsl2]
networkingMode=nat
# networkingMode=mirrored
dnsTunneling=true

[interop]
enabled=true
appendWindowsPath=true
appendWindowsPath=true

[user]
default=tester
EOF

bash "$script" --file "$fixture" >/dev/null
assert_line 'networkingMode=nat' "$fixture"
assert_line '# networkingMode=mirrored' "$fixture"
assert_line 'dnsTunneling=true' "$fixture"
assert_line 'enabled=true' "$fixture"
assert_line 'appendWindowsPath=false' "$fixture"
assert_line 'default=tester' "$fixture"

setting_count="$(grep -Ec '^[[:space:]]*appendWindowsPath[[:space:]]*=' "$fixture")"
[ "$setting_count" -eq 1 ] || fail "expected one appendWindowsPath setting, found $setting_count"

bash "$script" --check --file "$fixture" >/dev/null
before_hash="$(sha256sum "$fixture")"
bash "$script" --file "$fixture" >/dev/null
after_hash="$(sha256sum "$fixture")"
[ "$before_hash" = "$after_hash" ] || fail 'second application was not idempotent'

without_interop="$test_dir/without-interop.conf"
cat > "$without_interop" <<'EOF'
[boot]
systemd=true

[user]
default=tester
EOF
bash "$script" --file "$without_interop" >/dev/null
assert_line '[interop]' "$without_interop"
assert_line 'appendWindowsPath=false' "$without_interop"
assert_line 'default=tester' "$without_interop"

empty_config="$test_dir/empty.conf"
bash "$script" --file "$empty_config" >/dev/null
assert_line '[interop]' "$empty_config"
assert_line 'appendWindowsPath=false' "$empty_config"

printf 'PASS: configure-wsl-path-isolation is targeted and idempotent\n'
