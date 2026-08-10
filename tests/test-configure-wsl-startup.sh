#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/configure-wsl-startup.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/wsl-startup-configure-test.XXXXXX")"
cleanup() {
  chmod -R u+w "$test_dir" 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }
assert_contains() { grep -F "$1" "$2" >/dev/null || fail "missing '$1' in $2"; }

home_dir="$test_dir/home"
workspace="$home_dir/src/workspace"
mkdir -p "$home_dir"
printf '%s\n' '# existing profile content' > "$home_dir/.profile"
printf '%s\n' '# existing bashrc content' > "$home_dir/.bashrc"

bash "$script" --help | grep -F -- '--install' >/dev/null
expect_failure bash "$script" --workspace
expect_failure bash "$script" --check --install --home "$home_dir" --workspace "$workspace"
expect_failure bash "$script" --home '' --workspace "$workspace"
expect_failure bash "$script" --check --home "$home_dir" --workspace "$workspace"
[ ! -e "$workspace" ] || fail 'check created the workspace'

readonly_home="$test_dir/readonly-home"
readonly_workspace="$readonly_home/src"
mkdir -p "$readonly_workspace" "$readonly_home/.local/bin"
printf '%s\n' '# readable but intentionally not writable' > "$readonly_home/.profile"
printf '%s\n' '# readable but intentionally not writable' > "$readonly_home/.bashrc"
chmod 0755 "$test_dir"
chmod 0500 "$readonly_home"
chmod 0400 "$readonly_home/.profile" "$readonly_home/.bashrc"
readonly_runner=()
if [ "$(id -u)" -eq 0 ]; then
  command -v setpriv >/dev/null 2>&1 || fail 'setpriv is required to test read-only paths as root'
  chown -R 65534:65534 "$readonly_home"
  readonly_runner=(setpriv --reuid=65534 --regid=65534 --clear-groups)
fi
readonly_status=0
readonly_output="$("${readonly_runner[@]}" bash "$script" --check --home "$readonly_home" --workspace "$readonly_workspace" 2>&1)" || readonly_status=$?
[ "$readonly_status" -eq 1 ] || fail "read-only HOME and rc check returned $readonly_status instead of change-needed"
printf '%s\n' "$readonly_output" | grep -F 'CHANGE NEEDED' >/dev/null
printf '%s\n' "$readonly_output" | grep -F 'Home directory is not writable' >/dev/null \
  && fail 'check rejected an otherwise readable non-writable HOME or rc file'
printf '%s\n' "$readonly_output" | grep -F 'Startup file must be writable' >/dev/null \
  && fail 'check rejected an otherwise readable non-writable rc file'

bash "$script" --install --home "$home_dir" --workspace "$workspace" >/dev/null
[ -d "$workspace" ] || fail 'install did not create workspace'
[ -d "$home_dir/.local/bin" ] || fail 'install did not create local bin directory'
for rc_file in "$home_dir/.profile" "$home_dir/.bashrc"; do
  assert_contains '# existing' "$rc_file"
  assert_contains '# >>> bootstrap-wsl-ai-dev startup PATH >>>' "$rc_file"
  assert_contains "export PATH=\"\$HOME/.local/bin:\$PATH\"" "$rc_file"
  ls "${rc_file}.bootstrap-wsl-ai-dev.startup.backup."* >/dev/null 2>&1 || fail "missing backup for $rc_file"
done

bash "$script" --check --home "$home_dir" --workspace "$workspace" >/dev/null
before_hash="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
bash "$script" --install --home "$home_dir" --workspace "$workspace" >/dev/null
after_hash="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
[ "$before_hash" = "$after_hash" ] || fail 'second install was not idempotent'

fake_bin="$test_dir/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 0755 "$fake_bin/mv"
remove_before_hash="$(sha256sum "$home_dir/.profile")"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --remove --home "$home_dir" --workspace "$workspace"
[ "$remove_before_hash" = "$(sha256sum "$home_dir/.profile")" ] || fail 'failed atomic remove changed the rc file'

profile_mode_before_remove="$(stat -c '%a' "$home_dir/.profile")"
outside_workspace="$test_dir/outside-workspace"
outside_local_bin="$test_dir/outside-local-bin"
mkdir -p "$outside_workspace" "$outside_local_bin/bin"
mv "$workspace" "$home_dir/original-workspace"
ln -s "$outside_workspace" "$workspace"
mv "$home_dir/.local" "$home_dir/original-local"
ln -s "$outside_local_bin" "$home_dir/.local"
bash "$script" --remove --home "$home_dir" --workspace "$workspace" >/dev/null
if [ ! -L "$workspace" ] || [ ! -L "$home_dir/.local" ]; then
  fail 'remove changed workspace or local-bin links that it does not own'
fi
for rc_file in "$home_dir/.profile" "$home_dir/.bashrc"; do
  assert_contains '# existing' "$rc_file"
  grep -F 'bootstrap-wsl-ai-dev startup PATH' "$rc_file" >/dev/null && fail "remove left marker in $rc_file"
  removal_backup=''
  for backup in "${rc_file}.bootstrap-wsl-ai-dev.startup.backup."*; do
    grep -F 'bootstrap-wsl-ai-dev startup PATH' "$backup" >/dev/null && removal_backup="$backup"
  done
  [ -n "$removal_backup" ] || fail "missing removal backup for $rc_file"
  [ "$(stat -c '%a' "$removal_backup")" = "$profile_mode_before_remove" ] || fail "removal backup mode changed for $rc_file"
done
bash "$script" --remove --home "$home_dir" --workspace "$workspace" >/dev/null

collision_home="$test_dir/collision-home"
mkdir -p "$collision_home"
printf '%s\n' '# >>> bootstrap-wsl-ai-dev startup PATH >>>' > "$collision_home/.profile"
expect_failure bash "$script" --install --home "$collision_home" --workspace "$collision_home/src"
[ ! -e "$collision_home/src" ] || fail 'collision created workspace before refusing'

nonregular_home="$test_dir/nonregular-home"
mkdir -p "$nonregular_home/.profile"
expect_failure bash "$script" --install --home "$nonregular_home" --workspace "$nonregular_home/src"
[ ! -e "$nonregular_home/src" ] || fail 'nonregular rc created workspace before refusing'

symlink_home="$test_dir/symlink-home"
outside_rc="$test_dir/outside-rc"
dangling_rc="$test_dir/dangling-rc"
mkdir -p "$symlink_home"
printf '%s\n' '# outside content' > "$outside_rc"
ln -s "$outside_rc" "$symlink_home/.profile"
printf '%s\n' '# normal bashrc' > "$symlink_home/.bashrc"
outside_hash="$(sha256sum "$outside_rc")"
for action in --check --install --remove; do
  expect_failure bash "$script" "$action" --home "$symlink_home" --workspace "$symlink_home/src"
done
[ "$outside_hash" = "$(sha256sum "$outside_rc")" ] || fail 'rc symlink caused an outside file change'
rm "$symlink_home/.profile"
ln -s "$dangling_rc" "$symlink_home/.profile"
for action in --check --install --remove; do
  expect_failure bash "$script" "$action" --home "$symlink_home" --workspace "$symlink_home/src"
done
[ ! -e "$dangling_rc" ] || fail 'dangling rc symlink was followed during install'

atomic_home="$test_dir/atomic-home"
mkdir -p "$atomic_home"
printf '%s\n' '# original profile' > "$atomic_home/.profile"
printf '%s\n' '# original bashrc' > "$atomic_home/.bashrc"
atomic_hash="$(sha256sum "$atomic_home/.profile")"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --home "$atomic_home" --workspace "$atomic_home/src"
[ "$atomic_hash" = "$(sha256sum "$atomic_home/.profile")" ] || fail 'failed atomic install changed the rc file'

foreign_home="$test_dir/foreign-home"
mkdir -p "$foreign_home/src" "$foreign_home/.local/bin"
printf '%s\n' '# profile' > "$foreign_home/.profile"
printf '%s\n' '# bashrc' > "$foreign_home/.bashrc"
foreign_before="$(find "$foreign_home" -printf '%p %s %T@\n' | sort)"
cat > "$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = '-c' ] && [ "${2:-}" = '%u' ]; then
  printf '%s\n' 424242
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
chmod 0755 "$fake_bin/stat"
expect_failure env PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --home "$foreign_home" --workspace "$foreign_home/src"
foreign_after="$(find "$foreign_home" -printf '%p %s %T@\n' | sort)"
[ "$foreign_before" = "$foreign_after" ] || fail 'foreign-owned inputs were modified'

outside_local="$test_dir/outside-local"
local_symlink_home="$test_dir/local-symlink-home"
mkdir -p "$outside_local" "$local_symlink_home"
printf '%s\n' '# profile' > "$local_symlink_home/.profile"
printf '%s\n' '# bashrc' > "$local_symlink_home/.bashrc"
ln -s "$outside_local" "$local_symlink_home/.local"
outside_local_before="$(find "$outside_local" -printf '%p %s %T@\n' | sort)"
for action in --check --install; do
  expect_failure bash "$script" "$action" --home "$local_symlink_home" --workspace "$local_symlink_home/src"
done
bash "$script" --remove --home "$local_symlink_home" --workspace "$local_symlink_home/src" >/dev/null
outside_local_after="$(find "$outside_local" -printf '%p %s %T@\n' | sort)"
[ "$outside_local_before" = "$outside_local_after" ] || fail 'local-bin symlink outside HOME was modified'

foreign_parent_home="$test_dir/foreign-parent-home"
mkdir -p "$foreign_parent_home/src" "$foreign_parent_home/.local"
printf '%s\n' '# profile' > "$foreign_parent_home/.profile"
printf '%s\n' '# bashrc' > "$foreign_parent_home/.bashrc"
foreign_parent_before="$(find "$foreign_parent_home" -printf '%p %s %T@\n' | sort)"
cat > "$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
last="${!#}"
if [ "${1:-}" = '-c' ] && [ "${2:-}" = '%u' ] \
    && { [ "$last" = "$FOREIGN_PARENT_HOME/src" ] || [ "$last" = "$FOREIGN_PARENT_HOME/.local" ]; }; then
  printf '%s\n' 424242
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
chmod 0755 "$fake_bin/stat"
expect_failure env FOREIGN_PARENT_HOME="$foreign_parent_home" PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --home "$foreign_parent_home" --workspace "$foreign_parent_home/src/new-workspace"
env FOREIGN_PARENT_HOME="$foreign_parent_home" PATH="$fake_bin:/usr/bin:/bin" bash "$script" --remove --home "$foreign_parent_home" --workspace "$foreign_parent_home/src/new-workspace" >/dev/null
expect_failure env FOREIGN_PARENT_HOME="$foreign_parent_home" PATH="$fake_bin:/usr/bin:/bin" bash "$script" --install --home "$foreign_parent_home" --workspace "$foreign_parent_home"
foreign_parent_after="$(find "$foreign_parent_home" -printf '%p %s %T@\n' | sort)"
[ "$foreign_parent_before" = "$foreign_parent_after" ] || fail 'foreign parent directory received writes'

printf 'PASS: configure-wsl-startup uses owned blocks, backups, idempotence, and reversible user-only changes\n'
