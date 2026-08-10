#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/audit-wsl-startup.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/wsl-startup-audit-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }

home_dir="$test_dir/home"
workspace="$home_dir/src/project"
healthy_wsl_conf="$test_dir/wsl.conf"
mkdir -p "$workspace"
printf '%s\n' 'export EDITOR=vi' > "$home_dir/.profile"
printf '%s\n' 'alias ll="ls -al"' > "$home_dir/.bashrc"
git init -q "$workspace"
git -C "$workspace" config user.name 'Fixture User'
git -C "$workspace" config user.email 'fixture@example.invalid'
git -C "$workspace" config core.filemode false
cat > "$healthy_wsl_conf" <<'EOF'
[interop]
appendWindowsPath=false

[automount]
root=/mnt/
EOF

bash "$script" --help | grep -F -- '--wsl-conf PATH' >/dev/null
expect_failure bash "$script" --unknown
expect_failure bash "$script" --home '' --workspace "$workspace"
expect_failure bash "$script" --home "$test_dir/missing-home" --workspace "$workspace"

before="$(find "$home_dir" -printf '%p %T@ %s\n' | sort)"
healthy_output="$(env -i HOME="$home_dir" PATH='/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace "$workspace" --wsl-conf "$healthy_wsl_conf" --strict)"
after="$(find "$home_dir" -printf '%p %T@ %s\n' | sort)"
[ "$before" = "$after" ] || fail 'read-only audit changed the temporary HOME'
printf '%s\n' "$healthy_output" | grep -F 'Result:' >/dev/null
printf '%s\n' "$healthy_output" | grep -F '[FAIL]' >/dev/null && fail 'healthy fixture reported a failure'
printf '%s\n' "$healthy_output" | grep -F 'Git user.name is configured' >/dev/null
printf '%s\n' "$healthy_output" | grep -F 'Git core.filemode is configured for the workspace' >/dev/null

warn_output="$(env -i HOME="$home_dir" PATH='/usr/bin:/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace "$workspace" --wsl-conf "$healthy_wsl_conf")"
printf '%s\n' "$warn_output" | grep -F 'duplicate PATH entry: /usr/bin' >/dev/null

fail_output="$(env -i HOME="$home_dir" PATH='/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace /mnt/c/project --wsl-conf "$healthy_wsl_conf")"
printf '%s\n' "$fail_output" | grep -F 'workspace is on a Windows mount' >/dev/null
expect_failure env -i HOME="$home_dir" PATH='/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace /mnt/c/project --wsl-conf "$healthy_wsl_conf" --strict

cat > "$home_dir/.profile" <<'EOF'
export PATH="/mnt/c/Tools:$PATH"
EOF
reference_output="$(env -i HOME="$home_dir" PATH='/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace "$workspace" --wsl-conf "$healthy_wsl_conf")"
printf '%s\n' "$reference_output" | grep -F 'Windows mount reference found without executing' >/dev/null

printf '%s\n' 'if then' > "$home_dir/.bashrc"
syntax_output="$(env -i HOME="$home_dir" PATH='/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace "$workspace" --wsl-conf "$healthy_wsl_conf")"
printf '%s\n' "$syntax_output" | grep -F 'bash syntax check failed' >/dev/null

for invalid_conf in wrong-section duplicate true-value; do
  case "$invalid_conf" in
    wrong-section)
      cat > "$test_dir/$invalid_conf.conf" <<'EOF'
[user]
appendWindowsPath=false
EOF
      ;;
    duplicate)
      cat > "$test_dir/$invalid_conf.conf" <<'EOF'
[interop]
appendWindowsPath=false
appendWindowsPath=false
EOF
      ;;
    true-value)
      cat > "$test_dir/$invalid_conf.conf" <<'EOF'
[interop]
appendWindowsPath=true
EOF
      ;;
  esac
  invalid_output="$(env -i HOME="$home_dir" PATH='/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace "$workspace" --wsl-conf "$test_dir/$invalid_conf.conf")"
  printf '%s\n' "$invalid_output" | grep -F 'does not have exactly one [interop] appendWindowsPath=false setting' >/dev/null
done

custom_wsl_conf="$test_dir/custom-automount.conf"
cat > "$custom_wsl_conf" <<'EOF'
[interop]
appendWindowsPath=false

[automount]
root=/windows/
EOF
custom_output="$(env -i HOME="$home_dir" PATH='/windows/c/bin:/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace /windows/c/project --wsl-conf "$custom_wsl_conf")"
printf '%s\n' "$custom_output" | grep -F 'workspace is on a Windows mount: /windows/c/project' >/dev/null
printf '%s\n' "$custom_output" | grep -F 'Windows PATH entry is visible: /windows/c/bin' >/dev/null

root_wsl_conf="$test_dir/root-automount.conf"
cat > "$root_wsl_conf" <<'EOF'
[interop]
appendWindowsPath=false

[automount]
root=/
EOF
root_output="$(env -i HOME="$home_dir" PATH='/c/bin:/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace /c/project --wsl-conf "$root_wsl_conf")"
printf '%s\n' "$root_output" | grep -F 'workspace is on a Windows mount: /c/project' >/dev/null
printf '%s\n' "$root_output" | grep -F 'Windows PATH entry is visible: /c/bin' >/dev/null
printf '%s\n' "$root_output" | grep -F '/mnt/<drive>' >/dev/null && fail 'Windows-mount OK text was hard-coded to /mnt'

fake_bin="$test_dir/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '9p rw,aname=ordinary'
EOF
chmod 0755 "$fake_bin/findmnt"
ordinary_9p_output="$(env -i HOME="$home_dir" PATH="$fake_bin:/usr/bin:/bin" LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace "$workspace" --wsl-conf "$healthy_wsl_conf")"
printf '%s\n' "$ordinary_9p_output" | grep -F 'workspace is on a Windows mount' >/dev/null && fail 'ordinary 9p mount was treated as Windows'
cat > "$fake_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '9p rw,aname=drvfs'
EOF
chmod 0755 "$fake_bin/findmnt"
drvfs_output="$(env -i HOME="$home_dir" PATH="$fake_bin:/usr/bin:/bin" LANG='C.UTF-8' bash "$script" --home "$home_dir" --workspace "$workspace" --wsl-conf "$healthy_wsl_conf")"
printf '%s\n' "$drvfs_output" | grep -F 'workspace is on a Windows mount' >/dev/null

global_home="$test_dir/global-home"
caller_home="$test_dir/caller-home"
global_workspace="$test_dir/global-workspace"
mkdir -p "$global_home" "$caller_home" "$global_workspace"
env -u GIT_CONFIG_GLOBAL HOME="$global_home" XDG_CONFIG_HOME="$global_home/.config" git config --global user.name 'Global Fixture'
env -u GIT_CONFIG_GLOBAL HOME="$global_home" XDG_CONFIG_HOME="$global_home/.config" git config --global user.email 'global@example.invalid'
global_output="$(env -i HOME="$caller_home" GIT_CONFIG_GLOBAL="$caller_home/ignored.gitconfig" PATH='/usr/bin:/bin' LANG='C.UTF-8' bash "$script" --home "$global_home" --workspace "$global_workspace" --wsl-conf "$healthy_wsl_conf")"
printf '%s\n' "$global_output" | grep -F 'Git user.name is configured' >/dev/null
printf '%s\n' "$global_output" | grep -F 'Git user.email is configured' >/dev/null

printf 'PASS: audit-wsl-startup is read-only and distinguishes healthy, warn, fail, and strict states\n'
