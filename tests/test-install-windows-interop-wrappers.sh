#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/install-windows-interop-wrappers.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/windows-wrapper-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }

fake_bin="$test_dir/fake-bin"
windows_root="$test_dir/Windows Root"
bin_dir="$test_dir/bin$(printf '\302\240')unicode"
log_dir="$test_dir/log"
mkdir -p "$fake_bin" "$windows_root/System32"
mkdir -p "$log_dir"
cat > "$fake_bin/wslpath" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_LOG/wslpath-args"
printf 'C:\\Converted Path\\target'
EOF
cat > "$windows_root/explorer.exe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_LOG/explorer-args"
EOF
cat > "$windows_root/System32/clip.exe" <<'EOF'
#!/usr/bin/env bash
cat > "$TEST_LOG/clip-stdin"
EOF
chmod 0755 "$fake_bin/wslpath"
chmod 0755 "$windows_root/explorer.exe" "$windows_root/System32/clip.exe"

bash "$script" --help | grep -F -- '--windows-root PATH' >/dev/null
for action in --check --install --remove; do
  expect_failure env -u HOME PATH="$fake_bin:/usr/bin:/bin" bash "$script" "$action" --windows-root "$windows_root"
done
explicit_bin="$test_dir/explicit-bin"
env -u HOME PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$explicit_bin" --windows-root "$windows_root" >/dev/null
if [ ! -x "$explicit_bin/win-open" ] || [ ! -x "$explicit_bin/win-clip" ]; then
  fail 'explicit bin-dir did not work without HOME'
fi
env -u HOME PATH="$fake_bin:/usr/bin:/bin" bash "$script" --remove --bin-dir "$explicit_bin" >/dev/null

default_home="$test_dir/default-home"
outside_default_bin="$test_dir/outside-default-bin"
mkdir -p "$default_home" "$outside_default_bin"
ln -s "$outside_default_bin" "$default_home/.local"
default_before="$(find "$outside_default_bin" -printf '%p %s %T@\n' | sort)"
for action in --check --install --remove; do
  expect_failure env HOME="$default_home" PATH="$fake_bin:/usr/bin:/bin" bash "$script" "$action" --windows-root "$windows_root"
done
default_after="$(find "$outside_default_bin" -printf '%p %s %T@\n' | sort)"
[ "$default_before" = "$default_after" ] || fail 'default .local symlink outside HOME was modified'

foreign_parent_home="$test_dir/foreign-parent-home"
mkdir -p "$foreign_parent_home/.local"
cat > "$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
last="${!#}"
if [ "${1:-}" = '-c' ] && [ "${2:-}" = '%u' ] && [ "$last" = "$FOREIGN_PARENT_HOME/.local" ]; then
  printf '%s\n' 424242
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
chmod 0755 "$fake_bin/stat"
expect_failure env FOREIGN_PARENT_HOME="$foreign_parent_home" HOME="$foreign_parent_home" PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --windows-root "$windows_root"
expect_failure env FOREIGN_PARENT_HOME="$foreign_parent_home" HOME="$foreign_parent_home" PATH="$fake_bin:/usr/bin:/bin" bash "$script" --remove
rm -f "$fake_bin/stat"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$bin_dir" --windows-root "$test_dir/missing-Windows"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --bad-option
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --check --install --bin-dir "$bin_dir" --windows-root "$windows_root"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir '' --windows-root "$windows_root"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir / --windows-root "$windows_root"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --check --bin-dir "$bin_dir" --windows-root "$windows_root"
[ ! -e "$bin_dir" ] || fail 'check created bin directory'

foreign_bin="$test_dir/foreign-bin"
mkdir -p "$foreign_bin"
foreign_before="$(find "$foreign_bin" -printf '%p %s %T@\n' | sort)"
cat > "$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = '-c' ] && [ "${2:-}" = '%u' ]; then
  printf '%s\n' 424242
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
chmod 0755 "$fake_bin/stat"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$foreign_bin" --windows-root "$windows_root"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --remove --bin-dir "$foreign_bin"
foreign_after="$(find "$foreign_bin" -printf '%p %s %T@\n' | sort)"
[ "$foreign_before" = "$foreign_after" ] || fail 'foreign-owned bin directory was modified'
rm -f "$fake_bin/stat"

env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$bin_dir" --windows-root "$windows_root" >/dev/null
if [ ! -x "$bin_dir/win-open" ] || [ ! -x "$bin_dir/win-clip" ]; then
  fail 'install did not create executable wrappers'
fi
grep -F "$(printf 'exec %q' "$windows_root/explorer.exe")" "$bin_dir/win-open" >/dev/null
grep -F "$(printf 'exec %q' "$windows_root/System32/clip.exe")" "$bin_dir/win-clip" >/dev/null
env PATH="$fake_bin:/usr/bin:/bin" bash "$bin_dir/win-open" --help | grep -F 'Usage: win-open' >/dev/null
env PATH="$fake_bin:/usr/bin:/bin" bash "$bin_dir/win-clip" --help | grep -F 'Usage: win-clip' >/dev/null
linux_path="$test_dir/Linux path$(printf '\302\240')unicode"
mkdir -p "$linux_path"
TEST_LOG="$log_dir" PATH="$fake_bin:/usr/bin:/bin" bash "$bin_dir/win-open" "$linux_path"
grep -F -- "-w $linux_path" "$log_dir/wslpath-args" >/dev/null
grep -F 'C:\Converted Path\target' "$log_dir/explorer-args" >/dev/null
printf 'clipboard text' | TEST_LOG="$log_dir" PATH="$fake_bin:/usr/bin:/bin" bash "$bin_dir/win-clip"
[ "$(cat "$log_dir/clip-stdin")" = 'clipboard text' ] || fail 'win-clip did not pass standard input to clip.exe'

env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --check --bin-dir "$bin_dir" --windows-root "$windows_root" >/dev/null
before_hash="$(sha256sum "$bin_dir/win-open" "$bin_dir/win-clip")"
env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$bin_dir" --windows-root "$windows_root" >/dev/null
after_hash="$(sha256sum "$bin_dir/win-open" "$bin_dir/win-clip")"
[ "$before_hash" = "$after_hash" ] || fail 'second wrapper install was not idempotent'

foreign_wrapper_before="$(sha256sum "$bin_dir/win-open" "$bin_dir/win-clip")"
cat > "$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
last="${!#}"
if [ "${1:-}" = '-c' ] && [ "${2:-}" = '%u' ] && [ "$last" = "$FOREIGN_WRAPPER" ]; then
  printf '%s\n' 424242
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
chmod 0755 "$fake_bin/stat"
expect_failure env FOREIGN_WRAPPER="$bin_dir/win-open" PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$bin_dir" --windows-root "$windows_root"
expect_failure env FOREIGN_WRAPPER="$bin_dir/win-open" PATH="$fake_bin:/usr/bin:/bin" bash "$script" --remove --bin-dir "$bin_dir"
[ "$foreign_wrapper_before" = "$(sha256sum "$bin_dir/win-open" "$bin_dir/win-clip")" ] || fail 'foreign-owned wrapper was changed'
rm -f "$fake_bin/stat"

open_hash_before_collision="$(sha256sum "$bin_dir/win-open")"
printf '%s\n' '#!/usr/bin/env bash' '# unrelated line' '# bootstrap-wsl-ai-dev: windows-interop-wrapper v1' > "$bin_dir/win-clip"
collision_output="$(env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --check --bin-dir "$bin_dir" --windows-root "$windows_root" 2>&1 || true)"
printf '%s\n' "$collision_output" | grep -F 'Refusing unowned wrapper collision' >/dev/null
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$bin_dir" --windows-root "$windows_root"
[ "$open_hash_before_collision" = "$(sha256sum "$bin_dir/win-open")" ] || fail 'second-file collision changed win-open'
rm -f "$bin_dir/win-clip"
env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$bin_dir" --windows-root "$windows_root" >/dev/null

env PATH='/usr/bin:/bin' bash "$script" --remove --bin-dir "$bin_dir" --windows-root "$test_dir/missing-Windows" >/dev/null
[ -d "$bin_dir" ] || fail 'remove deleted bin directory'
if [ -e "$bin_dir/win-open" ] || [ -e "$bin_dir/win-clip" ]; then
  fail 'remove left owned wrappers'
fi

printf '%s\n' '# local command' > "$bin_dir/win-open"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --bin-dir "$bin_dir" --windows-root "$windows_root"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --remove --bin-dir "$bin_dir" --windows-root "$windows_root"

printf 'PASS: Windows interop wrappers reject missing dependencies and collisions and preserve Unicode paths\n'
